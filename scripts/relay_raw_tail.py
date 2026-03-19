#!/usr/bin/env python3
import argparse
import asyncio
import io
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Optional

import cbor2
import websockets

DEFAULT_ENDPOINT = 'wss://relay1.us-east.bsky.network/xrpc/com.atproto.sync.subscribeRepos'


def build_url(base: str, cursor: Optional[str]) -> str:
    if cursor:
        sep = '&' if '?' in base else '?'
        return f'{base}{sep}cursor={cursor}'
    return base


def detect_native_decoder(root: Path) -> Optional[str]:
    env = os.environ.get('FORTRANSKY_FIREHOSE_DECODER', '').strip()
    candidates = []
    if env:
        candidates.append(env)
    candidates.extend([
        str(root / 'bridge' / 'firehose-bridge' / 'target' / 'release' / 'firehose_bridge_cli'),
        str(root / 'bridge' / 'firehose-bridge' / 'target' / 'debug' / 'firehose_bridge_cli'),
    ])
    for candidate in candidates:
        if candidate and Path(candidate).exists() and os.access(candidate, os.X_OK):
            return candidate
    return shutil.which('firehose_bridge_cli')


def decode_frame_native(raw: bytes, decoder: str) -> list[dict]:
    proc = subprocess.run([decoder], input=raw, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.decode('utf-8', errors='replace').strip() or 'native decoder failed')
    events = []
    for line in proc.stdout.decode('utf-8', errors='replace').splitlines():
        line = line.strip()
        if not line:
            continue
        events.append(json.loads(line))
    return events


def read_varint(buf: bytes, pos: int) -> tuple[int, int]:
    shift = 0
    value = 0
    while True:
        if pos >= len(buf):
            raise ValueError('truncated varint')
        b = buf[pos]
        pos += 1
        value |= (b & 0x7F) << shift
        if not (b & 0x80):
            return value, pos
        shift += 7
        if shift > 63:
            raise ValueError('varint too large')


def read_cid(buf: bytes, pos: int) -> tuple[bytes, int]:
    start = pos
    _, pos = read_varint(buf, pos)
    _, pos = read_varint(buf, pos)
    _, pos = read_varint(buf, pos)
    digest_len, pos = read_varint(buf, pos)
    pos += digest_len
    if pos > len(buf):
        raise ValueError('truncated cid digest')
    return buf[start:pos], pos


def parse_car_v1(car_bytes: bytes) -> dict[bytes, bytes]:
    pos = 0
    header_len, pos = read_varint(car_bytes, pos)
    header_end = pos + header_len
    if header_end > len(car_bytes):
        raise ValueError('truncated car header')
    _header = cbor2.loads(car_bytes[pos:header_end])
    pos = header_end
    blocks: dict[bytes, bytes] = {}
    while pos < len(car_bytes):
        section_len, pos = read_varint(car_bytes, pos)
        section_end = pos + section_len
        if section_end > len(car_bytes):
            raise ValueError('truncated car section')
        section = car_bytes[pos:section_end]
        cid_bytes, data_pos = read_cid(section, 0)
        blocks[cid_bytes] = section[data_pos:]
        pos = section_end
    return blocks


def normalize_event(seq: int, repo: str, path: str, record: dict) -> dict:
    return {
        'kind': 'commit',
        'did': repo,
        'handle': '',
        'text': str(record.get('text', ''))[:1024],
        'time_us': str(seq),
        'uri': f'at://{repo}/{path}',
        'record_type': str(record.get('$type', '')),
        'source': 'relay-raw-python-fallback',
    }


def decode_frame_python(raw: bytes) -> list[dict]:
    decoder = cbor2.CBORDecoder(io.BytesIO(raw))
    header = decoder.decode()
    body = decoder.decode()
    if not isinstance(header, dict) or not isinstance(body, dict):
        return []
    if header.get('t') != '#commit':
        return []
    seq = int(body.get('seq', 0))
    repo = str(body.get('repo', ''))
    ops = body.get('ops', []) or []
    blocks_blob = body.get('blocks', b'') or b''
    if not isinstance(blocks_blob, (bytes, bytearray)):
        return []
    blocks = parse_car_v1(bytes(blocks_blob))
    out: list[dict] = []
    for op in ops:
        if not isinstance(op, dict):
            continue
        if op.get('action') != 'create':
            continue
        path = str(op.get('path', ''))
        if not path.startswith('app.bsky.feed.post/'):
            continue
        cid = op.get('cid', b'')
        if not isinstance(cid, (bytes, bytearray)):
            continue
        block = blocks.get(bytes(cid))
        if not block:
            continue
        record = cbor2.loads(block)
        if not isinstance(record, dict):
            continue
        if record.get('$type') != 'app.bsky.feed.post':
            continue
        out.append(normalize_event(seq, repo, path, record))
    return out


def decode_frame(raw: bytes, root: Path) -> list[dict]:
    decoder = detect_native_decoder(root)
    if decoder:
        return decode_frame_native(raw, decoder)
    return decode_frame_python(raw)


def load_fixture_events(frame_file: Path, root: Path) -> list[dict]:
    return decode_frame(frame_file.read_bytes(), root)


async def load_live_events(url: str, limit: int, root: Path) -> list[dict]:
    collected: list[dict] = []
    async with websockets.connect(url, max_size=2**22, ping_interval=20, ping_timeout=20) as ws:
        async for raw in ws:
            if isinstance(raw, str):
                continue
            try:
                events = decode_frame(raw, root)
            except Exception:
                events = []
            for ev in events:
                collected.append(ev)
                if len(collected) >= limit:
                    return collected
    return collected


async def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--endpoint', default=DEFAULT_ENDPOINT)
    ap.add_argument('--limit', type=int, default=12)
    ap.add_argument('--cursor', default='')
    ap.add_argument('--fixture', default='')
    args = ap.parse_args()

    root = Path(__file__).resolve().parents[1]
    fixture_path = Path(args.fixture) if args.fixture else (root / 'fixtures' / 'relay_commit_frame.bin')
    url = build_url(args.endpoint, args.cursor or None)

    prefer_fixture = os.environ.get('FORTRANSKY_RELAY_FIXTURE', '0').lower() not in {'0', 'false', 'no'}
    events: list[dict] = []
    if not prefer_fixture:
        try:
            events = await load_live_events(url, args.limit, root)
        except Exception as exc:
            sys.stderr.write(f'relay_raw_tail.py live decode failed, falling back to fixture: {exc}\n')
    if not events and fixture_path.exists():
        events = load_fixture_events(fixture_path, root)

    for ev in events[: max(1, args.limit)]:
        sys.stdout.write(json.dumps(ev, ensure_ascii=False) + '\n')
    sys.stdout.flush()
    return 0 if events else 1


if __name__ == '__main__':
    raise SystemExit(asyncio.run(main()))

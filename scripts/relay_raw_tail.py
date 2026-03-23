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
    # Detection order:
    # 1. FORTRANSKY_RELAY_DECODER  — explicit override
    # 2. FORTRANSKY_ASSEMBLERSKY_DECODER — explicit Assemblersky path
    # 3. bridge/assemblersky/bin/assemblersky_cli — bundled Assemblersky
    # 4. assemblersky_cli on PATH
    # 5. FORTRANSKY_FIREHOSE_DECODER — explicit Rust bridge path
    # 6. bridge/firehose-bridge/target/release/firehose_bridge_cli — bundled Rust
    # 7. bridge/firehose-bridge/target/debug/firehose_bridge_cli
    # 8. firehose_bridge_cli on PATH
    candidates = [
        os.environ.get('FORTRANSKY_RELAY_DECODER', '').strip() or None,
        os.environ.get('FORTRANSKY_ASSEMBLERSKY_DECODER', '').strip() or None,
        str(root / 'bridge' / 'assemblersky' / 'bin' / 'assemblersky_cli'),
        shutil.which('assemblersky_cli'),
        os.environ.get('FORTRANSKY_FIREHOSE_DECODER', '').strip() or None,
        str(root / 'bridge' / 'firehose-bridge' / 'target' / 'release' / 'firehose_bridge_cli'),
        str(root / 'bridge' / 'firehose-bridge' / 'target' / 'debug' / 'firehose_bridge_cli'),
        shutil.which('firehose_bridge_cli'),
    ]
    for candidate in candidates:
        if candidate and Path(candidate).exists() and os.access(candidate, os.X_OK):
            return candidate
    return None


def decode_frame_native(raw: bytes, decoder: str) -> list[dict]:
    # assemblersky_cli uses --input FILE; firehose_bridge_cli reads stdin directly
    # Write frame to a temp file for assemblersky_cli
    import tempfile
    if 'assemblersky' in Path(decoder).name:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.bin') as tf:
            tf.write(raw)
            tmp_path = tf.name
        cmd = [decoder, '--input', tmp_path]
    else:
        tmp_path = None
        cmd = [decoder]
    proc = subprocess.run(
        cmd,
        input=raw if tmp_path is None else None,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False
    )
    if tmp_path:
        try:
            import os; os.unlink(tmp_path)
        except OSError:
            pass
    if proc.returncode != 0:
        # rc=1 from assemblersky_cli means no matching op in this frame — not an error
        if tmp_path is not None and proc.returncode == 1:
            return []
        raise RuntimeError(proc.stderr.decode('utf-8', errors='replace').strip() or 'native decoder failed')
    events = []
    output = proc.stdout.decode('utf-8', errors='replace').strip()
    if not output:
        return events
    # Assemblersky emits pretty-printed JSON objects separated by blank lines.
    # firehose_bridge_cli emits compact NDJSON (one object per line).
    # Handle both: try splitting on blank lines first, then fall back to line-by-line.
    def normalise_asb(obj):
        if 'repo' in obj and 'did' not in obj:
            record = obj.get('record', {}) if isinstance(obj.get('record'), dict) else {}
            obj['did'] = obj.get('repo', '')
            obj['handle'] = ''
            obj['text'] = record.get('text', '')
            obj['time_us'] = str(obj.get('seq', ''))
            obj['record_type'] = obj.get('collection', '')
            obj['source'] = 'relay-raw-native'
            obj['error'] = ''
            obj['uri'] = (f"at://{obj['did']}/{obj.get('collection','')}"
                          f"/{obj.get('rkey','')}" )
            obj['record_json'] = record
        return obj

    # Try parsing as a single JSON object (pretty-printed Assemblersky output)
    try:
        obj = json.loads(output)
        events.append(normalise_asb(obj))
        return events
    except json.JSONDecodeError:
        pass

    # Fall back to NDJSON line-by-line (firehose_bridge_cli compact output)
    for line in output.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
            events.append(normalise_asb(obj))
        except Exception:
            continue
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
    # cbor2's streaming decoder has a read-ahead buffer that overshoots the first
    # item. Find the header boundary by trying incremental slices.
    header = None
    header_len = 0
    for n in range(5, min(30, len(raw))):
        try:
            h = cbor2.loads(raw[:n])
            if isinstance(h, dict) and 'op' in h:
                header = h
                header_len = n
                break
        except Exception:
            continue
    if header is None:
        return []
    try:
        body = cbor2.loads(raw[header_len:])
    except Exception:
        return []
    if not isinstance(body, dict):
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
        # cbor2 decodes CIDs as CBORTag(42, bytes) — unwrap the tag value
        if hasattr(cid, 'value'):
            cid = cid.value
        # CID bytes have a leading 0x00 multibase prefix in CBOR — strip it
        if isinstance(cid, (bytes, bytearray)) and len(cid) > 0 and cid[0] == 0:
            cid = cid[1:]
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
    # For live streaming use Python decoder — spawning a subprocess per frame
    # is too slow at firehose rates. Native decoder is used for fixture/single frames.
    return decode_frame_python(raw)


def decode_frame_single(raw: bytes, root: Path) -> list[dict]:
    # For single frame decode (fixture path) prefer native decoder if available
    decoder = detect_native_decoder(root)
    if decoder:
        return decode_frame_native(raw, decoder)
    return decode_frame_python(raw)


def load_fixture_events(frame_file: Path, root: Path) -> list[dict]:
    return decode_frame_single(frame_file.read_bytes(), root)


async def load_live_events(url: str, limit: int, root: Path) -> list[dict]:
    collected: list[dict] = []
    frames_seen = 0
    # Cap total frames scanned to avoid hanging when decoder filters most frames
    max_frames = limit * 500
    async with websockets.connect(url, max_size=2**22, ping_interval=20, ping_timeout=20) as ws:
        async for raw in ws:
            if isinstance(raw, str):
                continue
            frames_seen += 1
            try:
                events = decode_frame(raw, root)
            except Exception as _frame_exc:
                sys.stderr.write('frame decode error: ' + str(_frame_exc) + chr(10))
                events = []
            for ev in events:
                collected.append(ev)
                if len(collected) >= limit:
                    return collected
            if frames_seen >= max_frames:
                break
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

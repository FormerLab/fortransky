#!/usr/bin/env python3
import hashlib
from pathlib import Path
import cbor2


def varint(n: int) -> bytes:
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def cid_for_block(block: bytes) -> bytes:
    digest = hashlib.sha256(block).digest()
    # CIDv1 + dag-cbor + sha2-256
    return bytes([0x01, 0x71, 0x12, 0x20]) + digest


def car_v1_single(blocks: list[tuple[bytes, bytes]]) -> bytes:
    header = cbor2.dumps({"version": 1, "roots": []})
    out = bytearray()
    out.extend(varint(len(header)))
    out.extend(header)
    for cid_bytes, block in blocks:
        section = cid_bytes + block
        out.extend(varint(len(section)))
        out.extend(section)
    return bytes(out)


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    fixtures = root / 'fixtures'
    fixtures.mkdir(parents=True, exist_ok=True)

    record = {
        '$type': 'app.bsky.feed.post',
        'text': 'Synthetic raw relay commit fixture: hello from Fortransky.',
        'createdAt': '2026-03-19T00:00:00.000Z',
    }
    record_block = cbor2.dumps(record)
    record_cid = cid_for_block(record_block)
    car_bytes = car_v1_single([(record_cid, record_block)])

    op = {
        'action': 'create',
        'path': 'app.bsky.feed.post/3lmfixturepost',
        'cid': record_cid,
    }
    body = {
        'seq': 26653242501,
        'repo': 'did:plc:fortranskyfixture000000000000',
        'rev': '3lmfixture-rev',
        'time': '2026-03-19T00:00:00.000Z',
        'ops': [op],
        'blocks': car_bytes,
    }
    header = {'op': 1, 't': '#commit'}
    frame = cbor2.dumps(header) + cbor2.dumps(body)

    (fixtures / 'relay_commit_frame.bin').write_bytes(frame)
    (fixtures / 'relay_commit_expected.jsonl').write_text(
        '{"kind":"commit","did":"did:plc:fortranskyfixture000000000000",'
        '"handle":"","text":"Synthetic raw relay commit fixture: hello from Fortransky.",'
        '"time_us":"26653242501","uri":"at://did:plc:fortranskyfixture000000000000/app.bsky.feed.post/3lmfixturepost"}\n',
        encoding='utf-8',
    )
    print(fixtures / 'relay_commit_frame.bin')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

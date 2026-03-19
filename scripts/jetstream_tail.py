#!/usr/bin/env python3
import argparse
import asyncio
import json
import sys
from typing import Optional

import websockets

DEFAULT_ENDPOINT = "wss://jetstream2.us-east.bsky.network/subscribe"


def build_url(base: str, cursor: Optional[str]) -> str:
    if cursor:
        sep = '&' if '?' in base else '?'
        return f"{base}{sep}cursor={cursor}"
    return base


def simplify(msg: dict) -> dict:
    commit = msg.get("commit") or {}
    record = commit.get("record") or msg.get("record") or {}
    identity = msg.get("identity") or {}
    account = msg.get("account") or {}
    return {
        "kind": msg.get("kind") or msg.get("event") or "event",
        "time_us": str(msg.get("time_us") or msg.get("time") or ""),
        "did": msg.get("did") or account.get("did") or identity.get("did") or "",
        "handle": msg.get("handle") or identity.get("handle") or account.get("handle") or "",
        "text": record.get("text") or msg.get("text") or "",
    }


async def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--endpoint", default=DEFAULT_ENDPOINT)
    ap.add_argument("--limit", type=int, default=12)
    ap.add_argument("--cursor", default="")
    args = ap.parse_args()

    url = build_url(args.endpoint, args.cursor or None)
    count = 0
    try:
        async with websockets.connect(url, max_size=2**20, ping_interval=20, ping_timeout=20) as ws:
            async for raw in ws:
                if isinstance(raw, bytes):
                    try:
                        raw = raw.decode("utf-8", errors="replace")
                    except Exception:
                        continue
                try:
                    msg = json.loads(raw)
                except json.JSONDecodeError:
                    continue
                item = simplify(msg)
                sys.stdout.write(json.dumps(item, ensure_ascii=False) + "\n")
                sys.stdout.flush()
                count += 1
                if count >= args.limit:
                    break
        return 0
    except KeyboardInterrupt:
        return 130
    except Exception as exc:
        sys.stderr.write(f"jetstream_tail.py error: {exc}\n")
        return 1


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))

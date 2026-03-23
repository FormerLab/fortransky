# Fortransky

Yes, that Fortran.

A terminal-only Bluesky / AT Protocol client written in Fortran, with a native
firehose decoder for the `relay-raw` stream path.

Project blog post: https://www.patreon.com/posts/153457794

---

## Architecture

```
Fortran TUI  (src/)
  └─ C libcurl bridge  (cshim/)
  └─ Fortran iso_c_binding module  (src/atproto/firehose_bridge.f90)
       └─ Rust staticlib  (bridge/firehose-bridge/)
            envelope → CAR → DAG-CBOR → NormalizedEvent → JSONL
            + firehose_bridge_cli binary  (used by relay_raw_tail.py)

relay-raw stream path:
  relay_raw_tail.py
    └─ assemblersky_cli  (bridge/assemblersky/bin/)  ← preferred
    └─ firehose_bridge_cli  (bridge/firehose-bridge/target/release/)  ← fallback
    └─ Python cbor2  ← live stream decode
```

Session state is saved to `~/.fortransky/session.json`. Use an app password,
not your main Bluesky password.

---

## Build dependencies

### System packages (Ubuntu/Debian)

```bash
sudo apt install -y gfortran cmake pkg-config libcurl4-openssl-dev
```

### Rust toolchain

Requires rustc >= 1.70. Install via [rustup](https://rustup.rs) if not present:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

### Python deps (relay-raw stream path only)

The `relay_raw_tail.py` helper is launched as a subprocess by the TUI. It must
be able to import `cbor2` and `websockets` using whichever `python3` is on
`PATH` when Fortransky runs.

**Option A — system-wide (simplest):**
```bash
sudo pip install cbor2 websockets --break-system-packages
```

**Option B — venv, run with venv active:**
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install cbor2 websockets
```

### Assemblersky (optional, relay-raw native decoder)

Assemblersky is an x86-64 assembly AT Protocol firehose decoder.
If the binary is present at `bridge/assemblersky/bin/assemblersky_cli`,
`relay_raw_tail.py` will use it automatically for single-frame decode.

Build from source: https://github.com/FormerLab/assemblersky

```bash
cd /path/to/assemblersky
make
mkdir -p /path/to/fortransky/bridge/assemblersky/bin
cp rust-harness/target/release/assemblersky-harness \
   /path/to/fortransky/bridge/assemblersky/bin/assemblersky_cli
```

Check detection: `./scripts/check_assemblersky.sh`

---

## Build

```bash
./scripts/build.sh
./build/fortransky
```

---

## Login

Use an [app password](https://bsky.app/settings/app-passwords). At the home prompt:

```
l
Identifier: yourhandle.bsky.social
Password/app password: <app password>
```

Session is saved to `~/.fortransky/session.json` and restored on next launch.
To log out: `x`

---

## TUI commands

### Home view

| Command | Action |
|---------|--------|
| `l` | login + fetch timeline |
| `x` | logout + clear saved session |
| `a <handle>` | author feed |
| `s <query>` | search posts |
| `p <handle>` | profile view |
| `n` | notifications |
| `c` | compose post |
| `t <uri/url>` | open thread |
| `j` | stream tail |
| `m` | toggle stream mode (jetstream / relay-raw) |
| `q` | quit |

### Post list view

| Command | Action |
|---------|--------|
| `j` / `k` | move selection |
| `n` / `p` | next / previous page |
| `o` | open selected thread |
| `r` | reply to selected post |
| `l` | like selected post |
| `R` | repost selected post |
| `q` | quote-post |
| `P` | open author profile |
| `/query` | search |
| `b` | back to home |

### Stream view

| Command | Action |
|---------|--------|
| `j` | refresh |
| `b` | back |

---

## Stream modes

**jetstream** — Bluesky's Jetstream WebSocket service. Lower bandwidth, JSON
native, easiest to work with.

**relay-raw** — raw AT Protocol relay (`com.atproto.sync.subscribeRepos`).
Binary CBOR frames over WebSocket, decoded in Python with cbor2. The native
Assemblersky decoder (x86-64 assembly) is used when available for single-frame
decode; the Rust `firehose_bridge_cli` is the fallback.

### Native decoder detection order

1. `FORTRANSKY_RELAY_DECODER` environment variable
2. `FORTRANSKY_ASSEMBLERSKY_DECODER` environment variable
3. `bridge/assemblersky/bin/assemblersky_cli` (bundled Assemblersky)
4. `assemblersky_cli` on `PATH`
5. `FORTRANSKY_FIREHOSE_DECODER` environment variable
6. `bridge/firehose-bridge/target/release/firehose_bridge_cli`
7. `bridge/firehose-bridge/target/debug/firehose_bridge_cli`
8. `firehose_bridge_cli` on `PATH`

### Offline fixture testing

```bash
printf 'b\nm\nj\nb\nq\n' | ./build/fortransky
```

---

## Known issues / notes

- JSON parser is hand-rolled and lightweight — not a full schema-driven parser
- `relay-raw` only surfaces `app.bsky.feed.post` create ops
- Stream view shows raw DIDs; handle resolution is done where available
- The TUI is line-based (type command + Enter), not raw keypress
- `m` and `j` for stream control are home view commands — go `b` back to home
  first if you are in the post list

---

## Changelog

**v1.2** — Assemblersky integration. `relay_raw_tail.py` detects and prefers
`assemblersky_cli` over the Rust bridge. Live relay-raw decode via Python cbor2
(CBOR tag / CIDv1 handling fixed). Decoder detection order documented.

**v1.1** — Native Rust firehose decoder integrated. `relay_raw_tail.py` prefers
`firehose_bridge_cli` when found. CMakeLists wires Rust staticlib into the
Fortran link. JWT field lengths bumped to 1024. JSON key scanner depth-tracking
fix.

**v1.0** — Like, repost, quote-post actions. URL facet emission.

**v0.9** — Typed decode layer (`decode.f90`). Richer post semantics in TUI.

**v0.7** — C libcurl bridge replacing shell curl. Saved session support.
Stream mode toggle (jetstream / relay-raw).
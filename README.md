# Fortransky 

Yes, that Fortran.

A terminal-only Bluesky / AT Protocol client written in Fortran, with a Rust
native firehose decoder for the `relay-raw` stream path.

## Architecture

```
Fortran TUI  (src/)
  └─ C libcurl bridge  (cshim/)
  └─ Fortran iso_c_binding module  (src/atproto/firehose_bridge.f90)
       └─ Rust staticlib  (bridge/firehose-bridge/)
            envelope → CAR → DAG-CBOR → NormalizedEvent → JSONL
            + firehose_bridge_cli binary  (used by relay_raw_tail.py)
```

Session state is saved in `~/.fortransky/session.json`. Use an app password,
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
`PATH` at the time Fortransky runs — not just in an active venv.

**Option A — system-wide (simplest):**
```bash
sudo pip install cbor2 websockets --break-system-packages
```

**Option B — venv, then symlink or alias:**
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install cbor2 websockets
```
Then either run Fortransky with the venv active, or set:
```bash
export FORTRANSKY_RELAY_PYTHON=$PWD/.venv/bin/python3
```
(support for this env var is planned)

---

## Build

```bash
./scripts/build.sh
```

This builds the Rust bridge first (`cargo build --release`), then runs CMake.
The Rust step is skipped on subsequent builds if nothing changed.

```bash
./build/fortransky
```

---

## Login

Use an [app password](https://bsky.app/settings/app-passwords) created for
Fortransky specifically. At the home prompt:

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

### Notifications view

| Command | Action |
|---------|--------|
| `j` / `k` | move selection |
| `n` / `p` | next / previous page |
| `o` | open thread |
| `r` | reply |
| `b` | back |

### Stream view

| Command | Action |
|---------|--------|
| `j` | refresh |
| `b` | back |

---

## Stream modes

**jetstream** — connects to Bluesky's Jetstream WebSocket service. Lower
bandwidth, JSON native, easiest to work with.

**relay-raw** — connects to the raw AT Protocol relay
(`com.atproto.sync.subscribeRepos`). Frames are binary CBOR over WebSocket.
The native Rust decoder (`firehose_bridge_cli`) handles envelope → CAR →
DAG-CBOR → normalized JSON. Python cbor2 fallback remains for fixture mode.

### Native decoder detection order

1. `FORTRANSKY_FIREHOSE_DECODER` environment variable
2. `bridge/firehose-bridge/target/release/firehose_bridge_cli`
3. `bridge/firehose-bridge/target/debug/firehose_bridge_cli`
4. `firehose_bridge_cli` on `PATH`

### Relay fixture (offline testing)

By default relay-raw uses a bundled synthetic fixture. To use the live relay:

```bash
FORTRANSKY_RELAY_FIXTURE=0 ./build/fortransky
```

Quick offline demo:

```bash
printf 'b\nm\nj\nb\nq\n' | ./build/fortransky
```

---

## Known issues / notes

- JSON parser is hand-rolled and lightweight — not a full schema-driven parser
- `relay-raw` only surfaces `app.bsky.feed.post` create ops; other collections
  are filtered out at the normalize stage
- Stream view shows raw DIDs; handle resolution (DID → handle lookup) is not
  yet implemented
- The TUI is line-based (type command + Enter), not raw keypress
- `m` and `j` for stream control are home view commands — go `b` back to home
  first if you are in the post list

---

## Changelog

**v1.1** — Native Rust firehose decoder integrated. `relay_raw_tail.py` prefers
`firehose_bridge_cli` when found. CMakeLists wires Rust staticlib into the
Fortran link. JWT field lengths bumped to 1024 to fit full AT Protocol tokens.
JSON key scanner depth-tracking fix (was matching nested keys before top-level
`feed` array).

**v1.0** — Like, repost, quote-post actions. URL facet emission.

**v0.9** — Typed decode layer (`decode.f90`). Richer post semantics in TUI.

**v0.7** — C libcurl bridge replacing shell curl. Saved session support.
Stream mode toggle (jetstream / relay-raw).

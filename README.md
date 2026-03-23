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

image post path  (d <imagepath>):
  dither_prep.py      image → greyscale flat pixel file
  dither.f90          Floyd-Steinberg error diffusion (Bill Atkinson's algorithm)
  pixels_to_png.py    pixel file → PNG
  uploadBlob          PNG → Bluesky blob
  createRecord        post with app.bsky.embed.images
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

### Python deps

Required for relay-raw stream path and image posting:

```bash
sudo pip install cbor2 websockets Pillow --break-system-packages
```

Or with a venv (run Fortransky with the venv active):

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install cbor2 websockets Pillow
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
| `d <imagepath>` | dither image + post to Bluesky |
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

## Image posting

The `d` command dithers any image using Bill Atkinson's Floyd-Steinberg
algorithm (as used in MacPaint, 1984) and posts it to Bluesky.

```
d /path/to/image.jpg
```

The image is converted to greyscale, resized to 576×720 (the original MacPaint
canvas dimensions), dithered to 1-bit in Fortran, converted to PNG, and posted
with an image embed. Pillow is required.

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

**v1.3** — Floyd-Steinberg dithering + image post via `d <imagepath>`. Bill
Atkinson's algorithm (MacPaint, 1984) ported to Fortran. `uploadBlob` +
`createRecord` with image embed wired into the AT Protocol client. Requires
Pillow.

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
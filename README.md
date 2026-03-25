# Fortransky

Yes, that Fortran.

A terminal-only Bluesky / AT Protocol client written in Fortran. Posts, timelines,
notifications, dithered image posting, DMs, and terminal image rendering — all from
an amber terminal (if you run it in cool-retro-term), all the way down to the protocol

Project blog: https://www.patreon.com/posts/153457794

---

## Architecture

```
Fortran TUI  (src/)
  └─ C libcurl bridge  (cshim/)
  └─ Fortran iso_c_binding module  (src/atproto/firehose_bridge.f90)
       └─ Rust staticlib  (bridge/firehose-bridge/)
            envelope → CAR → DAG-CBOR → NormalizedEvent → JSONL

relay-raw stream path:
  relay_raw_tail.py
    └─ assemblersky_cli  (bridge/assemblersky/bin/)  ← x86-64 assembly decoder
    └─ firehose_bridge_cli  (bridge/firehose-bridge/target/release/)  ← Rust fallback
    └─ Python cbor2  ← live stream decode (CBORTag/CIDv1 aware)

image post path  (d <imagepath>):
  dither_prep.py    image → greyscale flat pixel file
  dither.f90        Floyd-Steinberg error diffusion in Fortran
  pixels_to_png.py  pixel file → PNG
  uploadBlob        PNG → AT Protocol blob
  createRecord      post with app.bsky.embed.images

image view path  (v on a post with image):
  CDN blob fetch    download fullsize image via http_get_to_file
  dither_prep.py    greyscale + resize to 80×48 for terminal
  dither.f90        Floyd-Steinberg in Fortran
  render            Unicode half-block chars (▀ ▄ █) — 80×48 effective pixels

DM path  (dm <handle>, i):
  getConvoForMembers  resolve or create conversation
  getMessages         fetch message thread
  sendMessage         send a DM
  All routed via atproto-proxy header to did:web:api.bsky.chat
  PDS host resolved automatically from plc.directory on login
```

Session state is saved to `~/.fortransky/session.json`. Use an app password
with DM access enabled, not your main Bluesky password.

---

## Build dependencies

### System packages (Ubuntu/Debian)

```bash
sudo apt install -y gfortran cmake pkg-config libcurl4-openssl-dev
```

### System packages (Arch/Garuda)

```bash
sudo pacman -S gcc-fortran cmake pkgconf curl python-pillow python-cbor2 python-websockets
```

### Rust toolchain

Requires rustc >= 1.78 (Cargo.lock v4). Latest stable recommended. Install via [rustup](https://rustup.rs) if not present:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

### Python deps

Required for relay-raw stream path, image posting, and image viewing:

```bash
sudo pip install cbor2 websockets Pillow --break-system-packages
```

Or with a venv (run Fortransky with the venv active):

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install cbor2 websockets Pillow
```

### Assemblersky integrated in Fortransky (relay-raw native decoder)

Assemblersky decodes raw AT Protocol firehose frames in x86-64 assembly.
If present at `bridge/assemblersky/bin/assemblersky_cli`, it is preferred
automatically.

Assemblersky module repo is not public yet, but here is how to do it later when shipped separately:

Build from source: https://github.com/FormerLab/assemblersky

```bash
cd /path/to/assemblersky && make
mkdir -p /path/to/fortransky/bridge/assemblersky/bin
cp rust-harness/target/release/assemblersky-harness \
   /path/to/fortransky/bridge/assemblersky/bin/assemblersky_cli
```

Check detection: `./scripts/check_assemblersky.sh`

---

## Build

chmod and 

```bash
./scripts/build.sh
./build/fortransky
```

---

## Login

Use an [app password](https://bsky.app/settings/app-passwords) with DM access
enabled. At the home prompt:

```
l
Identifier: yourhandle.bsky.social
Password/app password: <app password>
```

Session is saved to `~/.fortransky/session.json` and restored on next launch.
Your real PDS host is resolved from `plc.directory` on first login and stored
in the session — required for DMs and other PDS-proxied endpoints.
To log out: `x`

---

## TUI commands (only TUI here)

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
| `i` | DM inbox |
| `dm <handle>` | open or start a DM conversation |
| `t <uri/url>` | open thread |
| `j` | stream tail |
| `m` | toggle stream mode (jetstream / relay-raw) |
| `q` | quit |

### Post list view

| Command | Action |
|---------|--------|
| `j` / `k` | move selection |
| `n` / `p` | next / previous page |
| `o` | open thread |
| `v` | view image (dithered, half-block render) |
| `r` | reply to selected post |
| `l` | like selected post |
| `R` | repost selected post |
| `q` | quote-post |
| `P` | open author profile |
| `/query` | search |
| `b` | back to home |

### DM thread view

| Command | Action |
|---------|--------|
| `r` | reply (send message) |
| `j` | refresh messages |
| `b` | back |

### Stream view

| Command | Action |
|---------|--------|
| `j` | refresh |
| `b` | back |

---

## Image posting

The `d` command dithers any image using Bill Atkinson's Floyd-Steinberg
algorithm — the same algorithm used in MacPaint in 1984 — and posts it
to Bluesky as an image embed.

```
d /path/to/image.jpg
```

The image is converted to greyscale, resized to 576×720 (the original MacPaint
canvas dimensions), dithered to 1-bit in Fortran, converted to PNG, and posted
via `com.atproto.repo.uploadBlob` + `createRecord`. Pillow is required.

---

## Image viewing

The `v` command on any post with an image fetches the image from the Bluesky
CDN, dithers it in Fortran, and renders it inline using Unicode half-block
characters (`▀` `▄` `█`).

Each terminal character represents two pixel rows — top half and bottom half —
giving 80×48 effective pixels in a standard 80-column terminal. The same
Floyd-Steinberg algorithm used for posting is used for display.

---

## DMs

Fortransky implements `chat.bsky.convo.*` — the same DM protocol used by the
official Bluesky app. Requests are proxied through your PDS to
`did:web:api.bsky.chat` via the `atproto-proxy` header.

Your app password must have DM access enabled (the "Allow access to your direct
messages" toggle in Bluesky's app password settings).

PDS host is resolved automatically from `plc.directory` on login and stored in
the session file — no manual configuration needed.

---

## Stream modes

**jetstream** — Bluesky's Jetstream WebSocket service. Lower bandwidth, JSON
native, easiest to work with...

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

---

## Known issues / notes

- JSON parser is hand-rolled — not a full schema-driven parser
- `relay-raw` only surfaces `app.bsky.feed.post` create ops
- DM thread view shows raw DIDs; handle resolution coming in a future version
- The TUI is line-based (type command + Enter), not raw keypress
- `m` and `j` for stream control are home view commands — go `b` back to home
  first if you are in the post list

---

## Changelog

**v1.5** — Terminal image viewer via `v` command. Fetches image from Bluesky
CDN, dithers with Floyd-Steinberg in Fortran, renders using Unicode half-block
characters (80×48 effective pixels). Deep JSON key extraction added to
`json_extract_mod` for nested embed fields.

**v1.4** — DM support via `chat.bsky.convo.*`. `dm <handle>` opens or creates
a conversation, `i` lists the inbox, `r` sends a reply. PDS host auto-resolved
from `plc.directory` on login. `atproto-proxy` header routing to
`did:web:api.bsky.chat`. App password requires DM access enabled.

**v1.3** — Floyd-Steinberg dithering + image post via `d <imagepath>`. Bill
Atkinson's algorithm (MacPaint, 1984) ported to Fortran. `uploadBlob` +
`createRecord` with image embed. Requires Pillow.

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
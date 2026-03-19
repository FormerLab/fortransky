# Suggested Fixture Set

Capture and store raw websocket frames for at least these cases:

1. `#commit` with one `create app.bsky.feed.post`
2. `#commit` with one `create like`
3. `#commit` with one `delete follow`
4. `#identity`
5. `#account`
6. error frame (`op = -1`)

Then assert:
- envelope decode works
- commit metadata matches expected values
- CAR block lookup resolves the expected record block
- DAG-CBOR JSON contains post `text`
- normalize emits exactly one `fs_event_t` for the post-create fixture

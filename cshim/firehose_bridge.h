#ifndef FORTRANSKY_FIREHOSE_BRIDGE_H
#define FORTRANSKY_FIREHOSE_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    FS_OK = 0,
    FS_ERR_CBOR = 1,
    FS_ERR_ENVELOPE = 2,
    FS_ERR_COMMIT_PARSE = 3,
    FS_ERR_CAR_PARSE = 4,
    FS_ERR_DAGCBOR_PARSE = 5,
    FS_ERR_UNSUPPORTED = 6,
    FS_ERR_OOM = 7,
    FS_ERR_INTERNAL = 8
};

enum {
    FS_KIND_COMMIT_OP = 1,
    FS_KIND_IDENTITY = 2,
    FS_KIND_ACCOUNT = 3,
    FS_KIND_INFO = 4,
    FS_KIND_ERROR = 5
};

enum {
    FS_OP_NONE = 0,
    FS_OP_CREATE = 1,
    FS_OP_UPDATE = 2,
    FS_OP_DELETE = 3
};

typedef struct {
    int64_t seq;
    int32_t kind;
    int32_t op_action;
    const char *repo_did;
    const char *rev;
    const char *collection;
    const char *rkey;
    const char *record_cid;
    const char *uri;
    const char *record_json;
    const char *error_message;
} fs_event_t;

typedef struct {
    fs_event_t *events;
    size_t len;
    void *owner;
} fs_event_batch_t;

int fs_decoder_init(void);
void fs_decoder_shutdown(void);
int fs_decode_frame(const uint8_t *data, size_t len, fs_event_batch_t *out_batch);
void fs_free_batch(fs_event_batch_t *batch);

#ifdef __cplusplus
}
#endif

#endif

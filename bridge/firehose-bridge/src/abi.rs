use libc::{c_char, c_int, c_void, size_t};
use std::ffi::CString;
use std::ptr;

pub const FS_OK: c_int = 0;
pub const FS_ERR_CBOR: c_int = 1;
pub const FS_ERR_ENVELOPE: c_int = 2;
pub const FS_ERR_COMMIT_PARSE: c_int = 3;
pub const FS_ERR_CAR_PARSE: c_int = 4;
pub const FS_ERR_DAGCBOR_PARSE: c_int = 5;
pub const FS_ERR_UNSUPPORTED: c_int = 6;
pub const FS_ERR_OOM: c_int = 7;
pub const FS_ERR_INTERNAL: c_int = 8;

pub const FS_KIND_COMMIT_OP: c_int = 1;
pub const FS_KIND_IDENTITY: c_int = 2;
pub const FS_KIND_ACCOUNT: c_int = 3;
pub const FS_KIND_INFO: c_int = 4;
pub const FS_KIND_ERROR: c_int = 5;

pub const FS_OP_NONE: c_int = 0;
pub const FS_OP_CREATE: c_int = 1;
pub const FS_OP_UPDATE: c_int = 2;
pub const FS_OP_DELETE: c_int = 3;

#[repr(C)]
pub struct fs_event_t {
    pub seq: i64,
    pub kind: c_int,
    pub op_action: c_int,
    pub repo_did: *const c_char,
    pub rev: *const c_char,
    pub collection: *const c_char,
    pub rkey: *const c_char,
    pub record_cid: *const c_char,
    pub uri: *const c_char,
    pub record_json: *const c_char,
    pub error_message: *const c_char,
}

#[repr(C)]
pub struct fs_event_batch_t {
    pub events: *mut fs_event_t,
    pub len: size_t,
    pub owner: *mut c_void,
}

#[derive(Debug, Clone)]
pub struct NormalizedEvent {
    pub seq: i64,
    pub kind: i32,
    pub op_action: i32,
    pub repo_did: Option<String>,
    pub rev: Option<String>,
    pub collection: Option<String>,
    pub rkey: Option<String>,
    pub record_cid: Option<String>,
    pub uri: Option<String>,
    pub record_json: Option<String>,
    pub error_message: Option<String>,
}

struct OwnedCEvent {
    ev: fs_event_t,
    owned_strings: Vec<CString>,
}

#[repr(C)]
pub struct BatchOwner {
    events: Vec<fs_event_t>,
    _strings_per_event: Vec<Vec<CString>>,
}

fn safe_cstring(s: &str) -> CString {
    match CString::new(s) {
        Ok(v) => v,
        Err(_) => CString::new(s.replace('\0', "�")).unwrap_or_else(|_| CString::new("<invalid>").unwrap()),
    }
}

fn opt_cstr(src: &Option<String>, owned: &mut Vec<CString>) -> *const c_char {
    match src {
        Some(s) => {
            let c = safe_cstring(s);
            let p = c.as_ptr();
            owned.push(c);
            p
        }
        None => ptr::null(),
    }
}

fn to_owned_cevent(src: NormalizedEvent) -> OwnedCEvent {
    let mut owned_strings = Vec::new();
    let ev = fs_event_t {
        seq: src.seq,
        kind: src.kind,
        op_action: src.op_action,
        repo_did: opt_cstr(&src.repo_did, &mut owned_strings),
        rev: opt_cstr(&src.rev, &mut owned_strings),
        collection: opt_cstr(&src.collection, &mut owned_strings),
        rkey: opt_cstr(&src.rkey, &mut owned_strings),
        record_cid: opt_cstr(&src.record_cid, &mut owned_strings),
        uri: opt_cstr(&src.uri, &mut owned_strings),
        record_json: opt_cstr(&src.record_json, &mut owned_strings),
        error_message: opt_cstr(&src.error_message, &mut owned_strings),
    };
    OwnedCEvent { ev, owned_strings }
}

pub fn build_batch(events: Vec<NormalizedEvent>, out_batch: *mut fs_event_batch_t) -> Result<c_int, c_int> {
    if out_batch.is_null() {
        return Err(FS_ERR_INTERNAL);
    }

    let mut out_events = Vec::with_capacity(events.len());
    let mut string_bins = Vec::with_capacity(events.len());

    for e in events {
        let OwnedCEvent { ev, owned_strings } = to_owned_cevent(e);
        out_events.push(ev);
        string_bins.push(owned_strings);
    }

    let mut owner = Box::new(BatchOwner { events: out_events, _strings_per_event: string_bins });
    let events_ptr = owner.events.as_mut_ptr();
    let len = owner.events.len();
    let owner_ptr = Box::into_raw(owner) as *mut c_void;

    unsafe {
        (*out_batch).events = events_ptr;
        (*out_batch).len = len;
        (*out_batch).owner = owner_ptr;
    }

    Ok(FS_OK)
}

pub fn build_error_batch(message: impl Into<String>, out_batch: *mut fs_event_batch_t) -> c_int {
    let events = vec![NormalizedEvent {
        seq: 0,
        kind: FS_KIND_ERROR,
        op_action: FS_OP_NONE,
        repo_did: None,
        rev: None,
        collection: None,
        rkey: None,
        record_cid: None,
        uri: None,
        record_json: None,
        error_message: Some(message.into()),
    }];

    match build_batch(events, out_batch) {
        Ok(code) => code,
        Err(code) => code,
    }
}

#[no_mangle]
pub extern "C" fn fs_decoder_init() -> c_int { FS_OK }

#[no_mangle]
pub extern "C" fn fs_decoder_shutdown() {}

#[no_mangle]
pub extern "C" fn fs_decode_frame(data: *const u8, len: size_t, out_batch: *mut fs_event_batch_t) -> c_int {
    if out_batch.is_null() {
        return FS_ERR_INTERNAL;
    }
    unsafe {
        (*out_batch).events = ptr::null_mut();
        (*out_batch).len = 0;
        (*out_batch).owner = ptr::null_mut();
    }
    if data.is_null() {
        return build_error_batch("null frame pointer", out_batch);
    }

    let bytes = unsafe { std::slice::from_raw_parts(data, len) };
    match crate::decoder::decode_frame(bytes) {
        Ok(events) => match build_batch(events, out_batch) { Ok(code) => code, Err(code) => code },
        Err(err) => {
            let code = crate::decoder::map_error_to_code(&err);
            let _ = build_error_batch(err.to_string(), out_batch);
            code
        }
    }
}

#[no_mangle]
pub extern "C" fn fs_free_batch(batch: *mut fs_event_batch_t) {
    if batch.is_null() { return; }
    unsafe {
        if !(*batch).owner.is_null() {
            let _owner: Box<BatchOwner> = Box::from_raw((*batch).owner as *mut BatchOwner);
            (*batch).owner = ptr::null_mut();
        }
        (*batch).events = ptr::null_mut();
        (*batch).len = 0;
    }
}

use anyhow::Result;

#[derive(thiserror::Error, Debug)]
pub enum DecodeError {
    #[error("CBOR decode failed: {0}")]
    Cbor(String),
    #[error("envelope decode failed: {0}")]
    Envelope(String),
    #[error("commit decode failed: {0}")]
    Commit(String),
    #[error("CAR parse failed: {0}")]
    Car(String),
    #[error("DAG-CBOR decode failed: {0}")]
    DagCbor(String),
    #[error("unsupported frame: {0}")]
    Unsupported(String),
    #[error("internal error: {0}")]
    Internal(String),
}

pub fn decode_frame(bytes: &[u8]) -> Result<Vec<crate::abi::NormalizedEvent>, DecodeError> {
    let env = crate::envelope::decode_envelope(bytes).map_err(|e| DecodeError::Envelope(e.to_string()))?;
    match env {
        crate::envelope::Envelope::Commit(commit_env) => {
            let commit = crate::commit::decode_commit(commit_env).map_err(|e| {
                let msg = e.to_string();
                if msg.to_ascii_lowercase().contains("car") {
                    DecodeError::Car(msg)
                } else if msg.to_ascii_lowercase().contains("dag-cbor") {
                    DecodeError::DagCbor(msg)
                } else {
                    DecodeError::Commit(msg)
                }
            })?;
            crate::normalize::normalize_commit(commit).map_err(|e| DecodeError::Internal(e.to_string()))
        }
        crate::envelope::Envelope::Info(info) => Ok(vec![crate::abi::NormalizedEvent {
            seq: info.seq.unwrap_or(0),
            kind: crate::abi::FS_KIND_INFO,
            op_action: crate::abi::FS_OP_NONE,
            repo_did: None,
            rev: None,
            collection: None,
            rkey: None,
            record_cid: None,
            uri: None,
            record_json: info.payload_json,
            error_message: None,
        }]),
        crate::envelope::Envelope::Unknown => Err(DecodeError::Unsupported("unrecognized event-stream frame".into())),
    }
}

pub fn map_error_to_code(err: &DecodeError) -> libc::c_int {
    match err {
        DecodeError::Cbor(_) => crate::abi::FS_ERR_CBOR,
        DecodeError::Envelope(_) => crate::abi::FS_ERR_ENVELOPE,
        DecodeError::Commit(_) => crate::abi::FS_ERR_COMMIT_PARSE,
        DecodeError::Car(_) => crate::abi::FS_ERR_CAR_PARSE,
        DecodeError::DagCbor(_) => crate::abi::FS_ERR_DAGCBOR_PARSE,
        DecodeError::Unsupported(_) => crate::abi::FS_ERR_UNSUPPORTED,
        DecodeError::Internal(_) => crate::abi::FS_ERR_INTERNAL,
    }
}

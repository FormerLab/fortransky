use anyhow::Result;
use serde_json::Value;

use crate::abi::{NormalizedEvent, FS_KIND_COMMIT_OP, FS_OP_CREATE, FS_OP_DELETE, FS_OP_UPDATE};

pub fn normalize_commit(commit: crate::commit::DecodedCommit) -> Result<Vec<NormalizedEvent>> {
    let mut out = Vec::new();

    for op in commit.ops {
        let (collection, rkey) = split_repo_path(&op.path);
        let action = match op.action.as_str() {
            "create" => FS_OP_CREATE,
            "update" => FS_OP_UPDATE,
            "delete" => FS_OP_DELETE,
            _ => 0,
        };

        if action != FS_OP_CREATE {
            continue;
        }

        if collection.as_deref() != Some("app.bsky.feed.post") {
            continue;
        }

        let uri = match (&collection, &rkey) {
            (Some(c), Some(r)) => Some(format!("at://{}/{}/{}", commit.repo, c, r)),
            _ => None,
        };

        let record_json = sanitize_post_record_json(op.record_json.as_deref());

        out.push(NormalizedEvent {
            seq: commit.seq,
            kind: FS_KIND_COMMIT_OP,
            op_action: action,
            repo_did: Some(commit.repo.clone()),
            rev: Some(commit.rev.clone()),
            collection,
            rkey,
            record_cid: op.cid.clone(),
            uri,
            record_json,
            error_message: None,
        });
    }

    Ok(out)
}

fn split_repo_path(path: &str) -> (Option<String>, Option<String>) {
    let mut parts = path.split('/');
    let collection = parts.next().map(|s| s.to_string());
    let rkey = parts.next().map(|s| s.to_string());
    (collection, rkey)
}

fn sanitize_post_record_json(src: Option<&str>) -> Option<String> {
    let Some(src) = src else { return None; };
    let Ok(mut value) = serde_json::from_str::<Value>(src) else {
        return Some(src.to_string());
    };

    if let Value::Object(obj) = &mut value {
        if !obj.contains_key("$type") {
            obj.insert("$type".to_string(), Value::String("app.bsky.feed.post".to_string()));
        }
        if let Some(text) = obj.get("text") {
            if !text.is_string() {
                obj.insert("text".to_string(), Value::String(text.to_string()));
            }
        }
    }

    serde_json::to_string(&value).ok()
}

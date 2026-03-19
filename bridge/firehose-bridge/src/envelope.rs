use anyhow::{anyhow, bail, Result};
use ciborium::value::Value;
use std::io::Cursor;

#[derive(Debug, Clone)]
pub struct CommitOpRef {
    pub action: String,
    pub path: String,
    pub cid: Option<String>,
}

#[derive(Debug, Clone)]
pub struct CommitEnvelope {
    pub seq: i64,
    pub repo: String,
    pub rev: String,
    pub ops: Vec<CommitOpRef>,
    pub blocks: Vec<u8>,
}

#[derive(Debug, Clone)]
pub struct InfoEnvelope {
    pub seq: Option<i64>,
    pub payload_json: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Envelope {
    Commit(CommitEnvelope),
    Info(InfoEnvelope),
    Unknown,
}

#[derive(Debug, Clone)]
struct FrameHeader {
    op: i64,
    t: Option<String>,
}

pub fn decode_envelope(bytes: &[u8]) -> Result<Envelope> {
    if bytes.is_empty() {
        bail!("empty frame")
    }

    let mut cur = Cursor::new(bytes);
    let header_v: Value = ciborium::de::from_reader(&mut cur).map_err(|e| anyhow!("header CBOR decode failed: {e}"))?;
    let body_v: Value = ciborium::de::from_reader(&mut cur).map_err(|e| anyhow!("body CBOR decode failed: {e}"))?;
    let header = parse_header(&header_v)?;

    match header.op {
        1 => match header.t.as_deref() {
            Some("#commit") => Ok(Envelope::Commit(parse_commit(&body_v)?)),
            Some("#info") | Some("#identity") | Some("#account") | Some("#sync") => {
                let payload_json = serde_json::to_string(&crate::dagcbor::value_to_json(&body_v)).ok();
                let seq = get_i64_field(&body_v, "seq");
                Ok(Envelope::Info(InfoEnvelope { seq, payload_json }))
            }
            Some(other) => Ok(Envelope::Info(InfoEnvelope {
                seq: get_i64_field(&body_v, "seq"),
                payload_json: Some(format!("{{\"eventType\":{}}}", serde_json::to_string(other)?)),
            })),
            None => Ok(Envelope::Unknown),
        },
        -1 => {
            let payload_json = serde_json::to_string(&crate::dagcbor::value_to_json(&body_v)).ok();
            Ok(Envelope::Info(InfoEnvelope { seq: None, payload_json }))
        }
        _ => Ok(Envelope::Unknown),
    }
}

fn parse_header(v: &Value) -> Result<FrameHeader> {
    Ok(FrameHeader {
        op: get_i64_field(v, "op").ok_or_else(|| anyhow!("missing header.op"))?,
        t: get_string_field(v, "t"),
    })
}

fn parse_commit(v: &Value) -> Result<CommitEnvelope> {
    let seq = get_i64_field(v, "seq").ok_or_else(|| anyhow!("commit missing seq"))?;
    let repo = get_string_field(v, "repo").ok_or_else(|| anyhow!("commit missing repo"))?;
    let rev = get_string_field(v, "rev").ok_or_else(|| anyhow!("commit missing rev"))?;
    let blocks = get_bytes_field(v, "blocks").ok_or_else(|| anyhow!("commit missing blocks bytes"))?;
    let ops_v = get_field(v, "ops").ok_or_else(|| anyhow!("commit missing ops"))?;
    let mut ops = Vec::new();
    if let Value::Array(items) = ops_v {
        for item in items {
            let action = get_string_field(item, "action").or_else(|| get_string_field(item, "op")).unwrap_or_else(|| "unknown".to_string());
            let path = get_string_field(item, "path").ok_or_else(|| anyhow!("commit op missing path"))?;
            let cid = get_cid_like_field(item, "cid");
            ops.push(CommitOpRef { action, path, cid });
        }
    } else {
        bail!("commit.ops is not an array")
    }

    Ok(CommitEnvelope { seq, repo, rev, ops, blocks })
}

pub fn get_field<'a>(v: &'a Value, name: &str) -> Option<&'a Value> {
    let Value::Map(entries) = v else { return None; };
    entries.iter().find_map(|(k, vv)| match k {
        Value::Text(s) if s == name => Some(vv),
        _ => None,
    })
}

pub fn get_string_field(v: &Value, name: &str) -> Option<String> {
    match get_field(v, name)? {
        Value::Text(s) => Some(s.clone()),
        _ => None,
    }
}

pub fn get_i64_field(v: &Value, name: &str) -> Option<i64> {
    match get_field(v, name)? {
        Value::Integer(i) => i64::try_from(*i).ok(),
        _ => None,
    }
}

pub fn get_bytes_field(v: &Value, name: &str) -> Option<Vec<u8>> {
    match get_field(v, name)? {
        Value::Bytes(b) => Some(b.clone()),
        _ => None,
    }
}

pub fn get_cid_like_field(v: &Value, name: &str) -> Option<String> {
    crate::dagcbor::value_to_cid_string(get_field(v, name)?)
}

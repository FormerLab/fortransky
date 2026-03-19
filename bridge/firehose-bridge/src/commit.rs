use anyhow::{anyhow, Result};

#[derive(Debug, Clone)]
pub struct CommitOp {
    pub action: String,
    pub path: String,
    pub cid: Option<String>,
    pub record_json: Option<String>,
}

#[derive(Debug, Clone)]
pub struct DecodedCommit {
    pub seq: i64,
    pub repo: String,
    pub rev: String,
    pub ops: Vec<CommitOp>,
}

pub fn decode_commit(env: crate::envelope::CommitEnvelope) -> Result<DecodedCommit> {
    let blocks = crate::car::parse_car(&env.blocks)?;
    let mut out_ops = Vec::new();

    for op in env.ops {
        let record_json = match &op.cid {
            Some(cid) => {
                let block = crate::car::find_block_by_cid(&blocks, cid)
                    .ok_or_else(|| anyhow!("commit op cid not found in CAR blocks: {cid}"))?;
                let json = crate::dagcbor::decode_record_to_json(&block.bytes)?;
                Some(serde_json::to_string(&json).map_err(|e| anyhow!("record JSON serialization failed: {e}"))?)
            }
            None => None,
        };

        out_ops.push(CommitOp {
            action: op.action,
            path: op.path,
            cid: op.cid,
            record_json,
        });
    }

    Ok(DecodedCommit {
        seq: env.seq,
        repo: env.repo,
        rev: env.rev,
        ops: out_ops,
    })
}

use anyhow::{anyhow, bail, Result};
use cid::Cid;
use std::io::Cursor;

#[derive(Debug, Clone)]
pub struct CarBlock {
    pub cid: String,
    pub bytes: Vec<u8>,
}

pub fn parse_car(bytes: &[u8]) -> Result<Vec<CarBlock>> {
    if bytes.is_empty() {
        bail!("car parse failed: empty bytes")
    }
    let mut off = 0usize;
    let header_len = read_uvarint(bytes, &mut off)? as usize;
    if off + header_len > bytes.len() {
        bail!("car parse failed: truncated header")
    }

    let header_slice = &bytes[off..off + header_len];
    off += header_len;
    let header_v: ciborium::value::Value = ciborium::de::from_reader(Cursor::new(header_slice))
        .map_err(|e| anyhow!("car header CBOR decode failed: {e}"))?;
    validate_header(&header_v)?;

    let mut blocks = Vec::new();
    while off < bytes.len() {
        let section_len = read_uvarint(bytes, &mut off)? as usize;
        if section_len == 0 {
            continue;
        }
        if off + section_len > bytes.len() {
            bail!("car parse failed: truncated block section")
        }

        let section = &bytes[off..off + section_len];
        off += section_len;

        let (cid, cid_len) = parse_cid_prefix(section)?;
        let payload = section[cid_len..].to_vec();
        blocks.push(CarBlock {
            cid: cid.to_string(),
            bytes: payload,
        });
    }

    Ok(blocks)
}

pub fn find_block_by_cid<'a>(blocks: &'a [CarBlock], cid: &str) -> Option<&'a CarBlock> {
    blocks.iter().find(|b| b.cid == cid)
}

fn validate_header(v: &ciborium::value::Value) -> Result<()> {
    use ciborium::value::Value;
    let Value::Map(entries) = v else {
        bail!("car header is not a CBOR map")
    };
    let mut found_version = false;
    for (k, val) in entries {
        if let Value::Text(name) = k {
            if name == "version" {
                found_version = true;
                match val {
                    Value::Integer(i) if i128::from(*i) == 1 => {}
                    _ => bail!("unsupported CAR version (expected 1)"),
                }
            }
        }
    }
    if !found_version {
        bail!("car header missing version")
    }
    Ok(())
}

pub fn read_uvarint(bytes: &[u8], off: &mut usize) -> Result<u64> {
    let mut x = 0u64;
    let mut s = 0u32;
    loop {
        if *off >= bytes.len() {
            bail!("unexpected EOF while reading uvarint")
        }
        let b = bytes[*off];
        *off += 1;
        if b < 0x80 {
            if s >= 64 && b > 1 {
                bail!("uvarint overflow")
            }
            x |= (b as u64) << s;
            return Ok(x);
        }
        x |= ((b & 0x7f) as u64) << s;
        s += 7;
        if s > 63 {
            bail!("uvarint overflow")
        }
    }
}

fn parse_cid_prefix(section: &[u8]) -> Result<(Cid, usize)> {
    let mut cur = Cursor::new(section);
    let cid = Cid::read_bytes(&mut cur).map_err(|e| anyhow!("cid decode failed in CAR block: {e}"))?;
    let len = cur.position() as usize;
    Ok((cid, len))
}

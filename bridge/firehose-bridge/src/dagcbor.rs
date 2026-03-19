use anyhow::{anyhow, Result};
use ciborium::value::{Integer, Value};
use cid::Cid;
use serde_json::{Map, Number, Value as JsonValue};
use std::io::Cursor;

pub fn decode_record_to_json(bytes: &[u8]) -> Result<JsonValue> {
    let value: Value = ciborium::de::from_reader(Cursor::new(bytes))
        .map_err(|e| anyhow!("dag-cbor decode failed: {e}"))?;
    Ok(value_to_json(&value))
}

pub fn value_to_json(v: &Value) -> JsonValue {
    match v {
        Value::Null => JsonValue::Null,
        Value::Bool(b) => JsonValue::Bool(*b),
        Value::Integer(i) => integer_to_json(*i),
        Value::Float(f) => Number::from_f64(*f).map(JsonValue::Number).unwrap_or(JsonValue::Null),
        Value::Bytes(b) => JsonValue::String(hex_bytes(b)),
        Value::Text(s) => JsonValue::String(s.clone()),
        Value::Array(items) => JsonValue::Array(items.iter().map(value_to_json).collect()),
        Value::Map(entries) => {
            let mut obj = Map::new();
            for (k, val) in entries {
                let key = match k {
                    Value::Text(s) => s.clone(),
                    other => format!("_key_{:?}", other),
                };
                obj.insert(key, value_to_json(val));
            }
            JsonValue::Object(obj)
        }
        Value::Tag(tag, boxed) => {
            if *tag == 42 {
                match value_to_cid_string(boxed) {
                    Some(cid) => {
                        let mut obj = Map::new();
                        obj.insert("$link".to_string(), JsonValue::String(cid));
                        JsonValue::Object(obj)
                    }
                    None => JsonValue::String(format!("<cid-tag:{}>", tag)),
                }
            } else {
                let mut obj = Map::new();
                obj.insert("$tag".to_string(), JsonValue::Number(Number::from(*tag)));
                obj.insert("value".to_string(), value_to_json(boxed));
                JsonValue::Object(obj)
            }
        }
        _ => JsonValue::String(format!("<unsupported-cbor:{:?}>", v)),
    }
}

pub fn value_to_cid_string(v: &Value) -> Option<String> {
    match v {
        Value::Tag(tag, boxed) if *tag == 42 => match &**boxed {
            Value::Bytes(b) => decode_cid_bytes(b).ok(),
            _ => None,
        },
        Value::Bytes(b) => decode_cid_bytes(b).ok(),
        Value::Text(s) => Some(s.clone()),
        _ => None,
    }
}

fn decode_cid_bytes(b: &[u8]) -> Result<String> {
    let cid_bytes = if b.first().copied() == Some(0) { &b[1..] } else { b };
    let cid = Cid::read_bytes(&mut Cursor::new(cid_bytes))
        .map_err(|e| anyhow!("cid bytes decode failed: {e}"))?;
    Ok(cid.to_string())
}

fn integer_to_json(i: Integer) -> JsonValue {
    if let Ok(v) = i64::try_from(i) {
        JsonValue::Number(Number::from(v))
    } else if let Ok(v) = u64::try_from(i) {
        JsonValue::Number(Number::from(v))
    } else {
        // ciborium::Integer has no Display in all 0.2.x versions; values outside
        // i64/u64 range are impossible in ATProto records in practice.
        JsonValue::Null
    }
}

fn hex_bytes(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        use std::fmt::Write as _;
        let _ = write!(&mut s, "{:02x}", b);
    }
    s
}
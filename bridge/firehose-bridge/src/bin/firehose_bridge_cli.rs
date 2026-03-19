use std::fs;
use std::io::{self, Read};
use std::path::PathBuf;

use anyhow::{Context, Result};
use clap::Parser;
use fortransky_firehose_bridge::decoder;

#[derive(Parser, Debug)]
#[command(name = "firehose_bridge_cli")]
#[command(about = "Decode ATProto relay/firehose frames into normalized JSONL")]
struct Args {
    /// Read a single frame from a file instead of stdin
    #[arg(long)]
    frame_file: Option<PathBuf>,

    /// Emit pretty JSON instead of compact JSONL
    #[arg(long, default_value_t = false)]
    pretty: bool,
}

fn main() {
    if let Err(err) = real_main() {
        eprintln!("firehose_bridge_cli: {err:#}");
        std::process::exit(1);
    }
}

fn real_main() -> Result<()> {
    let args = Args::parse();
    let bytes = read_input(args.frame_file)?;
    let events = decoder::decode_frame(&bytes)
        .with_context(|| "frame decode failed")?;

    for ev in events {
        let value = serde_json::json!({
            "kind": map_kind(ev.kind),
            "did": ev.repo_did.unwrap_or_default(),
            "handle": "",
            "text": extract_text(ev.record_json.as_deref()),
            "time_us": ev.seq.to_string(),
            "uri": ev.uri.unwrap_or_default(),
            "record_type": ev.collection.unwrap_or_default(),
            "source": "relay-raw-native",
            "op": map_op(ev.op_action),
            "rev": ev.rev.unwrap_or_default(),
            "record_json": parse_record_json(ev.record_json.as_deref()),
            "error": ev.error_message.unwrap_or_default(),
        });
        if args.pretty {
            println!("{}", serde_json::to_string_pretty(&value)?);
        } else {
            println!("{}", serde_json::to_string(&value)?);
        }
    }

    Ok(())
}

fn read_input(frame_file: Option<PathBuf>) -> Result<Vec<u8>> {
    if let Some(path) = frame_file {
        return fs::read(&path).with_context(|| format!("failed to read frame file {}", path.display()));
    }
    let mut buf = Vec::new();
    io::stdin().read_to_end(&mut buf).context("failed to read frame bytes from stdin")?;
    Ok(buf)
}

fn parse_record_json(src: Option<&str>) -> serde_json::Value {
    match src {
        Some(s) => serde_json::from_str(s).unwrap_or_else(|_| serde_json::Value::String(s.to_string())),
        None => serde_json::Value::Null,
    }
}

fn extract_text(src: Option<&str>) -> String {
    match src.and_then(|s| serde_json::from_str::<serde_json::Value>(s).ok()) {
        Some(serde_json::Value::Object(map)) => map.get("text").and_then(|v| v.as_str()).unwrap_or("").to_string(),
        _ => String::new(),
    }
}

fn map_kind(kind: i32) -> &'static str {
    match kind {
        1 => "commit",
        2 => "identity",
        3 => "account",
        4 => "info",
        5 => "error",
        _ => "unknown",
    }
}

fn map_op(op: i32) -> &'static str {
    match op {
        1 => "create",
        2 => "update",
        3 => "delete",
        _ => "none",
    }
}

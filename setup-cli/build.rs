//! Embeds the installer payload (ObjectScript sources and native libraries from the
//! repository) in the binary, so a downloaded executable needs no checkout.

use std::fmt::Write as _;
use std::path::Path;

#[path = "src/files.rs"]
mod files;

fn main() {
    let manifest = std::env::var("CARGO_MANIFEST_DIR").unwrap();
    let root = Path::new(&manifest)
        .parent()
        .expect("setup-cli sits inside the repository");
    println!("cargo:rerun-if-changed=src/files.rs");
    for dir in [
        "src/objectscript/OPCUA",
        "src/objectscript/IRISConfig",
        "bin/unix",
    ] {
        println!("cargo:rerun-if-changed={}", root.join(dir).display());
    }
    let list = files::list(root).expect("reading the payload from the repository");
    let mut code = String::from("pub static FILES: &[(&str, &[u8])] = &[\n");
    for rel in &list {
        let abs = root.join(rel);
        assert!(abs.is_file(), "payload file missing: {}", abs.display());
        writeln!(
            code,
            "    ({rel:?}, include_bytes!({:?})),",
            abs.display().to_string()
        )
        .unwrap();
    }
    code.push_str("];\n");
    let out = Path::new(&std::env::var("OUT_DIR").unwrap()).join("embedded.rs");
    std::fs::write(out, code).unwrap();
}

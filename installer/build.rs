//! Embeds the installer payload (ObjectScript sources and native libraries from the
//! repository) in the binary, so a downloaded executable needs no checkout.

use std::fmt::Write as _;
use std::path::Path;

// Shared with the program, which also uses what only it needs (document names).
#[path = "src/files.rs"]
#[allow(dead_code)]
mod files;

fn main() {
    let manifest = std::env::var("CARGO_MANIFEST_DIR").unwrap();
    let root = Path::new(&manifest)
        .parent()
        .expect("installer/ sits inside the repository");
    println!("cargo:rerun-if-changed=src/files.rs");
    for dir in [
        "backend/src/OPCUA",
        "installer/objectscript",
        "backend/native",
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

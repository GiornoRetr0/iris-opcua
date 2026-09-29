//! Which repository files make up the installer payload, relative to the repository
//! root. Shared by `build.rs`, which embeds them in the binary, and by `payload.rs`,
//! which reads them from a checkout for `--dist`, so the two can never disagree.

use std::io;
use std::path::Path;

/// Native files per architecture, in dependency order (dependencies first).
pub const NATIVE: &[&str] = &["libcrypto.so.1.1", "libopen62541.so.0", "irisopcua.so"];
pub const ARCHES: &[&str] = &["amd64", "arm64"];
/// Directories whose layout mirrors ObjectScript package names, so a file's document
/// name is its path below one of them.
pub const SOURCE_ROOTS: &[&str] = &["backend/src", "installer/objectscript"];
pub const CLIENT_INSTALLER: &str = "installer/objectscript/IRISConfig/ClientInstaller.cls";
pub const APPLICATION_DIR: &str = "backend/src/OPCUA";

/// `backend/native/linux-<arch>/<name>`.
pub fn native(arch: &str, name: &str) -> String {
    format!("backend/native/linux-{arch}/{name}")
}

/// The installer class, every OPCUA class and include file, and the Linux native
/// libraries. Sorted, `/`-separated.
pub fn list(root: &Path) -> io::Result<Vec<String>> {
    let mut out = vec![CLIENT_INSTALLER.to_string()];
    walk(root, APPLICATION_DIR, &mut out)?;
    for arch in ARCHES {
        for name in NATIVE {
            out.push(native(arch, name));
        }
    }
    out.sort();
    Ok(out)
}

fn walk(root: &Path, rel: &str, out: &mut Vec<String>) -> io::Result<()> {
    for entry in std::fs::read_dir(root.join(rel))? {
        let entry = entry?;
        let name = entry.file_name().to_string_lossy().into_owned();
        let child = format!("{rel}/{name}");
        if entry.file_type()?.is_dir() {
            walk(root, &child, out)?;
        } else if name.ends_with(".cls") || name.ends_with(".inc") {
            out.push(child);
        }
    }
    Ok(())
}

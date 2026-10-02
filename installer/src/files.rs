//! Which repository files make up the installer payload, relative to the repository
//! root. Shared by `build.rs`, which embeds them in the binary, and by `payload.rs`,
//! which reads them from a checkout for `--dist`, so the two can never disagree.

use std::io;
use std::path::Path;

/// Native files of a Linux server, in dependency order (dependencies first).
pub const NATIVE_LINUX: &[&str] = &["libcrypto.so.1.1", "libopen62541.so.0", "irisopcua.so"];
/// Native files of a Windows server, in dependency order (dependencies first).
pub const NATIVE_WINDOWS: &[&str] = &["libcrypto-1_1-x64.dll", "open62541.dll", "IrisOPCUA.dll"];
/// Each `backend/native/` directory and the files it ships.
pub const PLATFORMS: &[(&str, &[&str])] = &[
    ("linux-amd64", NATIVE_LINUX),
    ("linux-arm64", NATIVE_LINUX),
    ("windows-x64", NATIVE_WINDOWS),
];
/// Directories whose layout mirrors ObjectScript package names, so a file's document
/// name is its path below one of them.
pub const SOURCE_ROOTS: &[&str] = &["backend/src", "installer/objectscript"];
pub const CLIENT_INSTALLER: &str = "installer/objectscript/IRISConfig/ClientInstaller.cls";
pub const APPLICATION_DIR: &str = "backend/src/OPCUA";

/// `backend/native/<platform>/<name>`.
pub fn native(platform: &str, name: &str) -> String {
    format!("backend/native/{platform}/{name}")
}

/// The installer class, every OPCUA class and include file, and the native libraries
/// of every platform. Sorted, `/`-separated.
pub fn list(root: &Path) -> io::Result<Vec<String>> {
    let mut out = vec![CLIENT_INSTALLER.to_string()];
    walk(root, APPLICATION_DIR, &mut out)?;
    for (platform, names) in PLATFORMS {
        for name in *names {
            out.push(native(platform, name));
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

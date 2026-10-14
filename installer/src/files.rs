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
/// The OPC UA Console's production build (`npx ng build` in `webapp/`), served by IRIS.
pub const CONSOLE_DIR: &str = "webapp/dist/webapp/browser";
/// The console's entry page; its absence means the console was not built.
pub const CONSOLE_INDEX: &str = "webapp/dist/webapp/browser/index.html";
/// Licence notices of the bundled third-party code; the build writes them beside `browser/`.
pub const CONSOLE_LICENSES: &str = "webapp/dist/webapp/3rdpartylicenses.txt";

/// `backend/native/<platform>/<name>`.
pub fn native(platform: &str, name: &str) -> String {
    format!("backend/native/{platform}/{name}")
}

/// The installer class, every OPCUA class and include file, the native libraries of
/// every platform, and the console build when present. Sorted, `/`-separated.
pub fn list(root: &Path) -> io::Result<Vec<String>> {
    let mut out = vec![CLIENT_INSTALLER.to_string()];
    walk(root, APPLICATION_DIR, &mut out, &|n| {
        n.ends_with(".cls") || n.ends_with(".inc")
    })?;
    if root.join(CONSOLE_DIR).is_dir() {
        walk(root, CONSOLE_DIR, &mut out, &|_| true)?;
        if root.join(CONSOLE_LICENSES).is_file() {
            out.push(CONSOLE_LICENSES.to_string());
        }
    }
    for (platform, names) in PLATFORMS {
        for name in *names {
            out.push(native(platform, name));
        }
    }
    out.sort();
    Ok(out)
}

fn walk(
    root: &Path,
    rel: &str,
    out: &mut Vec<String>,
    keep: &dyn Fn(&str) -> bool,
) -> io::Result<()> {
    for entry in std::fs::read_dir(root.join(rel))? {
        let entry = entry?;
        let name = entry.file_name().to_string_lossy().into_owned();
        let child = format!("{rel}/{name}");
        if entry.file_type()?.is_dir() {
            walk(root, &child, out, keep)?;
        } else if keep(&name) {
            out.push(child);
        }
    }
    Ok(())
}

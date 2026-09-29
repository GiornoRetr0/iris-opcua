//! Locates the ObjectScript sources and native libraries, and picks the artifacts
//! for the server platform IRIS reports.

use sha2::{Digest, Sha256};
use std::fs;
use std::path::{Path, PathBuf};

/// The installer class the CLI loads into %SYS first.
pub const CLIENT_INSTALLER: &str = "src/objectscript/IRISConfig/ClientInstaller.cls";
pub const CLIENT_INSTALLER_DOC: &str = "IRISConfig.ClientInstaller.cls";

/// Files whose absence means the payload is incomplete.
const REQUIRED: &[&str] = &[
    CLIENT_INSTALLER,
    "src/objectscript/OPCUA/Constants.inc",
    "src/objectscript/OPCUA/Utils.cls",
    "src/objectscript/OPCUA/Client.cls",
    "src/objectscript/OPCUA/REST/Handler.cls",
];

pub struct Payload {
    pub root: PathBuf,
}

/// One ObjectScript document: its Atelier name and file on disk.
#[derive(Debug, Clone)]
pub struct Doc {
    pub name: String,
    pub path: PathBuf,
}

#[derive(Debug, Clone)]
pub struct Artifact {
    pub name: &'static str,
    pub path: PathBuf,
    pub sha256: String,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Arch {
    Amd64,
    Arm64,
}

/// What the server platform means for native artifacts.
#[derive(Debug, Clone, PartialEq)]
pub enum Target {
    Linux(Arch),
    Unsupported(String),
}

impl Target {
    pub fn label(&self) -> String {
        match self {
            Target::Linux(Arch::Amd64) => "Linux x86-64".into(),
            Target::Linux(Arch::Arm64) => "Linux ARM64".into(),
            Target::Unsupported(p) => p.clone(),
        }
    }
}

/// Map IRIS's `$System.Version.GetOS()` / `GetPlatform()` to a supported target.
/// Only Linux is supported so far; Windows and macOS servers are reported as such.
pub fn target_for(os: &str, platform: &str) -> Target {
    let p = platform.to_ascii_lowercase();
    if os.eq_ignore_ascii_case("windows") {
        return Target::Unsupported(format!(
            "Windows ({platform}) — Windows servers are not supported by this installer yet"
        ));
    }
    if p.contains("mac") || p.contains("aix") || p.contains("solaris") {
        return Target::Unsupported(format!("{platform} — only Linux servers are supported"));
    }
    if !os.eq_ignore_ascii_case("unix") {
        return Target::Unsupported(format!("{os} ({platform})"));
    }
    if p.contains("arm64") || p.contains("aarch64") {
        Target::Linux(Arch::Arm64)
    } else if p.contains("x86-64")
        || p.contains("x86_64")
        || p.contains("x64")
        || p.contains("amd64")
    {
        Target::Linux(Arch::Amd64)
    } else {
        Target::Unsupported(format!("{platform} — CPU architecture not recognized"))
    }
}

/// Native files for a target, in dependency order (dependencies first).
pub fn native_names(target: &Target) -> &'static [&'static str] {
    match target {
        Target::Linux(_) => &["libcrypto.so.1.1", "libopen62541.so.0", "irisopcua.so"],
        Target::Unsupported(_) => &[],
    }
}

impl Payload {
    /// Explicit `--dist`, else the checkout containing the executable, else the working directory.
    pub fn locate(dist: Option<PathBuf>) -> Result<Payload, String> {
        if let Some(d) = dist {
            return Payload::check(d.clone()).ok_or_else(|| {
                format!(
                    "{} does not contain the OPC UA payload (src/objectscript and bin).",
                    d.display()
                )
            });
        }
        let mut starts = Vec::new();
        if let Ok(exe) = std::env::current_exe() {
            starts.push(exe.canonicalize().unwrap_or(exe));
        }
        if let Ok(cwd) = std::env::current_dir() {
            starts.push(cwd);
        }
        for start in starts {
            for dir in start.ancestors() {
                if let Some(p) = Payload::check(dir.to_path_buf()) {
                    return Ok(p);
                }
            }
        }
        Err("Could not find the OPC UA payload. Run the tool from the repository checkout, or pass --dist <path to the repository>.".into())
    }

    fn check(root: PathBuf) -> Option<Payload> {
        (root.join("src/objectscript/OPCUA").is_dir() && root.join("bin").is_dir())
            .then_some(Payload { root })
    }

    pub fn missing_files(&self) -> Vec<String> {
        REQUIRED
            .iter()
            .filter(|f| !self.root.join(f).is_file())
            .map(|f| f.to_string())
            .collect()
    }

    pub fn client_installer(&self) -> Doc {
        Doc {
            name: CLIENT_INSTALLER_DOC.into(),
            path: self.root.join(CLIENT_INSTALLER),
        }
    }

    /// `OPCUA.Constants.inc` first, then every OPCUA class except `Tests/`.
    /// Examples and the IRISConfig installers are not part of a client install.
    pub fn application_docs(&self) -> Result<Vec<Doc>, String> {
        let base = self.root.join("src/objectscript");
        let mut docs = vec![Doc {
            name: "OPCUA.Constants.inc".into(),
            path: base.join("OPCUA/Constants.inc"),
        }];
        let mut classes = Vec::new();
        collect_classes(&base, &base.join("OPCUA"), &mut classes)
            .map_err(|e| format!("Reading sources: {e}"))?;
        classes.sort_by(|a, b| a.name.cmp(&b.name));
        docs.extend(classes);
        Ok(docs)
    }

    pub fn artifacts(&self, target: &Target) -> Result<Vec<Artifact>, String> {
        let dir = match target {
            Target::Linux(Arch::Amd64) => self.root.join("bin/unix/amd64"),
            Target::Linux(Arch::Arm64) => self.root.join("bin/unix/arm64"),
            Target::Unsupported(p) => return Err(format!("No native artifacts for {p}.")),
        };
        native_names(target)
            .iter()
            .map(|name| {
                let path = dir.join(name);
                let bytes = fs::read(&path).map_err(|e| format!("{}: {e}", path.display()))?;
                Ok(Artifact {
                    name,
                    sha256: sha256_hex(&bytes),
                    path,
                })
            })
            .collect()
    }
}

fn collect_classes(base: &Path, dir: &Path, out: &mut Vec<Doc>) -> std::io::Result<()> {
    for entry in fs::read_dir(dir)? {
        let path = entry?.path();
        if path.is_dir() {
            if path.file_name().is_some_and(|n| n == "Tests") {
                continue;
            }
            collect_classes(base, &path, out)?;
        } else if path.extension().is_some_and(|e| e == "cls") {
            out.push(Doc {
                name: doc_name(base, &path),
                path,
            });
        }
    }
    Ok(())
}

/// `src/objectscript/OPCUA/REST/Handler.cls` → `OPCUA.REST.Handler.cls`.
fn doc_name(base: &Path, path: &Path) -> String {
    let rel = path.strip_prefix(base).unwrap_or(path);
    rel.components()
        .map(|c| c.as_os_str().to_string_lossy())
        .collect::<Vec<_>>()
        .join(".")
}

pub fn sha256_hex(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

/// Source lines as Atelier expects them: one string per line, no terminators.
pub fn doc_lines(path: &Path) -> Result<Vec<String>, String> {
    let text = fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
    Ok(text
        .replace("\r\n", "\n")
        .split('\n')
        .map(str::to_string)
        .collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn platform_mapping() {
        assert_eq!(
            target_for("UNIX", "Ubuntu Server LTS for ARM64 Containers"),
            Target::Linux(Arch::Arm64)
        );
        assert_eq!(
            target_for("UNIX", "Red Hat Enterprise Linux 9 for x86-64"),
            Target::Linux(Arch::Amd64)
        );
        assert!(matches!(
            target_for("Windows", "Microsoft Windows 64-bit"),
            Target::Unsupported(_)
        ));
        assert!(matches!(
            target_for("UNIX", "macOS for Apple Silicon"),
            Target::Unsupported(_)
        ));
        assert!(matches!(
            target_for("UNIX", "Some Linux for RISC-V"),
            Target::Unsupported(_)
        ));
    }

    #[test]
    fn repository_payload_is_complete_and_excludes_tests() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .unwrap()
            .to_path_buf();
        let p = Payload::check(root).expect("repository payload");
        assert!(p.missing_files().is_empty());
        let docs = p.application_docs().unwrap();
        assert_eq!(docs[0].name, "OPCUA.Constants.inc");
        assert!(docs.iter().any(|d| d.name == "OPCUA.REST.Handler.cls"));
        assert!(docs
            .iter()
            .all(|d| d.name.starts_with("OPCUA.") && !d.name.starts_with("OPCUA.Tests.")));
        for arch in [Arch::Amd64, Arch::Arm64] {
            let a = p.artifacts(&Target::Linux(arch)).unwrap();
            assert_eq!(a.len(), 3);
            assert!(a.iter().all(|x| x.sha256.len() == 64));
        }
    }
}

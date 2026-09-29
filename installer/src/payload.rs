//! The installer payload — ObjectScript sources and native libraries — and the
//! artifact choice for the server platform IRIS reports.
//!
//! The payload is built into the binary (see `build.rs`), so a downloaded executable
//! needs no repository. `--dist <checkout>` reads the same files from a checkout instead.

use crate::files;
use sha2::{Digest, Sha256};
use std::borrow::Cow;
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

mod embedded {
    include!(concat!(env!("OUT_DIR"), "/embedded.rs"));
}

/// Files whose absence means the payload is incomplete.
const REQUIRED: &[&str] = &[
    files::CLIENT_INSTALLER,
    "backend/src/OPCUA/Constants.inc",
    "backend/src/OPCUA/Utils.cls",
    "backend/src/OPCUA/Client.cls",
    "backend/src/OPCUA/REST/Handler.cls",
];

pub struct Payload {
    files: BTreeMap<String, Cow<'static, [u8]>>,
    /// The checkout it came from; `None` when built in.
    root: Option<PathBuf>,
    /// Where built-in native files are written when an administrator must copy them by hand.
    extract_dir: PathBuf,
}

/// One ObjectScript document: its Atelier name and source lines.
#[derive(Debug, Clone)]
pub struct Doc {
    pub name: String,
    pub lines: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct Artifact {
    pub name: &'static str,
    pub sha256: String,
    pub bytes: Vec<u8>,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Arch {
    Amd64,
    Arm64,
}

impl Arch {
    fn dir(self) -> &'static str {
        match self {
            Arch::Amd64 => "amd64",
            Arch::Arm64 => "arm64",
        }
    }
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

impl Payload {
    /// `--dist` when given, else the copy built into this binary.
    pub fn locate(dist: Option<PathBuf>, extract_dir: PathBuf) -> Result<Payload, String> {
        match dist {
            Some(root) => Payload::from_dir(&root, extract_dir),
            None => Ok(Payload::embedded(extract_dir)),
        }
    }

    pub fn embedded(extract_dir: PathBuf) -> Payload {
        let files = embedded::FILES
            .iter()
            .map(|(rel, bytes)| (rel.to_string(), Cow::Borrowed(*bytes)))
            .collect();
        Payload {
            files,
            root: None,
            extract_dir,
        }
    }

    pub fn from_dir(root: &Path, extract_dir: PathBuf) -> Result<Payload, String> {
        let list = files::list(root).map_err(|e| {
            format!(
                "{} does not contain the OPC UA payload (backend/ and installer/objectscript/): {e}",
                root.display()
            )
        })?;
        let mut files = BTreeMap::new();
        for rel in list {
            let bytes = std::fs::read(root.join(&rel))
                .map_err(|e| format!("{}: {e}", root.join(&rel).display()))?;
            files.insert(rel, Cow::Owned(bytes));
        }
        Ok(Payload {
            files,
            root: Some(root.to_path_buf()),
            extract_dir,
        })
    }

    /// Where the payload came from, for messages.
    pub fn origin(&self) -> String {
        match &self.root {
            Some(r) => r.display().to_string(),
            None => "the copy built into this program".into(),
        }
    }

    pub fn missing_files(&self) -> Vec<String> {
        REQUIRED
            .iter()
            .filter(|f| !self.files.contains_key(**f))
            .map(|f| f.to_string())
            .collect()
    }

    fn doc(&self, rel: &str) -> Result<Doc, String> {
        let bytes = self
            .files
            .get(rel)
            .ok_or_else(|| format!("{rel} is missing from the payload"))?;
        let text = String::from_utf8_lossy(bytes);
        Ok(Doc {
            name: doc_name(rel),
            lines: text
                .replace("\r\n", "\n")
                .split('\n')
                .map(str::to_string)
                .collect(),
        })
    }

    pub fn client_installer(&self) -> Result<Doc, String> {
        self.doc(files::CLIENT_INSTALLER)
    }

    /// Include files first (`OPCUA.Constants.inc`), then every OPCUA class.
    /// Tests and Examples live outside `backend/src/` and are not part of a client install.
    pub fn application_docs(&self) -> Result<Vec<Doc>, String> {
        let prefix = format!("{}/", files::APPLICATION_DIR);
        let rels: Vec<&String> = self
            .files
            .keys()
            .filter(|k| k.starts_with(&prefix))
            .collect();
        let includes = rels.iter().filter(|r| r.ends_with(".inc"));
        let classes = rels.iter().filter(|r| r.ends_with(".cls"));
        includes.chain(classes).map(|r| self.doc(r)).collect()
    }

    pub fn artifacts(&self, target: &Target) -> Result<Vec<Artifact>, String> {
        let arch = match target {
            Target::Linux(a) => *a,
            Target::Unsupported(p) => return Err(format!("No native artifacts for {p}.")),
        };
        files::NATIVE
            .iter()
            .map(|name| {
                let rel = files::native(arch.dir(), name);
                let bytes = self
                    .files
                    .get(&rel)
                    .ok_or_else(|| format!("{rel} is missing from the payload"))?;
                Ok(Artifact {
                    name,
                    sha256: sha256_hex(bytes),
                    bytes: bytes.to_vec(),
                })
            })
            .collect()
    }

    /// A file on this machine an administrator can copy to the server. Built-in files are
    /// written to `local/native/<arch>/` first.
    pub fn artifact_file(&self, target: &Target, a: &Artifact) -> Result<PathBuf, String> {
        let Target::Linux(arch) = target else {
            return Err("unsupported platform".into());
        };
        let rel = files::native(arch.dir(), a.name);
        if let Some(root) = &self.root {
            return Ok(root.join(rel));
        }
        let dir = self.extract_dir.join(arch.dir());
        std::fs::create_dir_all(&dir).map_err(|e| format!("{}: {e}", dir.display()))?;
        let path = dir.join(a.name);
        if std::fs::read(&path).map(|b| b != a.bytes).unwrap_or(true) {
            std::fs::write(&path, &a.bytes).map_err(|e| format!("{}: {e}", path.display()))?;
        }
        Ok(path)
    }
}

/// `backend/src/OPCUA/REST/Handler.cls` → `OPCUA.REST.Handler.cls`.
fn doc_name(rel: &str) -> String {
    let below = files::SOURCE_ROOTS
        .iter()
        .find_map(|root| rel.strip_prefix(root)?.strip_prefix('/'))
        .unwrap_or(rel);
    below.replace('/', ".")
}

pub fn sha256_hex(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
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

    fn check_complete(p: &Payload) {
        assert!(p.missing_files().is_empty());
        assert_eq!(
            p.client_installer().unwrap().name,
            "IRISConfig.ClientInstaller.cls"
        );
        let docs = p.application_docs().unwrap();
        assert_eq!(docs[0].name, "OPCUA.Constants.inc");
        assert!(docs.iter().any(|d| d.name == "OPCUA.REST.Handler.cls"));
        assert!(docs
            .iter()
            .all(|d| d.name.starts_with("OPCUA.") && !d.name.starts_with("OPCUA.Tests.")));
        for arch in [Arch::Amd64, Arch::Arm64] {
            let a = p.artifacts(&Target::Linux(arch)).unwrap();
            assert_eq!(a.len(), 3);
            assert!(a
                .iter()
                .all(|x| x.sha256.len() == 64 && !x.bytes.is_empty()));
        }
    }

    #[test]
    fn built_in_payload_is_complete_and_matches_the_checkout() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap();
        let tmp = std::env::temp_dir();
        let built_in = Payload::embedded(tmp.clone());
        let checkout = Payload::from_dir(root, tmp).unwrap();
        check_complete(&built_in);
        check_complete(&checkout);
        assert_eq!(built_in.files, checkout.files);
    }

    #[test]
    fn built_in_artifacts_are_written_out_for_manual_copy() {
        let dir = std::env::temp_dir().join(format!("opcua-native-{}", std::process::id()));
        let p = Payload::embedded(dir.clone());
        let t = Target::Linux(Arch::Arm64);
        let a = &p.artifacts(&t).unwrap()[0];
        let path = p.artifact_file(&t, a).unwrap();
        assert_eq!(sha256_hex(&std::fs::read(&path).unwrap()), a.sha256);
        std::fs::remove_dir_all(dir).unwrap();
    }
}

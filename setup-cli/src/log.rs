//! A private, redacted log file: `local/setup.log`.

use std::fs::{File, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

static LOG: Mutex<Option<(PathBuf, File)>> = Mutex::new(None);
static SECRETS: Mutex<Vec<String>> = Mutex::new(Vec::new());

pub fn open(dir: &Path) -> std::io::Result<()> {
    crate::config::ensure_private_dir(dir)?;
    let path = dir.join("setup.log");
    let mut opts = OpenOptions::new();
    opts.create(true).append(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
        opts.mode(0o600);
        let f = opts.open(&path)?;
        f.set_permissions(std::fs::Permissions::from_mode(0o600))?;
        *LOG.lock().unwrap() = Some((path, f));
    }
    #[cfg(not(unix))]
    {
        let f = opts.open(&path)?;
        *LOG.lock().unwrap() = Some((path, f));
    }
    Ok(())
}

pub fn path() -> Option<PathBuf> {
    LOG.lock().unwrap().as_ref().map(|(p, _)| p.clone())
}

/// Register a value that must never be written anywhere.
pub fn secret(s: &str) {
    if !s.is_empty() {
        SECRETS.lock().unwrap().push(s.to_string());
    }
}

pub fn redact(text: &str) -> String {
    let mut out = text.to_string();
    for s in SECRETS.lock().unwrap().iter() {
        out = out.replace(s.as_str(), "***");
    }
    out
}

pub fn write(text: &str) {
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    if let Some((_, f)) = LOG.lock().unwrap().as_mut() {
        let _ = writeln!(f, "{secs} {}", redact(text));
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn registered_secrets_are_redacted() {
        super::secret("hunter2-xyz");
        assert_eq!(super::redact("pw hunter2-xyz ok"), "pw *** ok");
    }
}

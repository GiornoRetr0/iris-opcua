//! Connection definitions, the base URL rules, and `local/connections.json`.
//!
//! Passwords are stored in plain text on purpose (see the plan, §6): the file lives
//! in the tool's own `local/` folder, is git-ignored, and is owner-only on Unix.

use serde::{Deserialize, Serialize};
use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};

pub const DEFAULT_NAMESPACE: &str = "OPCUA";
pub const DEFAULT_APP_PATH: &str = "/csp/opcua/api";

/// A base URL as the user defined it, normalized.
#[derive(Debug, Clone, PartialEq)]
pub struct BaseUrl {
    pub scheme: String,
    pub host: String,
    pub port: Option<u16>,
    pub prefix: String,
}

impl BaseUrl {
    pub fn as_string(&self) -> String {
        match self.port {
            Some(p) => format!("{}://{}:{}{}", self.scheme, self.host, p, self.prefix),
            None => format!("{}://{}{}", self.scheme, self.host, self.prefix),
        }
    }

    pub fn is_https(&self) -> bool {
        self.scheme == "https"
    }

    pub fn is_localhost(&self) -> bool {
        let h = self.host.trim_start_matches('[').trim_end_matches(']');
        h == "localhost" || h == "::1" || h.starts_with("127.")
    }
}

#[derive(Debug, PartialEq)]
pub enum UrlInput {
    /// A complete URL.
    Full(BaseUrl),
    /// No scheme was typed: the caller must ask for one rather than guess.
    NeedsScheme(String),
}

/// Parse `http(s)://host(:port)/pathPrefix` or a bare host. Never invents a port.
pub fn parse_base_url(input: &str) -> Result<UrlInput, String> {
    let s = input.trim();
    if s.is_empty() {
        return Err("Enter a URL or a host name.".into());
    }
    if s.chars().any(char::is_whitespace) {
        return Err("The URL must not contain spaces.".into());
    }
    if s.contains('?') || s.contains('#') {
        return Err("The URL must not contain a query (?) or fragment (#).".into());
    }
    let (scheme, rest) = match s.find("://") {
        Some(i) => (s[..i].to_ascii_lowercase(), &s[i + 3..]),
        None => return check_authority(s).map(|_| UrlInput::NeedsScheme(s.to_string())),
    };
    if scheme != "http" && scheme != "https" {
        return Err(format!("Unsupported scheme '{scheme}'. Use http or https."));
    }
    let (authority, path) = match rest.find('/') {
        Some(i) => (&rest[..i], &rest[i..]),
        None => (rest, ""),
    };
    let (host, port) = check_authority(authority)?;
    let prefix = normalize_prefix(path)?;
    Ok(UrlInput::Full(BaseUrl {
        scheme,
        host,
        port,
        prefix,
    }))
}

/// Complete a scheme-less input once the user has chosen the scheme.
pub fn with_scheme(scheme: &str, input: &str) -> Result<BaseUrl, String> {
    match parse_base_url(&format!("{scheme}://{}", input.trim()))? {
        UrlInput::Full(u) => Ok(u),
        UrlInput::NeedsScheme(_) => Err("Could not apply the scheme.".into()),
    }
}

fn check_authority(authority: &str) -> Result<(String, Option<u16>), String> {
    let authority = authority.split('/').next().unwrap_or("");
    if authority.contains('@') {
        return Err("Do not put credentials in the URL; you will be asked for them.".into());
    }
    let (host, port) = if let Some(end) = authority.strip_prefix('[').and_then(|a| a.find(']')) {
        let host = &authority[..end + 2];
        match &authority[end + 2..] {
            "" => (host, None),
            p if p.starts_with(':') => (host, Some(&p[1..])),
            _ => return Err("Invalid IPv6 address.".into()),
        }
    } else {
        match authority.rsplit_once(':') {
            Some((h, p)) => (h, Some(p)),
            None => (authority, None),
        }
    };
    if host.is_empty() {
        return Err("The URL has no host.".into());
    }
    if !host.starts_with('[')
        && !host
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '-' || c == '_')
    {
        return Err(format!("'{host}' is not a valid host name or IP address."));
    }
    let port = match port {
        None => None,
        Some(p) => match p.parse::<u16>() {
            Ok(n) if n > 0 => Some(n),
            _ => return Err(format!("'{p}' is not a valid port.")),
        },
    };
    Ok((host.to_ascii_lowercase(), port))
}

fn normalize_prefix(path: &str) -> Result<String, String> {
    let trimmed = path.trim_end_matches('/');
    if trimmed.is_empty() {
        return Ok(String::new());
    }
    if trimmed.contains("//") || trimmed.split('/').any(|seg| seg == "." || seg == "..") {
        return Err(format!("Invalid path prefix '{path}'."));
    }
    Ok(trimmed.to_string())
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct Instance {
    pub guid: String,
    pub version: String,
    #[serde(default)]
    pub platform: String,
}

/// Non-secret choices and progress for one connection's installation.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct Setup {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub namespace: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub app_path: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub api_url: Option<String>,
    /// `running:<step>` while a mutation is under way, `failed:<step>` or `done` after it.
    /// A hint only: the next run inspects IRIS before trusting it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub progress: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Connection {
    pub name: String,
    pub base_url: String,
    pub username: String,
    /// Plain text, only when the user chose to remember it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub password: Option<String>,
    /// The user accepted sending credentials over plain http to a remote host.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub allow_plain_http: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub instance: Option<Instance>,
    #[serde(default)]
    pub setup: Setup,
}

impl Connection {
    /// A remembered password is only valid for the URL, user and instance it was saved with.
    pub fn saved_password_for(&self, base_url: &str, user: &str) -> Option<&str> {
        if self.base_url == base_url && self.username == user && self.instance.is_some() {
            self.password.as_deref()
        } else {
            None
        }
    }

    pub fn namespace(&self) -> String {
        self.setup
            .namespace
            .clone()
            .unwrap_or_else(|| DEFAULT_NAMESPACE.into())
    }

    pub fn app_path(&self) -> String {
        self.setup
            .app_path
            .clone()
            .unwrap_or_else(|| DEFAULT_APP_PATH.into())
    }
}

#[derive(Debug, Default, Serialize, Deserialize)]
pub struct Store {
    #[serde(default = "store_version")]
    pub version: u32,
    #[serde(default)]
    pub connections: Vec<Connection>,
    #[serde(skip)]
    path: PathBuf,
}

fn store_version() -> u32 {
    1
}

impl Store {
    pub fn load(dir: &Path) -> io::Result<Store> {
        let path = dir.join("connections.json");
        let mut store = match fs::read_to_string(&path) {
            Ok(text) => serde_json::from_str::<Store>(&text).map_err(|e| {
                io::Error::new(
                    io::ErrorKind::InvalidData,
                    format!("{} is not valid: {e}", path.display()),
                )
            })?,
            Err(e) if e.kind() == io::ErrorKind::NotFound => Store {
                version: 1,
                ..Default::default()
            },
            Err(e) => return Err(e),
        };
        store.path = path;
        Ok(store)
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    pub fn find(&self, name: &str) -> Option<usize> {
        self.connections
            .iter()
            .position(|c| c.name.eq_ignore_ascii_case(name))
    }

    /// Write atomically: a private temp file, then rename over the old one.
    pub fn save(&self) -> io::Result<()> {
        let dir = self.path.parent().unwrap_or(Path::new("."));
        ensure_private_dir(dir)?;
        let tmp = self.path.with_extension("json.tmp");
        let body = serde_json::to_string_pretty(self).map_err(io::Error::other)?;
        {
            let mut f = private_file(&tmp)?;
            f.write_all(body.as_bytes())?;
            f.write_all(b"\n")?;
            f.sync_all()?;
        }
        fs::rename(&tmp, &self.path)
    }
}

/// Create `dir` owner-only (0700) on Unix. On Windows it inherits the parent's ACL.
pub fn ensure_private_dir(dir: &Path) -> io::Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::{DirBuilderExt, PermissionsExt};
        if !dir.exists() {
            fs::DirBuilder::new()
                .recursive(true)
                .mode(0o700)
                .create(dir)?;
        }
        fs::set_permissions(dir, fs::Permissions::from_mode(0o700))
    }
    #[cfg(not(unix))]
    {
        fs::create_dir_all(dir)
    }
}

/// Open (truncating) a file readable only by its owner (0600) on Unix.
pub fn private_file(path: &Path) -> io::Result<fs::File> {
    let mut opts = fs::OpenOptions::new();
    opts.write(true).create(true).truncate(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
        opts.mode(0o600);
        let f = opts.open(path)?;
        f.set_permissions(fs::Permissions::from_mode(0o600))?;
        Ok(f)
    }
    #[cfg(not(unix))]
    {
        opts.open(path)
    }
}

/// Validate a namespace name the same way the server does.
pub fn valid_namespace(ns: &str) -> bool {
    let mut chars = ns.chars();
    matches!(chars.next(), Some(c) if c.is_ascii_alphabetic())
        && ns.len() <= 63
        && chars.all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
}

/// Validate a web application path the same way the server does.
pub fn valid_app_path(p: &str) -> bool {
    p.starts_with('/')
        && !p.ends_with('/')
        && p[1..].split('/').all(|seg| {
            !seg.is_empty()
                && seg
                    .chars()
                    .all(|c| c.is_ascii_alphanumeric() || "_.-".contains(c))
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn full(s: &str) -> BaseUrl {
        match parse_base_url(s).unwrap() {
            UrlInput::Full(u) => u,
            other => panic!("expected full URL, got {other:?}"),
        }
    }

    #[test]
    fn url_keeps_what_was_typed_and_invents_no_port() {
        let u = full("HTTPS://IRIS.example.com/iris-prod/");
        assert_eq!(u.as_string(), "https://iris.example.com/iris-prod");
        assert_eq!(u.port, None);
        assert_eq!(
            full("http://10.0.0.12:52773").as_string(),
            "http://10.0.0.12:52773"
        );
        assert_eq!(
            full("http://[::1]:52773/x").as_string(),
            "http://[::1]:52773/x"
        );
        assert!(full("http://[::1]:52773").is_localhost());
    }

    #[test]
    fn bare_host_asks_for_scheme() {
        assert_eq!(
            parse_base_url("iris01").unwrap(),
            UrlInput::NeedsScheme("iris01".into())
        );
        assert_eq!(
            parse_base_url("iris01:52773/pre").unwrap(),
            UrlInput::NeedsScheme("iris01:52773/pre".into())
        );
        assert_eq!(
            with_scheme("http", "iris01:52773/pre").unwrap().as_string(),
            "http://iris01:52773/pre"
        );
    }

    #[test]
    fn url_rejects_bad_input() {
        for bad in [
            "",
            "ftp://x",
            "http://user:pw@host",
            "user@host",
            "http://h:0",
            "http://h:99999",
            "http://h:port",
            "http://h/a/../b",
            "http://h/?x",
            "http:// h",
            "http://",
        ] {
            assert!(parse_base_url(bad).is_err(), "{bad} should be rejected");
        }
    }

    #[test]
    fn localhost_detection() {
        assert!(full("http://localhost:52773").is_localhost());
        assert!(full("http://127.0.0.1").is_localhost());
        assert!(!full("http://10.0.0.1").is_localhost());
    }

    #[test]
    fn names_and_paths() {
        assert!(valid_namespace("OPCUA") && valid_namespace("Plant-1_A"));
        assert!(!valid_namespace("%SYS") && !valid_namespace("1ns") && !valid_namespace("a b"));
        assert!(valid_app_path("/csp/opcua/api"));
        assert!(
            !valid_app_path("csp/x")
                && !valid_app_path("/csp/")
                && !valid_app_path("/a//b")
                && !valid_app_path("/a b")
        );
    }

    #[test]
    fn saved_password_is_bound_to_url_user_and_instance() {
        let mut c = Connection {
            name: "a".into(),
            base_url: "http://h:1".into(),
            username: "u".into(),
            password: Some("p".into()),
            allow_plain_http: false,
            instance: None,
            setup: Setup::default(),
        };
        assert_eq!(c.saved_password_for("http://h:1", "u"), None);
        c.instance = Some(Instance {
            guid: "G".into(),
            ..Default::default()
        });
        assert_eq!(c.saved_password_for("http://h:1", "u"), Some("p"));
        assert_eq!(c.saved_password_for("http://h:2", "u"), None);
        assert_eq!(c.saved_password_for("http://h:1", "v"), None);
    }

    #[test]
    fn store_round_trip_is_private_and_omits_absent_password() {
        let dir = std::env::temp_dir().join(format!("opcua-setup-test-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        let mut s = Store::load(&dir).unwrap();
        s.connections.push(Connection {
            name: "a".into(),
            base_url: "http://h:1".into(),
            username: "u".into(),
            password: None,
            allow_plain_http: false,
            instance: None,
            setup: Setup::default(),
        });
        s.save().unwrap();
        let text = fs::read_to_string(s.path()).unwrap();
        assert!(!text.contains("password"));
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(
                fs::metadata(s.path()).unwrap().permissions().mode() & 0o777,
                0o600
            );
            assert_eq!(
                fs::metadata(&dir).unwrap().permissions().mode() & 0o777,
                0o700
            );
        }
        let back = Store::load(&dir).unwrap();
        assert_eq!(back.connections, s.connections);
        fs::remove_dir_all(&dir).unwrap();
    }
}

//! Inspect, plan, apply and verify, by calling `IRISConfig.ClientInstaller` over Atelier.

use crate::atelier::{Client, Error};
use crate::log;
use crate::payload::{self, Artifact, Payload, Target};
use base64::Engine;
use serde::Deserialize;
use serde_json::{json, Value};

const SYS: &str = "%SYS";
const CHUNK: usize = 256 * 1024;

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Privileges {
    pub development: bool,
    pub admin_manage: bool,
    pub admin_secure: bool,
    pub irissys_write: bool,
}

impl Privileges {
    pub fn missing(&self) -> Vec<&'static str> {
        let mut m = Vec::new();
        if !self.development {
            m.push("%Development:USE");
        }
        if !self.admin_manage {
            m.push("%Admin_Manage:USE");
        }
        if !self.admin_secure {
            m.push("%Admin_Secure:USE");
        }
        if !self.irissys_write {
            m.push("%DB_IRISSYS:WRITE");
        }
        m
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Namespace {
    pub name: String,
    pub state: String,
    #[serde(default)]
    pub reason: String,
}

pub struct NamespaceCheck {
    pub namespace: Namespace,
    /// A database file exists where the namespace's database would go, not created by this tool.
    pub foreign_database: bool,
    pub database_resource: String,
    /// Whether this account can read and write that database once it exists.
    pub database_access: bool,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Info {
    pub user: String,
    pub version: String,
    pub os: String,
    pub platform: String,
    pub bin_dir: String,
    pub privileges: Privileges,
    pub bin_writable: bool,
    #[serde(default)]
    pub namespaces: Vec<Namespace>,
}

impl Info {
    pub fn target(&self) -> Target {
        payload::target_for(&self.os, &self.platform)
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteFile {
    pub name: String,
    pub path: String,
    pub exists: bool,
    #[serde(default)]
    pub sha256: String,
    #[serde(default)]
    pub crypto: bool,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct App {
    pub state: String,
    #[serde(default)]
    pub reason: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Check {
    pub name: String,
    pub ok: bool,
    #[serde(default)]
    pub message: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Verification {
    pub ok: bool,
    #[serde(default)]
    pub checks: Vec<Check>,
    #[serde(default)]
    pub api_access: bool,
}

impl Verification {
    pub fn check(&self, name: &str) -> Option<&Check> {
        self.checks.iter().find(|c| c.name == name)
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum FileAction {
    Upload,
    Reuse,
    /// An existing crypto library different from ours: kept, never replaced.
    KeepExisting,
}

#[derive(Debug, Clone)]
pub struct Plan {
    pub namespace: String,
    pub create_namespace: bool,
    pub app_path: String,
    pub create_app: bool,
    pub target: Target,
    pub files: Vec<(Artifact, FileAction, String)>,
}

/// Why installation cannot start. `manual` carries the copy instructions when IRIS
/// cannot write its bin directory.
#[derive(Debug, Clone)]
pub struct Blocker {
    pub title: String,
    pub body: String,
}

pub enum Ping {
    Ok,
    NoAccess,
    NotRouted,
    Other(String),
}

pub struct Installer<'a> {
    pub client: &'a Client,
    pub payload: &'a Payload,
}

impl<'a> Installer<'a> {
    /// Upload and compile `IRISConfig.ClientInstaller` into %SYS. Changes no configuration.
    pub fn bootstrap(&self) -> Result<(), String> {
        let doc = self.payload.client_installer();
        let lines = payload::doc_lines(&doc.path)?;
        let explain = |e: Error| {
            match e {
            Error::Unauthorized => "IRIS refused to load the installer class into %SYS. The account needs %Development:USE and write access to %DB_IRISSYS.".to_string(),
            e => format!("Could not load the installer class into %SYS. It needs %Development:USE and write access to %DB_IRISSYS. {e}"),
        }
        };
        self.client
            .put_doc(SYS, &doc.name, &lines)
            .map_err(explain)?;
        self.client
            .compile(SYS, std::slice::from_ref(&doc.name))
            .map_err(explain)?;
        log::write("bootstrap: ClientInstaller compiled in %SYS");
        Ok(())
    }

    /// Call one ClientInstaller procedure and return its JSON result, whatever `ok` says.
    fn call(&self, proc: &str, args: &[Value]) -> Result<Value, String> {
        let marks = vec!["?"; args.len()].join(",");
        let sql = format!("SELECT IRISConfig.ClientInstaller_{proc}({marks}) AS r");
        let rows = self
            .client
            .query(SYS, &sql, args)
            .map_err(|e| format!("{proc}: {e}"))?;
        let r = rows
            .first()
            .map(|row| row["r"].clone())
            .unwrap_or(Value::Null);
        // Atelier parses a JSON string result itself; accept either form.
        let v = match r {
            Value::String(s) => serde_json::from_str(&s).map_err(|_| {
                format!(
                    "{proc}: result is not JSON: {}",
                    s.chars().take(200).collect::<String>()
                )
            })?,
            v => v,
        };
        if v.get("ok").and_then(Value::as_bool).is_none() || v.get("step").is_none() {
            return Err(format!(
                "{proc}: malformed result from IRIS: {}",
                v.to_string().chars().take(200).collect::<String>()
            ));
        }
        log::write(&format!(
            "{proc}: ok={} {}",
            v["ok"],
            v["message"].as_str().unwrap_or("")
        ));
        Ok(v)
    }

    /// Like `call`, but a result with `ok: false` becomes an error with the server's message.
    fn call_ok(&self, proc: &str, args: &[Value]) -> Result<Value, String> {
        let v = self.call(proc, args)?;
        if v["ok"] == true {
            Ok(v)
        } else {
            Err(v["message"]
                .as_str()
                .filter(|m| !m.is_empty())
                .unwrap_or("IRIS reported a failure without a message.")
                .to_string())
        }
    }

    pub fn info(&self) -> Result<Info, String> {
        let v = self.call_ok("Info", &[])?;
        serde_json::from_value(v).map_err(|e| format!("Info: unexpected result: {e}"))
    }

    pub fn inspect_namespace(&self, ns: &str) -> Result<NamespaceCheck, String> {
        let v = self.call_ok("InspectNamespace", &[json!(ns)])?;
        let namespace = serde_json::from_value(v["namespace"].clone())
            .map_err(|e| format!("InspectNamespace: {e}"))?;
        Ok(NamespaceCheck {
            namespace,
            foreign_database: v["databaseExists"] == true,
            database_resource: v["databaseResource"]
                .as_str()
                .unwrap_or_default()
                .to_string(),
            database_access: v["databaseAccess"] == true,
        })
    }

    pub fn inspect_app(&self, path: &str, ns: &str) -> Result<App, String> {
        let v = self.call_ok("InspectApp", &[json!(path), json!(ns)])?;
        serde_json::from_value(v["app"].clone()).map_err(|e| format!("InspectApp: {e}"))
    }

    pub fn inspect_files(&self, names: &[&str]) -> Result<Vec<RemoteFile>, String> {
        let v = self.call_ok("InspectFiles", &[json!(names.join(","))])?;
        serde_json::from_value(v["files"].clone()).map_err(|e| format!("InspectFiles: {e}"))
    }

    pub fn verify(&self, ns: &str, path: &str) -> Result<Verification, String> {
        let v = self.call("Verify", &[json!(ns), json!(path)])?;
        if v["checks"].is_null() {
            return Err(v["message"].as_str().unwrap_or("Verify failed").to_string());
        }
        serde_json::from_value(v).map_err(|e| format!("Verify: {e}"))
    }

    /// Read-only preflight. Returns the plan, or every blocker found.
    pub fn preflight(&self, info: &Info, ns: &str, app_path: &str) -> Result<Plan, Vec<Blocker>> {
        let mut blockers = Vec::new();
        let mut block = |t: &str, b: String| {
            blockers.push(Blocker {
                title: t.into(),
                body: b,
            })
        };

        let target = info.target();
        if let Target::Unsupported(p) = &target {
            block(
                "Unsupported server platform",
                format!(
                    "IRIS reports {p}. This installer supports Linux x86-64 and ARM64 servers."
                ),
            );
        }
        let missing = info.privileges.missing();
        if !missing.is_empty() {
            block("Missing IRIS privileges", format!("The account {} lacks: {}. Ask an IRIS administrator to grant them (for example through a role), then retry. This tool never grants privileges.", info.user, missing.join(", ")));
        }
        let absent = self.payload.missing_files();
        if !absent.is_empty() {
            block(
                "Source payload incomplete",
                format!(
                    "Missing under {}: {}",
                    self.payload.root.display(),
                    absent.join(", ")
                ),
            );
        }

        let mut create_namespace = false;
        match self.inspect_namespace(ns) {
            Ok(c) => match c.namespace.state.as_str() {
                "conflict" => block("Namespace conflict", format!("Namespace {ns} is used by something else: {}. It was not changed. Choose a separate namespace.", c.namespace.reason)),
                "missing" if c.foreign_database => block("Database file exists", format!("Namespace {ns} does not exist, but a database file already exists in its default directory. It was not touched. Choose another namespace name.")),
                _ if !c.database_access => {
                    let res = &c.database_resource;
                    let first = if c.namespace.state == "missing" { format!("create the resource {res} and ") } else { String::new() };
                    block("No access to the namespace database", format!(
                        "The account {} would not be able to use the database of {ns}, which is protected by resource {res}. Either run this tool as an account with the %All role, or have an IRIS administrator {first}grant {res}:RW to your account through a role. Then retry.",
                        info.user))
                }
                "missing" => create_namespace = true,
                _ => {}
            },
            Err(e) => block("Namespace check failed", e),
        }

        let mut create_app = false;
        match self.inspect_app(app_path, ns) {
            Ok(a) if a.state == "conflict" => block("REST application conflict", a.reason),
            Ok(a) => create_app = a.state == "missing",
            Err(e) => block("REST application check failed", e),
        }

        let mut files = Vec::new();
        if let Target::Linux(_) = target {
            match self.payload.artifacts(&target) {
                Ok(artifacts) => {
                    let names: Vec<&str> = artifacts.iter().map(|a| a.name).collect();
                    match self.inspect_files(&names) {
                        Ok(remote) => {
                            for a in artifacts {
                                let r = remote.iter().find(|r| r.name == a.name);
                                let dest = r
                                    .map(|r| r.path.clone())
                                    .unwrap_or_else(|| format!("{}{}", info.bin_dir, a.name));
                                let action = match r {
                                    Some(r) if r.exists && r.sha256 == a.sha256 => {
                                        FileAction::Reuse
                                    }
                                    Some(r) if r.exists && r.crypto => FileAction::KeepExisting,
                                    Some(r) if r.exists => {
                                        block("Native library conflict", format!("{} already exists with different content (SHA-256 {}). It was not replaced. Replace it with the supplied file during a maintenance window (IRIS may have it loaded), then retry.", r.path, r.sha256));
                                        FileAction::Reuse
                                    }
                                    _ => FileAction::Upload,
                                };
                                files.push((a, action, dest));
                            }
                        }
                        Err(e) => block("Native library check failed", e),
                    }
                }
                Err(e) => block("Native artifacts missing", e),
            }
        }

        let uploads: Vec<&(Artifact, FileAction, String)> =
            files.iter().filter(|f| f.1 == FileAction::Upload).collect();
        if !uploads.is_empty() && !info.bin_writable {
            let list = uploads
                .iter()
                .map(|(a, _, dest)| {
                    format!(
                        "  {}\n    to     {dest}\n    SHA-256 {}",
                        a.path.display(),
                        a.sha256
                    )
                })
                .collect::<Vec<_>>()
                .join("\n");
            block("IRIS cannot write its bin directory", format!("Nothing was changed. Ask a server administrator to copy these files onto the IRIS server, readable by the IRIS process:\n{list}\nThen choose Retry: the files are verified by hash before installation continues."));
        }

        if blockers.is_empty() {
            Ok(Plan {
                namespace: ns.into(),
                create_namespace,
                app_path: app_path.into(),
                create_app,
                target,
                files,
            })
        } else {
            Err(blockers)
        }
    }

    /// Stream one file into IRIS's bin directory in chunks, then verify and move it into place.
    pub fn install_file(&self, a: &Artifact) -> Result<String, String> {
        let bytes = std::fs::read(&a.path).map_err(|e| format!("{}: {e}", a.path.display()))?;
        if payload::sha256_hex(&bytes) != a.sha256 {
            return Err(format!(
                "{} changed on disk during installation.",
                a.path.display()
            ));
        }
        let engine = base64::engine::general_purpose::STANDARD;
        for (i, chunk) in bytes.chunks(CHUNK).enumerate() {
            self.call_ok(
                "StageChunk",
                &[
                    json!(a.name),
                    json!(engine.encode(chunk)),
                    json!(if i == 0 { 1 } else { 0 }),
                ],
            )?;
        }
        let v = self.call_ok("CommitFile", &[json!(a.name), json!(a.sha256)])?;
        Ok(v["action"].as_str().unwrap_or("installed").to_string())
    }

    pub fn create_namespace(&self, ns: &str) -> Result<String, String> {
        let v = self.call_ok("CreateNamespace", &[json!(ns)])?;
        Ok(v["action"].as_str().unwrap_or("").to_string())
    }

    /// Upload Constants.inc first, then the classes; compile exactly those documents.
    pub fn import_classes(&self, ns: &str) -> Result<usize, String> {
        let docs = self.payload.application_docs()?;
        for d in &docs {
            let lines = payload::doc_lines(&d.path)?;
            self.client
                .put_doc(ns, &d.name, &lines)
                .map_err(|e| format!("Uploading {}: {e}", d.name))?;
        }
        let names: Vec<String> = docs.iter().map(|d| d.name.clone()).collect();
        self.client
            .compile(ns, &names)
            .map_err(|e| format!("Compilation failed. {e}"))?;
        log::write(&format!(
            "import: {} documents compiled in {ns}",
            names.len()
        ));
        Ok(names.len())
    }

    pub fn register_library(&self, ns: &str) -> Result<String, String> {
        let v = self.call_ok("RegisterLibrary", &[json!(ns)])?;
        Ok(v["version"]
            .as_str()
            .map(String::from)
            .unwrap_or_else(|| v["version"].to_string()))
    }

    pub fn create_app(&self, path: &str, ns: &str) -> Result<Value, String> {
        self.call_ok("CreateApp", &[json!(path), json!(ns)])
    }

    /// Authenticated `GET {base}{app}/ping`, from this machine.
    pub fn ping(&self, app_path: &str, api_access: bool) -> Ping {
        match self.client.get(&format!("{app_path}/ping")) {
            Ok((200, body))
                if serde_json::from_str::<Value>(&body).is_ok_and(|v| v["status"] == "ok") =>
            {
                Ping::Ok
            }
            Ok((200, _)) => Ping::Other("the response is not the OPC UA API".into()),
            // IRIS answers 404, not 401, when the account may not use the application.
            Ok((404, _)) if !api_access => Ping::NoAccess,
            Ok((404, _)) => Ping::NotRouted,
            Ok((401, _)) => Ping::NoAccess,
            Ok((code, _)) => Ping::Other(format!("HTTP {code}")),
            Err(e) => Ping::Other(e.to_string()),
        }
    }
}

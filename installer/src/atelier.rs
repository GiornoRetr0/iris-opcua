//! HTTP client for IRIS's built-in Atelier REST API (`/api/atelier`).
//!
//! Credentials travel only in the `Authorization` header. Redirects are not followed,
//! so the header is never replayed to another address.

use base64::Engine;
use serde_json::{json, Value};
use std::fmt;
use std::time::Duration;

/// What went wrong talking to the server, in terms the user can act on.
#[derive(Debug)]
pub enum Error {
    Unreachable(String),
    Tls(String),
    Timeout,
    Redirect(String),
    /// 401: wrong password, unknown user, or no %Development (Atelier cannot tell them apart).
    Unauthorized,
    /// IRIS answers, but `/api/atelier` is disabled or not routed.
    AtelierDisabled,
    NotIris(String),
    Http(u16, String),
    /// Atelier accepted the request but reported errors in `status.errors`.
    Atelier(Vec<String>),
    Malformed(String),
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::Unreachable(d) => write!(f, "Cannot reach the server: {d}. Check the host, port and path prefix, and that the web server is running."),
            Error::Tls(d) => write!(f, "TLS handshake failed: {d}. If the server's certificate comes from an internal CA, note that this tool trusts only public CAs."),
            Error::Timeout => write!(f, "The server did not answer in time."),
            Error::Redirect(to) => write!(f, "The server redirects to {to}. Use that address as the base URL."),
            Error::Unauthorized => write!(f, "IRIS rejected the sign-in: the username or password is wrong, or the account lacks %Development, which the Atelier API requires."),
            Error::AtelierDisabled => write!(f, "This is an IRIS web server, but the Atelier API (/api/atelier) is disabled or not routed. Enable the /api/atelier web application in the Management Portal (System Administration > Security > Applications > Web Applications), or allow it in the web gateway."),
            Error::NotIris(d) => write!(f, "The address does not look like an IRIS web server ({d}). Check the port and path prefix."),
            Error::Http(code, d) => write!(f, "HTTP {code}: {d}"),
            Error::Atelier(errs) => write!(f, "IRIS reported: {}", errs.join("; ")),
            Error::Malformed(d) => write!(f, "Unexpected response from IRIS: {d}"),
        }
    }
}

/// What `GET /api/atelier/` reports about the server.
#[derive(Debug, Clone)]
pub struct ServerInfo {
    pub version: String,
    pub instance_id: String,
    pub interoperability: bool,
}

pub struct Client {
    agent: ureq::Agent,
    base: String,
    auth: String,
    secret: String,
}

impl Client {
    pub fn new(base: &str, user: &str, password: &str) -> Client {
        let config = ureq::Agent::config_builder()
            .http_status_as_error(false)
            .max_redirects(0)
            .max_redirects_will_error(false)
            .timeout_connect(Some(Duration::from_secs(10)))
            .timeout_global(Some(Duration::from_secs(600)))
            .user_agent(concat!("iris-opcua-setup/", env!("CARGO_PKG_VERSION")))
            .build();
        let token = base64::engine::general_purpose::STANDARD.encode(format!("{user}:{password}"));
        Client {
            agent: config.into(),
            base: base.to_string(),
            auth: format!("Basic {token}"),
            secret: password.to_string(),
        }
    }

    /// Remove the password from any text that might reach the terminal or a log.
    pub fn redact(&self, text: &str) -> String {
        redact(text, &self.secret)
    }

    /// Identify the server without sending credentials: Atelier asks for Basic auth,
    /// a disabled Atelier on IRIS 404s while the Portal login page still answers.
    pub fn probe(&self) -> Result<(), Error> {
        let (code, headers, _) = self.request("GET", "/api/atelier/", None, false)?;
        match code {
            401 | 200 => Ok(()),
            300..=399 => Err(Error::Redirect(headers.location.unwrap_or_default())),
            404 => {
                let (c, _, body) = self.request("GET", "/csp/sys/UtilHome.csp", None, false)?;
                if c == 200 && body.contains("IRIS") {
                    Err(Error::AtelierDisabled)
                } else {
                    Err(Error::NotIris(format!(
                        "HTTP 404 for /api/atelier/{}",
                        server_note(&headers)
                    )))
                }
            }
            c => Err(Error::NotIris(format!(
                "HTTP {c} for /api/atelier/{}",
                server_note(&headers)
            ))),
        }
    }

    /// `GET /api/atelier/` with credentials.
    pub fn authenticate(&self) -> Result<ServerInfo, Error> {
        let v = self.json("GET", "/api/atelier/", None)?;
        let c = &v["result"]["content"];
        let version = c["version"].as_str().unwrap_or_default().to_string();
        if !version.contains("IRIS") {
            return Err(Error::NotIris(
                "no IRIS version in the Atelier response".into(),
            ));
        }
        let features = c["features"].as_array().cloned().unwrap_or_default();
        Ok(ServerInfo {
            version,
            instance_id: c["id"].as_str().unwrap_or_default().to_string(),
            interoperability: features
                .iter()
                .any(|f| f["name"] == "ENSEMBLE" && f["enabled"] == true),
        })
    }

    /// Upload one document, overwriting the server copy.
    pub fn put_doc(&self, ns: &str, name: &str, lines: &[String]) -> Result<(), Error> {
        let path = format!(
            "/api/atelier/v1/{}/doc/{}?ignoreConflict=1",
            enc(ns),
            enc(name)
        );
        self.json(
            "PUT",
            &path,
            Some(json!({ "enc": false, "content": lines })),
        )
        .map(|_| ())
    }

    /// Compile documents. Atelier returns HTTP 200 even when compilation fails, so
    /// `status.errors` and error lines in the console output decide the outcome.
    pub fn compile(&self, ns: &str, docs: &[String]) -> Result<Vec<String>, Error> {
        let path = format!("/api/atelier/v1/{}/action/compile?flags=cuk", enc(ns));
        let v = self.json("POST", &path, Some(json!(docs)))?;
        let console: Vec<String> = v["console"]
            .as_array()
            .map(|a| {
                a.iter()
                    .filter_map(|l| l.as_str().map(String::from))
                    .collect()
            })
            .unwrap_or_default();
        let errors: Vec<String> = console
            .iter()
            .filter(|l| l.contains("ERROR"))
            .cloned()
            .collect();
        if !errors.is_empty() {
            return Err(Error::Atelier(errors));
        }
        Ok(console)
    }

    /// Run SQL with bound parameters; returns the result rows.
    pub fn query(&self, ns: &str, sql: &str, params: &[Value]) -> Result<Vec<Value>, Error> {
        let path = format!("/api/atelier/v1/{}/action/query", enc(ns));
        let v = self.json(
            "POST",
            &path,
            Some(json!({ "query": sql, "parameters": params })),
        )?;
        v["result"]["content"]
            .as_array()
            .cloned()
            .ok_or_else(|| Error::Malformed("query returned no rows".into()))
    }

    /// Authenticated GET of an arbitrary path under the base URL (the OPC UA API ping).
    pub fn get(&self, path: &str) -> Result<(u16, String), Error> {
        let (code, _, body) = self.request("GET", path, None, true)?;
        Ok((code, body))
    }

    fn json(&self, method: &str, path: &str, body: Option<Value>) -> Result<Value, Error> {
        let (code, headers, text) = self.request(method, path, body, true)?;
        match code {
            401 | 403 => return Err(Error::Unauthorized),
            300..=399 => return Err(Error::Redirect(headers.location.unwrap_or_default())),
            404 if path == "/api/atelier/" => return Err(Error::AtelierDisabled),
            _ => {}
        }
        let v: Value = serde_json::from_str(&text).map_err(|_| {
            if code == 200 {
                Error::NotIris("the response is not Atelier JSON".into())
            } else {
                Error::Http(code, snippet(&text))
            }
        })?;
        let mut errors = status_errors(&v);
        // A rejected document upload reports its error in result.status instead.
        if let Some(s) = v["result"]["status"].as_str().filter(|s| !s.is_empty()) {
            errors.push(s.to_string());
        }
        if !errors.is_empty() {
            return Err(Error::Atelier(
                errors.iter().map(|e| self.redact(e)).collect(),
            ));
        }
        if !(200..300).contains(&code) {
            return Err(Error::Http(code, snippet(&text)));
        }
        Ok(v)
    }

    fn request(
        &self,
        method: &str,
        path: &str,
        body: Option<Value>,
        auth: bool,
    ) -> Result<(u16, Headers, String), Error> {
        let url = format!("{}{}", self.base, path);
        let result = match (method, body) {
            ("GET", _) => {
                let mut r = self.agent.get(&url);
                if auth {
                    r = r.header("Authorization", &self.auth);
                }
                r.call()
            }
            (m, body) => {
                let mut r = match m {
                    "PUT" => self.agent.put(&url),
                    _ => self.agent.post(&url),
                };
                if auth {
                    r = r.header("Authorization", &self.auth);
                }
                let bytes = body.map(|b| b.to_string()).unwrap_or_default();
                r.content_type("application/json").send(bytes.as_bytes())
            }
        };
        let mut resp = result.map_err(|e| classify(&e, &self.secret))?;
        let code = resp.status().as_u16();
        let headers = Headers {
            location: resp
                .headers()
                .get("location")
                .and_then(|v| v.to_str().ok())
                .map(String::from),
            server: resp
                .headers()
                .get("server")
                .and_then(|v| v.to_str().ok())
                .map(String::from),
        };
        let text = resp
            .body_mut()
            .with_config()
            .limit(64 * 1024 * 1024)
            .read_to_string()
            .map_err(|e| classify(&e, &self.secret))?;
        Ok((code, headers, text))
    }
}

struct Headers {
    location: Option<String>,
    server: Option<String>,
}

fn server_note(h: &Headers) -> String {
    h.server
        .as_ref()
        .map(|s| format!(", server '{s}'"))
        .unwrap_or_default()
}

fn classify(e: &ureq::Error, secret: &str) -> Error {
    use ureq::Error as E;
    let text = redact(&e.to_string(), secret);
    match e {
        E::Timeout(_) => Error::Timeout,
        E::HostNotFound => Error::Unreachable("host name not found".into()),
        E::ConnectionFailed => Error::Unreachable("connection refused or failed".into()),
        E::Tls(_) | E::Rustls(_) => Error::Tls(text),
        E::Io(io) if io.kind() == std::io::ErrorKind::TimedOut => Error::Timeout,
        E::Io(io)
            if matches!(
                io.kind(),
                std::io::ErrorKind::ConnectionRefused
                    | std::io::ErrorKind::ConnectionReset
                    | std::io::ErrorKind::ConnectionAborted
            ) =>
        {
            Error::Unreachable(text)
        }
        E::Protocol(_) => Error::NotIris(format!("not an HTTP response: {text}")),
        _ if text.to_ascii_lowercase().contains("tls") || text.contains("certificate") => {
            Error::Tls(text)
        }
        _ => Error::Unreachable(text),
    }
}

fn status_errors(v: &Value) -> Vec<String> {
    v["status"]["errors"]
        .as_array()
        .map(|a| {
            a.iter()
                .map(|e| {
                    e["error"]
                        .as_str()
                        .map(String::from)
                        .unwrap_or_else(|| e.to_string())
                })
                .collect()
        })
        .unwrap_or_default()
}

/// Percent-encode a path segment (namespaces such as `%SYS`, document names).
pub fn enc(s: &str) -> String {
    s.bytes()
        .map(|b| match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' => {
                (b as char).to_string()
            }
            _ => format!("%{b:02X}"),
        })
        .collect()
}

fn snippet(text: &str) -> String {
    let t: String = text.chars().filter(|c| !c.is_control()).take(200).collect();
    if t.is_empty() {
        "empty response".into()
    } else {
        t
    }
}

/// Replace every occurrence of the secret (and its Basic-auth form) with `***`.
pub fn redact(text: &str, secret: &str) -> String {
    if secret.is_empty() {
        return text.to_string();
    }
    text.replace(secret, "***")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encodes_namespace_and_doc_names() {
        assert_eq!(enc("%SYS"), "%25SYS");
        assert_eq!(enc("OPCUA.REST.Handler.cls"), "OPCUA.REST.Handler.cls");
        assert_eq!(enc("a b/c"), "a%20b%2Fc");
    }

    #[test]
    fn redaction_removes_password() {
        assert_eq!(
            redact("login s3cr3t! failed for s3cr3t!", "s3cr3t!"),
            "login *** failed for ***"
        );
        assert_eq!(redact("nothing", ""), "nothing");
        let c = Client::new("http://h:1", "u", "pw-123");
        assert!(!c
            .redact("Authorization failed with pw-123")
            .contains("pw-123"));
    }

    #[test]
    fn status_errors_are_extracted() {
        let v: Value =
            serde_json::from_str(r#"{"status":{"errors":[{"error":"ERROR #5001: boom"}]}}"#)
                .unwrap();
        assert_eq!(status_errors(&v), vec!["ERROR #5001: boom".to_string()]);
        assert!(status_errors(&json!({"status":{"errors":[]}})).is_empty());
    }

    #[test]
    fn unreachable_port_is_reported_as_unreachable() {
        // Port 9 (discard) on localhost is closed on any normal machine.
        let c = Client::new("http://127.0.0.1:9", "u", "p");
        assert!(matches!(c.probe(), Err(Error::Unreachable(_))));
    }
}

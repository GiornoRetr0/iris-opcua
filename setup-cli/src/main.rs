//! `iris-opcua-setup`: installs and verifies the IRIS OPC UA backend on an existing
//! IRIS instance, over the Atelier REST API, then hands off to the webapp.
//!
//! OPC UA servers, certificates, schemas and pipelines are configured in the webapp,
//! never here.

mod atelier;
mod config;
mod installer;
mod log;
mod payload;
mod ui;

use atelier::{Client, Error, ServerInfo};
use config::{BaseUrl, Connection, Instance, Setup, Store, UrlInput};
use installer::{FileAction, Info, Installer, Ping, Plan, Verification};
use payload::Payload;
use std::path::{Path, PathBuf};
use ui::{action_key, back_key, disabled, gap, item, quit_key, section, Frame, Status};

const HELP: &str = "\
iris-opcua-setup — install the IRIS OPC UA backend on an existing IRIS instance

Usage: iris-opcua-setup [--dist <path>]

Options:
  --dist <path>   Repository checkout holding src/objectscript and bin/
                  (default: the checkout containing this program)
  -V, --version   Print the version
  -h, --help      Print this help

The tool is interactive. It connects over HTTP(S) to IRIS's Atelier API
(/api/atelier), so it needs the instance's web server address and an IRIS
account with %Development, %Admin_Manage, %Admin_Secure and write access to
%DB_IRISSYS. Local state is kept in the tool's local/ folder.";

struct App {
    store: Store,
    payload: Payload,
    local: PathBuf,
}

struct Session {
    idx: usize,
    client: Client,
    server: ServerInfo,
}

enum Next {
    SignIn,
    Quit,
}

fn main() {
    let dist = match parse_args() {
        Ok(d) => d,
        Err(e) => {
            eprintln!("{e}\n\nRun with --help for usage.");
            std::process::exit(2);
        }
    };
    ui::init();
    if !ui::stdin_is_terminal() {
        eprintln!("iris-opcua-setup is interactive: sign-in needs a terminal, and passwords are never read from redirected input.");
        std::process::exit(2);
    }
    let payload = match Payload::locate(dist) {
        Ok(p) => p,
        Err(e) => {
            eprintln!("{e}");
            std::process::exit(2);
        }
    };
    let local = local_dir(&payload);
    if let Err(e) = log::open(&local) {
        eprintln!("Warning: cannot open the log in {}: {e}", local.display());
    }
    log::write("start");
    let store = match Store::load(&local) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("{e}");
            std::process::exit(2);
        }
    };
    let mut app = App {
        store,
        payload,
        local,
    };
    loop {
        let Some(session) = sign_in(&mut app) else {
            break;
        };
        match session_menu(&mut app, session) {
            Next::SignIn => continue,
            Next::Quit => break,
        }
    }
    log::write("exit");
    println!();
}

fn parse_args() -> Result<Option<PathBuf>, lexopt::Error> {
    use lexopt::prelude::*;
    let mut dist = None;
    let mut parser = lexopt::Parser::from_env();
    while let Some(arg) = parser.next()? {
        match arg {
            Long("dist") => dist = Some(PathBuf::from(parser.value()?)),
            Short('V') | Long("version") => {
                println!("iris-opcua-setup {}", env!("CARGO_PKG_VERSION"));
                std::process::exit(0);
            }
            Short('h') | Long("help") => {
                println!("{HELP}");
                std::process::exit(0);
            }
            _ => return Err(arg.unexpected()),
        }
    }
    Ok(dist)
}

/// `setup-cli/local/` next to the sources when run from a checkout, else `local/` beside the binary.
fn local_dir(payload: &Payload) -> PathBuf {
    if let Ok(exe) = std::env::current_exe() {
        let exe = exe.canonicalize().unwrap_or(exe);
        if let Some(dir) = exe
            .ancestors()
            .find(|d| d.join("Cargo.toml").is_file() && d.join("src/main.rs").is_file())
        {
            return dir.join("local");
        }
        let tool = payload.root.join("setup-cli");
        if exe.starts_with(&payload.root) && tool.is_dir() {
            return tool.join("local");
        }
        if let Some(dir) = exe.parent() {
            return dir.join("local");
        }
    }
    PathBuf::from("local")
}

fn ctx(c: &Connection) -> String {
    format!("{} · {} · {}", c.name, c.base_url, c.username)
}

fn save(app: &App) -> Option<String> {
    app.store
        .save()
        .err()
        .map(|e| format!("Could not save {}: {e}", app.store.path().display()))
}

// ---------------------------------------------------------------- sign-in gate

/// Delete a saved connection after confirmation. `highlighted` is the list key of the
/// connection under the cursor; without one (plain mode) the number is asked for.
fn delete_connection(app: &mut App, highlighted: &str) -> Option<(Status, String)> {
    let number = if highlighted.is_empty() {
        let f = Frame::new("Delete connection");
        ui::input(&f, "Number of the connection to delete", "")
    } else {
        highlighted.to_string()
    };
    let i = number
        .parse::<usize>()
        .ok()
        .filter(|i| *i >= 1 && *i <= app.store.connections.len())?
        - 1;
    let c = &app.store.connections[i];
    let mut f = Frame::new("Delete connection").context(&ctx(c));
    f.text(&format!(
        "Delete the connection '{}' ({})? Its URL, username, saved password and setup choices are removed from this machine. Nothing on the IRIS server changes.",
        c.name, c.base_url
    ));
    if !ui::yes_no(&f, "Delete it", "Keep it", false) {
        return None;
    }
    let name = app.store.connections.remove(i).name;
    log::write(&format!("deleted connection {name}"));
    Some(match save(app) {
        None => (Status::Ok, format!("Connection '{name}' deleted.")),
        Some(e) => (Status::Fail, e),
    })
}

fn sign_in(app: &mut App) -> Option<Session> {
    let mut notice: Option<(Status, String)> = None;
    loop {
        let mut f = Frame::new("Choose a connection");
        f.notice = notice.take();
        if app.store.connections.is_empty() {
            f.text("No connections yet. A connection is the web server address of an IRIS instance plus an IRIS account.");
        } else {
            f.dim("Pick the IRIS instance to work with, or define a new one.");
        }
        let mut entries = Vec::new();
        if !app.store.connections.is_empty() {
            entries.push(section("Saved connections"));
            let w = app
                .store
                .connections
                .iter()
                .map(|c| c.name.chars().count())
                .max()
                .unwrap_or(0)
                .max(8);
            for (i, c) in app.store.connections.iter().enumerate() {
                let saved = if c.password.is_some() {
                    "saved login"
                } else {
                    "asks for password"
                };
                entries.push(item(
                    (i + 1).to_string(),
                    format!("{:<w$}  {}", c.name, c.base_url),
                    saved,
                ));
            }
            entries.push(gap());
        }
        entries.push(item("N", "New connection", "name, URL and login"));
        if !app.store.connections.is_empty() {
            entries.push(action_key("D", "Delete"));
        }
        entries.push(quit_key());
        let default = if app.store.connections.is_empty() {
            "N"
        } else {
            "1"
        };
        let (key, highlighted) = ui::menu_at(&f, &entries, default);
        match key.as_str() {
            "Q" => return None,
            "D" => notice = delete_connection(app, &highlighted),
            "N" => {
                if let Some(c) = define_connection(app, None) {
                    if let Some(s) = authenticate(app, c, None) {
                        return Some(s);
                    }
                }
            }
            n => {
                if let Ok(i) = n.parse::<usize>() {
                    let c = app.store.connections[i - 1].clone();
                    if let Some(s) = authenticate(app, c, Some(i - 1)) {
                        return Some(s);
                    }
                }
            }
        }
    }
}

/// Ask for name, base URL and username, one screen each. `prefill` keeps earlier answers.
fn define_connection(app: &App, prefill: Option<&Connection>) -> Option<Connection> {
    let mut f = Frame::new(if prefill.is_some() {
        "Edit connection"
    } else {
        "New connection"
    });
    f.dim(
        "A connection is how this tool reaches IRIS: its web server address and an IRIS account.",
    );
    f.blank();

    let mut error = None;
    let name = loop {
        let mut g = f.clone();
        g.error = error.take();
        g.text("Name — a local label for this connection, for example iris-prod.");
        let n = ui::input(&g, "Name", prefill.map(|c| c.name.as_str()).unwrap_or(""));
        if n.is_empty() || n.chars().any(char::is_control) || n.chars().count() > 40 {
            error = Some("Enter a short name (up to 40 characters).".into());
            continue;
        }
        let clash = app.store.find(&n).is_some_and(|i| {
            prefill.is_none_or(|p| !app.store.connections[i].name.eq_ignore_ascii_case(&p.name))
        });
        if clash {
            error = Some(format!("A connection named '{n}' already exists."));
            continue;
        }
        break n;
    };
    f.kv("Name", &name);

    let url = loop {
        let mut g = f.clone();
        g.error = error.take();
        g.blank();
        g.text("Base URL — how to reach the IRIS web server: http(s)://host(:port)/pathPrefix, or just the host name or IP.");
        let raw = ui::input(
            &g,
            "Base URL",
            prefill.map(|c| c.base_url.as_str()).unwrap_or(""),
        );
        let parsed = match config::parse_base_url(&raw) {
            Ok(UrlInput::Full(u)) => u,
            Ok(UrlInput::NeedsScheme(host)) => match ask_scheme(&f, &host) {
                Some(u) => u,
                None => continue,
            },
            Err(e) => {
                error = Some(e);
                continue;
            }
        };
        if parsed.port.is_some() || confirm_no_port(&f, &parsed) {
            break parsed.as_string();
        }
    };
    f.kv("Base URL", &url);

    let username = loop {
        let mut g = f.clone();
        g.error = error.take();
        g.blank();
        g.text(
            "Username — an IRIS account allowed to install (see the README for the privileges).",
        );
        let u = ui::input(
            &g,
            "Username",
            prefill.map(|c| c.username.as_str()).unwrap_or(""),
        );
        if !u.is_empty() && !u.contains(':') {
            break u;
        }
        error = Some("Enter an IRIS username (it cannot contain ':').".into());
    };

    let mut c = prefill.cloned().unwrap_or(Connection {
        name: String::new(),
        base_url: String::new(),
        username: String::new(),
        password: None,
        allow_plain_http: false,
        instance: None,
        setup: Setup::default(),
    });
    if c.base_url != url || c.username != username {
        c.password = None;
        c.allow_plain_http = false;
    }
    c.name = name;
    c.base_url = url;
    c.username = username;
    Some(c)
}

fn ask_scheme(f: &Frame, host: &str) -> Option<BaseUrl> {
    let mut g = f.clone();
    g.blank();
    g.text(&format!(
        "'{host}' has no scheme. Which one does the IRIS web server use?"
    ));
    let entries = [
        item("1", "https", "encrypted"),
        item("2", "http", "unencrypted"),
        item("B", "Back", "enter the URL again"),
    ];
    let scheme = match ui::menu(&g, &entries, "1").as_str() {
        "1" => "https",
        "2" => "http",
        _ => return None,
    };
    config::with_scheme(scheme, host).ok()
}

/// Without a port, warn and show the URL exactly as it will be used.
fn confirm_no_port(f: &Frame, u: &BaseUrl) -> bool {
    let mut g = f.clone();
    g.blank();
    g.status(Status::Action, "No port was given.");
    g.detail(&format!(
        "The URL will be used exactly as written, so the {} default port applies. IRIS's own web server usually listens on another port (often 52773). Nothing is assumed.",
        u.scheme
    ));
    g.blank();
    g.kv("URL", &u.as_string());
    let entries = [
        item("E", "Enter the URL again", ""),
        item("U", "Use it as written", ""),
    ];
    ui::menu(&g, &entries, "E") == "U"
}

/// Probe, then authenticate. `idx` is the stored connection being used, if any.
fn authenticate(app: &mut App, mut conn: Connection, idx: Option<usize>) -> Option<Session> {
    let mut typed: Option<String> = None;
    let mut error: Option<String> = None;
    loop {
        let mut f = Frame::new("Sign in").context(&ctx(&conn));
        f.kv("Connection", &conn.name);
        f.kv("Base URL", &conn.base_url);
        f.kv("Username", &conn.username);
        f.error = error.take();
        let (password, remembered) = match typed.take() {
            Some(p) => (p, false),
            None => match conn.saved_password_for(&conn.base_url, &conn.username) {
                Some(p) => (p.to_string(), true),
                None => (ui::secret(&f, "Password"), false),
            },
        };
        f.error = None;
        log::secret(&password);
        let client = Client::new(&conn.base_url, &conn.username, &password);
        let probed = ui::busy(&f, &format!("Connecting to {}", conn.base_url), || {
            client.probe()
        });
        if probed.is_ok() && !plain_http_allowed(&f, &mut conn) {
            return None;
        }
        let result = probed.and_then(|_| ui::busy(&f, "Signing in", || client.authenticate()));
        match result {
            Ok(server) => {
                if let Some(inst) = conn
                    .instance
                    .as_ref()
                    .filter(|i| !i.guid.is_empty() && i.guid != server.instance_id)
                {
                    let mut g =
                        Frame::new("A different IRIS instance answered").context(&ctx(&conn));
                    g.status(
                        Status::Fail,
                        "This URL now reaches a different IRIS instance.",
                    );
                    g.detail(&format!(
                        "{} was recorded as instance {}, but it now answers as {}. Nothing was changed.",
                        conn.base_url, inst.guid, server.instance_id
                    ));
                    g.blank();
                    g.text("If this is intended (for example the server was rebuilt), make it this connection's new target. Its saved setup choices and saved password are cleared.");
                    if !ui::yes_no(&g, "Use the new instance", "Go back", false) {
                        return None;
                    }
                    conn.setup = Setup::default();
                    conn.password = None;
                }
                let platform = conn
                    .instance
                    .as_ref()
                    .map(|i| i.platform.clone())
                    .unwrap_or_default();
                conn.instance = Some(Instance {
                    guid: server.instance_id.clone(),
                    version: server.version.clone(),
                    platform,
                });
                if !remembered {
                    let mut g = Frame::new("Remember the password?").context(&ctx(&conn));
                    g.status(Status::Ok, "Signed in.");
                    g.blank();
                    g.text(&format!(
                        "If you remember it, the password is saved in plain text in {} — a file only your user can read, never committed. Otherwise you enter it on every launch.",
                        app.store.path().display()
                    ));
                    conn.password = ui::yes_no(&g, "Yes, remember it", "No, ask every time", true)
                        .then_some(password);
                }
                let i = match idx {
                    Some(i) => {
                        app.store.connections[i] = conn;
                        i
                    }
                    None => {
                        app.store.connections.push(conn);
                        app.store.connections.len() - 1
                    }
                };
                let _ = save(app);
                log::write(&format!(
                    "signed in: {} {}",
                    app.store.connections[i].name, app.store.connections[i].base_url
                ));
                return Some(Session {
                    idx: i,
                    client,
                    server,
                });
            }
            Err(e) => {
                log::write(&format!("sign-in failed: {} {e}", conn.base_url));
                let unauthorized = matches!(e, Error::Unauthorized);
                if remembered && unauthorized {
                    error = Some("The saved login no longer works. Your connection and setup choices are kept; enter the password again.".into());
                    continue;
                }
                let mut g = Frame::new("Sign-in failed").context(&ctx(&conn));
                g.status(Status::Fail, "Could not sign in.");
                g.blank();
                g.text(&log::redact(&e.to_string()));
                let entries = [
                    item("R", "Retry", ""),
                    item("E", "Edit connection", ""),
                    item("B", "Back", ""),
                ];
                match ui::menu(&g, &entries, "R").as_str() {
                    "R" => {
                        if !unauthorized {
                            typed = Some(password.clone());
                        }
                    }
                    "E" => {
                        if let Some(c) = define_connection(app, Some(&conn)) {
                            conn = c;
                        }
                    }
                    _ => return None,
                }
            }
        }
    }
}

/// Basic credentials over plain http to another host travel unencrypted: ask once.
fn plain_http_allowed(f: &Frame, conn: &mut Connection) -> bool {
    let url = match config::parse_base_url(&conn.base_url) {
        Ok(UrlInput::Full(u)) => u,
        _ => return true,
    };
    if url.is_https() || url.is_localhost() || conn.allow_plain_http {
        return true;
    }
    let mut g = f.clone();
    g.blank();
    g.status(
        Status::Action,
        "This connection uses plain http to another machine.",
    );
    g.detail("The username and password would cross the network unencrypted. Prefer an https address if the web server offers one.");
    let ok = ui::yes_no(&g, "Send them over http anyway", "Cancel", false);
    conn.allow_plain_http = ok;
    ok
}

// ---------------------------------------------------------------- overview

enum Health {
    NotInstalled,
    Partial,
    Healthy(Verification),
}

struct Overview {
    info: Info,
    health: Health,
    frame: Frame,
}

fn session_menu(app: &mut App, s: Session) -> Next {
    if !load_installer(app, &s) {
        return Next::SignIn;
    }
    loop {
        // Re-read the server every time: the previous screen may have installed something.
        let Some(ov) = inspect(app, &s) else {
            return Next::SignIn;
        };
        let conn = app.store.connections[s.idx].clone();
        let f = ov.frame;
        let recommended = match &ov.health {
            Health::NotInstalled => "Set up backend",
            Health::Partial
                if conn
                    .setup
                    .progress
                    .as_deref()
                    .is_some_and(|p| !p.starts_with("done")) =>
            {
                "Resume setup"
            }
            Health::Partial => "Repair installation",
            Health::Healthy(_) => "Webapp settings",
        };
        let entries = [
            item("1", recommended, "recommended"),
            item("2", "Check installation", "read-only"),
            back_key(),
            quit_key(),
        ];
        match ui::menu(&f, &entries, "1").as_str() {
            "1" => {
                let next = match ov.health {
                    Health::Healthy(v) => handoff(app, &s, v),
                    _ => setup(app, &s, &ov.info),
                };
                if let Some(n) = next {
                    return n;
                }
            }
            "2" => check(app, &s),
            "B" => {
                log::write("signed out");
                return Next::SignIn;
            }
            _ => {
                ui::show(&f);
                return Next::Quit;
            }
        }
    }
}

/// Load the installer class into %SYS. False means go back to the connections.
fn load_installer(app: &mut App, s: &Session) -> bool {
    let conn = app.store.connections[s.idx].clone();
    let inst = Installer {
        client: &s.client,
        payload: &app.payload,
    };
    loop {
        let f = Frame::new("Preparing").context(&ctx(&conn));
        match ui::busy(&f, "Loading installer support into %SYS", || {
            inst.bootstrap()
        }) {
            Ok(()) => return true,
            Err(e) => {
                let mut g =
                    Frame::new("Installer support could not be loaded").context(&ctx(&conn));
                g.status(
                    Status::Fail,
                    "The installer class could not be loaded into %SYS.",
                );
                g.blank();
                g.text(&log::redact(&e));
                let entries = [item("R", "Retry", ""), item("B", "Back to connections", "")];
                if ui::menu(&g, &entries, "R") != "R" {
                    return false;
                }
            }
        }
    }
}

/// Read-only overview: connection, platform, interoperability, backend state.
fn inspect(app: &mut App, s: &Session) -> Option<Overview> {
    let conn = app.store.connections[s.idx].clone();
    let inst = Installer {
        client: &s.client,
        payload: &app.payload,
    };
    let ns = conn.namespace();
    let path = conn.app_path();
    loop {
        let wait = Frame::new("Overview").context(&ctx(&conn));
        let r = ui::busy(&wait, "Inspecting the instance", || {
            let info = inst.info()?;
            let exists = info
                .namespaces
                .iter()
                .any(|n| n.name.eq_ignore_ascii_case(&ns));
            let v = if exists {
                Some(inst.verify(&ns, &path))
            } else {
                None
            };
            Ok::<_, String>((info, v))
        });
        let (info, v) = match r {
            Ok(x) => x,
            Err(e) => {
                let mut g = Frame::new("Inspection failed").context(&ctx(&conn));
                g.status(Status::Fail, &log::redact(&e));
                let entries = [item("R", "Retry", ""), item("B", "Back to connections", "")];
                if ui::menu(&g, &entries, "R") != "R" {
                    return None;
                }
                continue;
            }
        };
        if let Some(i) = app.store.connections[s.idx].instance.as_mut() {
            i.platform = info.platform.clone();
        }
        let _ = save(app);

        let mut f = Frame::new("Overview").context(&ctx(&conn));
        f.status(
            Status::Ok,
            &format!("IRIS connection        {}", short_version(&info.version)),
        );
        match info.target() {
            t @ payload::Target::Linux(_) => {
                f.status(Status::Ok, &format!("Server platform        {}", t.label()))
            }
            payload::Target::Unsupported(p) => f.status(
                Status::Fail,
                &format!("Server platform        not supported: {p}"),
            ),
        }
        if s.server.interoperability {
            f.status(Status::Ok, "Interoperability       available");
        } else {
            f.status(
                Status::Fail,
                "Interoperability       not available on this instance",
            );
        }
        let missing = info.privileges.missing();
        if !missing.is_empty() {
            f.status(
                Status::Fail,
                &format!("Privileges             missing {}", missing.join(", ")),
            );
        }
        if let Some(p) = conn
            .setup
            .progress
            .as_deref()
            .and_then(|p| p.strip_prefix("running:"))
        {
            f.status(
                Status::Action,
                &format!("A previous run stopped during \"{p}\"."),
            );
            f.detail("Its outcome is unknown; the state below was inspected fresh.");
        }
        let health = match v {
            None => {
                f.status(
                    Status::Todo,
                    &format!(
                        "OPC UA backend         not installed (namespace {ns} does not exist)"
                    ),
                );
                Health::NotInstalled
            }
            Some(Ok(v)) if v.ok => {
                f.status(
                    Status::Ok,
                    &format!("OPC UA backend         installed in {ns} · {path}"),
                );
                Health::Healthy(v)
            }
            Some(Ok(v)) => {
                f.status(
                    Status::Todo,
                    &format!("OPC UA backend         incomplete in {ns}"),
                );
                for c in v.checks.iter().filter(|c| !c.ok) {
                    f.detail(&c.message);
                }
                Health::Partial
            }
            Some(Err(e)) => {
                f.status(Status::Fail, "OPC UA backend         could not be checked");
                f.detail(&log::redact(&e));
                Health::Partial
            }
        };
        return Some(Overview {
            info,
            health,
            frame: f,
        });
    }
}

fn short_version(v: &str) -> String {
    match v.find(" (Build") {
        Some(b) => {
            let release = v[..b].rsplit(' ').next().unwrap_or("");
            let build = v[b + 1..].split(')').next().unwrap_or("");
            format!("IRIS {release} {build})")
        }
        None => v.chars().take(60).collect(),
    }
}

/// Read-only verification plus the API ping, on its own screen.
fn check(app: &App, s: &Session) {
    let conn = &app.store.connections[s.idx];
    let inst = Installer {
        client: &s.client,
        payload: &app.payload,
    };
    loop {
        let title = format!(
            "Check installation · {} · {}",
            conn.namespace(),
            conn.app_path()
        );
        let wait = Frame::new(&title).context(&ctx(conn));
        let r = ui::busy(&wait, "Verifying", || {
            inst.verify(&conn.namespace(), &conn.app_path()).map(|v| {
                let p = v
                    .check("app")
                    .is_some_and(|c| c.ok)
                    .then(|| inst.ping(&conn.app_path(), v.api_access));
                (v, p)
            })
        });
        let mut f = Frame::new(&title).context(&ctx(conn));
        match r {
            Ok((v, p)) => {
                checks_into(&mut f, &v);
                if let Some(p) = p {
                    ping_into(&mut f, conn, &p);
                }
            }
            Err(e) => f.status(Status::Fail, &log::redact(&e)),
        }
        let entries = [item("R", "Run again", ""), item("B", "Back", "")];
        if ui::menu(&f, &entries, "B") != "R" {
            return;
        }
    }
}

fn checks_into(f: &mut Frame, v: &Verification) {
    for c in &v.checks {
        f.status(if c.ok { Status::Ok } else { Status::Fail }, &c.message);
    }
}

/// Add the API ping result; true when the API answered.
fn ping_into(f: &mut Frame, conn: &Connection, p: &Ping) -> bool {
    let url = format!("{}{}", conn.base_url, conn.app_path());
    match p {
        Ping::Ok => {
            f.status(
                Status::Ok,
                &format!("API responds at {url} (checked from this machine)"),
            );
            true
        }
        Ping::NoAccess => {
            f.status(
                Status::Action,
                &format!("API at {url} refused {}", conn.username),
            );
            f.detail(&format!(
                "The account lacks the {} resource the REST application requires. Grant the {} role (created by this installer) to the IRIS accounts that use the webapp.",
                installer_resource(),
                installer_role(&conn.namespace())
            ));
            false
        }
        Ping::NotRouted => {
            f.status(Status::Action, &format!("API not reachable at {url}"));
            f.detail(&format!(
                "IRIS has the application and this account may use it, but the request returned 404. The web server or gateway in front of IRIS probably does not route {}; add that path to its IRIS application paths.",
                conn.app_path()
            ));
            false
        }
        Ping::Other(e) => {
            f.status(
                Status::Action,
                &format!("API check at {url} failed: {}", log::redact(e)),
            );
            false
        }
    }
}

fn installer_resource() -> &'static str {
    "OPCUA_API"
}

/// Must match IRISConfig.ClientInstaller's ApiRolePrefix.
fn installer_role(ns: &str) -> String {
    format!("OPCUA_API_{}", ns.to_ascii_uppercase())
}

// ---------------------------------------------------------------- setup wizard

/// Choose namespace → preflight → review → apply → handoff. `None` returns to the overview.
fn setup(app: &mut App, s: &Session, info: &Info) -> Option<Next> {
    loop {
        let (ns, path) = choose_namespace(app, s, info)?;
        {
            let c = &mut app.store.connections[s.idx];
            if c.setup.app_path.as_deref() != Some(path.as_str()) {
                c.setup.api_url = None;
            }
            c.setup.namespace = Some(ns.clone());
            c.setup.app_path = Some(path.clone());
        }
        let _ = save(app);
        let conn = app.store.connections[s.idx].clone();
        let inst = Installer {
            client: &s.client,
            payload: &app.payload,
        };
        let plan = loop {
            // Re-read the server each attempt: Retry follows a privilege grant or a manual copy.
            let wait = Frame::new("Checking prerequisites").context(&ctx(&conn));
            let r = ui::busy(
                &wait,
                &format!("Checking namespace {ns}, privileges and native files"),
                || match inst.info() {
                    Ok(fresh) => inst.preflight(&fresh, &ns, &path),
                    Err(e) => Err(vec![installer::Blocker {
                        title: "Inspection failed".into(),
                        body: e,
                    }]),
                },
            );
            match r {
                Ok(plan) => break plan,
                Err(blockers) => {
                    let mut f = Frame::new("Cannot install yet").context(&ctx(&conn));
                    for b in &blockers {
                        f.status(Status::Fail, &b.title);
                        f.detail(&b.body);
                        f.blank();
                        log::write(&format!("preflight: {}: {}", b.title, b.body));
                    }
                    f.dim("Nothing was changed.");
                    let entries = [
                        item("R", "Retry the checks", ""),
                        item("B", "Back", ""),
                        quit_key(),
                    ];
                    match ui::menu(&f, &entries, "R").as_str() {
                        "R" => continue,
                        "Q" => {
                            ui::show(&f);
                            return Some(Next::Quit);
                        }
                        _ => return None,
                    }
                }
            }
        };
        match review(app, s, &plan) {
            Review::Install => {}
            Review::Back => continue,
            Review::Quit => return Some(Next::Quit),
        }
        match apply(app, s, &plan) {
            Applied::Done(v) => return handoff(app, s, v),
            Applied::Retry => continue,
            Applied::Menu => return None,
            Applied::Quit => return Some(Next::Quit),
        }
    }
}

fn namespace_note(state: &str) -> Option<&'static str> {
    match state {
        "owned" => Some("installed by this tool"),
        "backend" => Some("already holds the OPC UA backend"),
        "empty" => Some("empty interoperability namespace"),
        _ => None,
    }
}

/// Two clear groups: create a new namespace, or use one of the existing ones.
fn choose_namespace(app: &App, s: &Session, info: &Info) -> Option<(String, String)> {
    let conn = &app.store.connections[s.idx];
    let inst = Installer {
        client: &s.client,
        payload: &app.payload,
    };
    let mut path = conn.app_path();
    let mut error = None;
    let exists = |n: &str| {
        info.namespaces
            .iter()
            .any(|x| x.name.eq_ignore_ascii_case(n))
    };
    // Suggest the saved choice, else OPCUA; if taken, OPCUA2, OPCUA3, …
    let suggested = {
        let saved = conn.namespace();
        if !exists(&saved) {
            saved
        } else {
            (1..)
                .map(|i| {
                    if i == 1 {
                        "OPCUA".to_string()
                    } else {
                        format!("OPCUA{i}")
                    }
                })
                .find(|n| !exists(n))
                .unwrap()
        }
    };
    loop {
        let mut f = Frame::new("Where should the OPC UA backend go?").context(&ctx(conn));
        f.error = error.take();
        f.text("The backend needs its own interoperability namespace. Create a new one, or use an existing namespace that is empty or already holds the backend.");
        let mut entries = vec![
            section("Create a new namespace"),
            item("1", suggested.clone(), "recommended"),
            item("N", "Another name…", "type a name"),
        ];
        entries.push(gap());
        entries.push(section("Or use an existing namespace"));
        let mut keys: Vec<(String, String)> = vec![("1".into(), suggested.clone())];
        if info.namespaces.is_empty() {
            entries.push(disabled("none", "this instance has no other namespaces"));
        }
        for n in &info.namespaces {
            match namespace_note(&n.state) {
                Some(note) => {
                    let key = (keys.len() + 1).to_string();
                    entries.push(item(key.clone(), n.name.clone(), note));
                    keys.push((key, n.name.clone()));
                }
                None => entries.push(disabled(
                    n.name.clone(),
                    format!("not usable: {}", n.reason),
                )),
            }
        }
        entries.push(gap());
        entries.push(item("A", "Advanced settings", format!("REST path {path}")));
        entries.push(item("B", "Back", ""));
        let default = keys
            .iter()
            .find(|(_, n)| n.eq_ignore_ascii_case(&conn.namespace()))
            .map(|(k, _)| k.clone())
            .unwrap_or_else(|| "1".into());
        let choice = ui::menu(&f, &entries, &default);
        let ns = match choice.as_str() {
            "B" => return None,
            "A" => {
                path = advanced(conn, &path);
                continue;
            }
            "N" => {
                let mut g = Frame::new("New namespace name").context(&ctx(conn));
                g.text("Letters, digits, '-' or '_', starting with a letter. A database with the same name is created in the instance's manager directory.");
                let n = ui::input(&g, "Namespace", "").to_ascii_uppercase();
                if n.is_empty() {
                    continue;
                }
                if !config::valid_namespace(&n) {
                    error = Some(format!("'{n}' is not a valid namespace name."));
                    continue;
                }
                n
            }
            k => match keys.iter().find(|(key, _)| key == k) {
                Some((_, n)) => n.clone(),
                None => continue,
            },
        };
        // Validate at once, so a conflict is explained before the review.
        match ui::busy(&f, &format!("Checking {ns}"), || {
            inst.inspect_namespace(&ns)
        }) {
            Ok(c) if c.namespace.state == "conflict" => {
                error = Some(format!(
                    "Namespace {ns} cannot be used: {}. It was not changed.",
                    c.namespace.reason
                ));
            }
            Ok(_) => return Some((ns, path)),
            Err(e) => error = Some(e),
        }
    }
}

fn advanced(conn: &Connection, current: &str) -> String {
    let mut error = None;
    loop {
        let mut f = Frame::new("Advanced settings").context(&ctx(conn));
        f.error = error.take();
        f.text("REST application path — the web path the webapp calls. Change it only if the default is taken or your web gateway needs another path.");
        let p = ui::input(&f, "REST application path", current);
        if config::valid_app_path(&p) {
            return p;
        }
        error = Some("Use a path such as /csp/opcua/api (letters, digits, '.', '-', '_').".into());
    }
}

enum Review {
    Install,
    Back,
    Quit,
}

fn review(app: &App, s: &Session, plan: &Plan) -> Review {
    let conn = &app.store.connections[s.idx];
    let mut f = Frame::new("Review the changes").context(&ctx(conn));
    let uploads = plan
        .files
        .iter()
        .filter(|f| f.1 == FileAction::Upload)
        .count();
    let native = if uploads > 0 {
        "upload through IRIS"
    } else {
        "reuse (already present)"
    };
    f.heading(&format!("{:<16}{:<24}{}", "What", "Target", "Action"));
    row(
        &mut f,
        "Namespace",
        &plan.namespace,
        if plan.create_namespace {
            "create"
        } else {
            "reuse"
        },
    );
    row(&mut f, "Native adapter", &plan.target.label(), native);
    row(
        &mut f,
        "ObjectScript",
        "OPCUA application",
        "import and compile",
    );
    row(
        &mut f,
        "REST app",
        &plan.app_path,
        if plan.create_app { "create" } else { "reuse" },
    );
    f.blank();
    for (a, action, dest) in &plan.files {
        let what = match action {
            FileAction::Upload => "upload",
            FileAction::Reuse => "identical, reuse",
            FileAction::KeepExisting => "keep the existing copy",
        };
        f.dim(&format!("{:<20} {what} → {dest}", a.name));
    }
    if plan.create_app {
        f.dim(&format!(
            "The REST app requires resource {}; role {} grants it (both created if missing, assigned to nobody).",
            installer_resource(),
            installer_role(&plan.namespace)
        ));
    }
    let entries = [
        item("I", "Install", "apply the changes above"),
        item("B", "Back", "change the namespace"),
        quit_key(),
    ];
    match ui::menu(&f, &entries, "I").as_str() {
        "I" => Review::Install,
        "B" => Review::Back,
        _ => {
            ui::show(&f);
            Review::Quit
        }
    }
}

fn row(f: &mut Frame, what: &str, value: &str, action: &str) {
    f.text(&format!("{what:<16}{value:<24}{action}"));
}

enum Applied {
    Done(Verification),
    Retry,
    Menu,
    Quit,
}

/// Prevents two installations against the same connection from this machine. An OS file
/// lock, so a killed run (Ctrl+C) releases it automatically; the file itself stays.
struct Lock(#[allow(dead_code)] std::fs::File);

impl Lock {
    fn acquire(dir: &Path, name: &str) -> Result<Lock, String> {
        let safe: String = name
            .chars()
            .map(|c| if c.is_ascii_alphanumeric() { c } else { '_' })
            .collect();
        let path = dir.join(format!("{safe}.lock"));
        let file = std::fs::OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(false)
            .open(&path)
            .map_err(|e| format!("Cannot open {}: {e}", path.display()))?;
        match file.try_lock() {
            Ok(()) => Ok(Lock(file)),
            Err(std::fs::TryLockError::WouldBlock) => Err(format!("Another installation for '{name}' is running on this machine. Wait for it to finish.")),
            Err(std::fs::TryLockError::Error(e)) => Err(format!("Cannot lock {}: {e}", path.display())),
        }
    }
}

const STEPS: [&str; 6] = [
    "Native libraries installed",
    "Namespace ready",
    "ObjectScript imported and compiled",
    "Native connector registered and loaded",
    "REST application configured",
    "Backend verified",
];

/// The install screen: every step with its current state.
fn progress_frame(
    conn: &Connection,
    plan: &Plan,
    done: &[(Status, String)],
    running: Option<usize>,
) -> Frame {
    let mut f =
        Frame::new(&format!("Installing into namespace {}", plan.namespace)).context(&ctx(conn));
    for (i, name) in STEPS.iter().enumerate() {
        if let Some((st, note)) = done.get(i) {
            f.status(
                *st,
                &if note.is_empty() {
                    name.to_string()
                } else {
                    format!("{name}  ({note})")
                },
            );
        } else if running == Some(i) {
            f.spinning(name);
        } else {
            f.status(Status::Wait, name);
        }
    }
    f
}

fn apply(app: &mut App, s: &Session, plan: &Plan) -> Applied {
    let conn = app.store.connections[s.idx].clone();
    let _lock = match Lock::acquire(&app.local, &conn.name) {
        Ok(l) => l,
        Err(e) => {
            let mut f = Frame::new("Installation not started").context(&ctx(&conn));
            f.status(Status::Fail, &e);
            ui::menu(&f, &[item("B", "Back", "")], "B");
            return Applied::Menu;
        }
    };
    let mut done: Vec<(Status, String)> = Vec::new();
    let mut verification = None;
    for (i, name) in STEPS.iter().enumerate() {
        set_progress(app, s, &format!("running:{name}"));
        let inst = Installer {
            client: &s.client,
            payload: &app.payload,
        };
        let frame = progress_frame(&conn, plan, &done, Some(i));
        let r: Result<String, String> = ui::busy(&frame, name, || match i {
            0 => {
                let mut notes = Vec::new();
                for (a, action, _) in &plan.files {
                    if *action == FileAction::Upload {
                        notes.push(format!("{} {}", a.name, inst.install_file(a)?));
                    }
                }
                Ok(if notes.is_empty() {
                    "all present".into()
                } else {
                    notes.join(", ")
                })
            }
            1 => inst.create_namespace(&plan.namespace),
            2 => inst
                .import_classes(&plan.namespace)
                .map(|n| format!("{n} documents")),
            3 => inst
                .register_library(&plan.namespace)
                .map(|v| format!("version {v}")),
            4 => inst.create_app(&plan.app_path, &plan.namespace).map(|v| {
                let mut note = v["action"].as_str().unwrap_or("").to_string();
                if let Some(role) = v["roleCreated"].as_str() {
                    note.push_str(&format!("; role {role} created"));
                }
                note
            }),
            _ => inst.verify(&plan.namespace, &plan.app_path).and_then(|v| {
                if v.ok {
                    verification = Some(v);
                    Ok(String::new())
                } else {
                    Err(v
                        .checks
                        .iter()
                        .filter(|c| !c.ok)
                        .map(|c| c.message.clone())
                        .collect::<Vec<_>>()
                        .join("; "))
                }
            }),
        });
        match r {
            Ok(note) => {
                log::write(&format!("step ok: {name} {note}"));
                done.push((Status::Ok, note));
            }
            Err(e) => {
                let e = log::redact(&e);
                log::write(&format!("step failed: {name}: {e}"));
                set_progress(app, s, &format!("failed:{name}"));
                done.push((Status::Fail, String::new()));
                let mut f = progress_frame(&conn, plan, &done, None);
                f.blank();
                f.status(Status::Fail, &format!("{name} — failed"));
                f.detail(&e);
                f.blank();
                f.dim("Completed installation steps have been preserved.");
                if let Some(p) = log::path() {
                    f.dim(&format!("Log: {}", p.display()));
                }
                let entries = [
                    item("R", "Retry", "inspects first, repeats nothing that worked"),
                    item("B", "Back to the overview", ""),
                    quit_key(),
                ];
                return match ui::menu(&f, &entries, "R").as_str() {
                    "R" => Applied::Retry,
                    "B" => Applied::Menu,
                    _ => {
                        ui::show(&f);
                        Applied::Quit
                    }
                };
            }
        }
    }
    set_progress(app, s, "done");
    Applied::Done(verification.expect("verified"))
}

fn set_progress(app: &mut App, s: &Session, p: &str) {
    app.store.connections[s.idx].setup.progress = Some(p.to_string());
    let _ = save(app);
}

// ---------------------------------------------------------------- handoff

fn handoff(app: &mut App, s: &Session, v: Verification) -> Option<Next> {
    let mut v = v;
    let mut ping = {
        let conn = &app.store.connections[s.idx];
        let inst = Installer {
            client: &s.client,
            payload: &app.payload,
        };
        let wait = Frame::new("Checking the API").context(&ctx(conn));
        ui::busy(&wait, "Calling the OPC UA API", || {
            inst.ping(&conn.app_path(), v.api_access)
        })
    };
    if app.store.connections[s.idx].setup.api_url.is_none() {
        let reachable = matches!(ping, Ping::Ok);
        let url = choose_api_url(app, s, reachable);
        app.store.connections[s.idx].setup.api_url = Some(url);
        let _ = save(app);
    }
    let mut notice = None;
    loop {
        let conn = app.store.connections[s.idx].clone();
        let reachable = matches!(ping, Ping::Ok);
        let mut f = Frame::new(if reachable {
            "Backend installed"
        } else {
            "Backend installed; HTTP access not yet verified"
        })
        .context(&ctx(&conn));
        f.notice = notice.take();
        checks_into(&mut f, &v);
        ping_into(&mut f, &conn, &ping);
        f.blank();
        f.heading("In the webapp, open Settings → IRIS API Gateway and enter:");
        f.blank();
        let checked = format!("{}{}", conn.base_url, conn.app_path());
        let api = conn
            .setup
            .api_url
            .clone()
            .unwrap_or_else(|| checked.clone());
        let label = if api == checked && reachable {
            "(checked from this machine)"
        } else {
            "(not checked)"
        };
        f.kv("API Base URL", &format!("{api}  {}", label));
        f.kv(
            "Username",
            &format!(
                "an IRIS account with the {} role",
                installer_role(&conn.namespace())
            ),
        );
        f.blank();
        f.text("Then configure your OPC UA servers in the webapp.");
        let entries = [
            item("1", "Show connection details", ""),
            item("2", "Run checks again", "read-only"),
            item("3", "Change the API Base URL", ""),
            item("4", "Export setup summary", "no passwords"),
            gap(),
            item("B", "Back to the overview", ""),
            quit_key(),
        ];
        match ui::menu(&f, &entries, "B").as_str() {
            "1" => details(app, s),
            "2" => {
                let inst = Installer {
                    client: &s.client,
                    payload: &app.payload,
                };
                let wait = Frame::new("Checking the installation").context(&ctx(&conn));
                let r = ui::busy(&wait, "Verifying", || {
                    inst.verify(&conn.namespace(), &conn.app_path()).map(|nv| {
                        let p = inst.ping(&conn.app_path(), nv.api_access);
                        (nv, p)
                    })
                });
                match r {
                    Ok((nv, p)) if nv.ok => {
                        v = nv;
                        ping = p;
                        notice = Some((Status::Ok, "Checks ran again.".into()));
                    }
                    Ok(_) => return None,
                    Err(e) => notice = Some((Status::Fail, log::redact(&e))),
                }
            }
            "3" => {
                let url = choose_api_url(app, s, reachable);
                app.store.connections[s.idx].setup.api_url = Some(url);
                let _ = save(app);
            }
            "4" => notice = Some(export(app, s)),
            "B" => return None,
            _ => {
                ui::show(&f);
                return Some(Next::Quit);
            }
        }
    }
}

/// The API address the webapp should use: proposed, and changeable.
fn choose_api_url(app: &App, s: &Session, reachable: bool) -> String {
    let conn = &app.store.connections[s.idx];
    let checked = format!("{}{}", conn.base_url, conn.app_path());
    let proposed = conn
        .setup
        .api_url
        .clone()
        .filter(|u| u.ends_with(&conn.app_path()))
        .unwrap_or_else(|| checked.clone());
    let mut f = Frame::new("API address for the webapp").context(&ctx(conn));
    f.text("The webapp needs the address of the OPC UA REST API. This tool proposes the address it used itself:");
    f.blank();
    let label = if proposed == checked && reachable {
        "(checked from this machine)"
    } else {
        "(not checked)"
    };
    f.kv("Proposed", &format!("{proposed}  {label}"));
    f.blank();
    f.dim("Keep it unless browsers reach IRIS through another address, such as a proxy or a different host name.");
    let entries = [
        item("1", "Use the proposed address", ""),
        item("2", "Enter a different address", ""),
    ];
    if ui::menu(&f, &entries, "1") == "1" {
        return proposed;
    }
    let mut error = None;
    loop {
        let mut g = Frame::new("API address for the webapp").context(&ctx(conn));
        g.error = error.take();
        g.text("Enter the full address browsers use for the OPC UA REST API, for example https://iris.example.com/csp/opcua/api.");
        let a = ui::input(&g, "API Base URL", &proposed);
        match config::parse_base_url(&a) {
            Ok(UrlInput::Full(u)) => return u.as_string(),
            _ => error = Some("Enter a full http(s):// URL.".into()),
        }
    }
}

fn summary_lines(c: &Connection) -> Vec<(String, String)> {
    let inst = c.instance.clone().unwrap_or_default();
    vec![
        ("Connection".into(), c.name.clone()),
        ("Base URL".into(), c.base_url.clone()),
        ("Username".into(), c.username.clone()),
        ("Instance GUID".into(), inst.guid),
        ("IRIS version".into(), inst.version),
        ("Server platform".into(), inst.platform),
        ("Namespace".into(), c.namespace()),
        ("REST path".into(), c.app_path()),
        (
            "API Base URL".into(),
            c.setup.api_url.clone().unwrap_or_default(),
        ),
        ("API role".into(), installer_role(&c.namespace())),
        (
            "Setup status".into(),
            c.setup.progress.clone().unwrap_or_else(|| "not run".into()),
        ),
    ]
}

fn details(app: &App, s: &Session) {
    let c = &app.store.connections[s.idx];
    let mut f = Frame::new("Connection details").context(&ctx(c));
    for (k, v) in summary_lines(c) {
        f.kv(&k, &v);
    }
    let saved = if c.password.is_some() {
        format!("saved in {}", app.store.path().display())
    } else {
        "not saved (asked on each launch)".into()
    };
    f.kv("Password", &saved);
    if let Some(p) = log::path() {
        f.kv("Log file", &p.display().to_string());
    }
    ui::menu(&f, &[item("B", "Back", "")], "B");
}

fn export(app: &App, s: &Session) -> (Status, String) {
    let c = &app.store.connections[s.idx];
    let safe: String = c
        .name
        .chars()
        .map(|ch| if ch.is_ascii_alphanumeric() { ch } else { '_' })
        .collect();
    let path = app.local.join(format!("{safe}-summary.txt"));
    let mut text = String::from("IRIS OPC UA backend — setup summary (contains no passwords)\n\n");
    for (k, v) in summary_lines(c) {
        text.push_str(&format!("{k:<16} {v}\n"));
    }
    let r = config::private_file(&path)
        .and_then(|mut f| std::io::Write::write_all(&mut f, log::redact(&text).as_bytes()));
    match r {
        Ok(()) => (Status::Ok, format!("Summary written to {}", path.display())),
        Err(e) => (
            Status::Fail,
            format!("Could not write {}: {e}", path.display()),
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_is_shortened() {
        assert_eq!(
            short_version("IRIS for UNIX (Ubuntu Server LTS for ARM64 Containers) 2025.3 (Build 226U) Thu Nov 13 2025 12:41:34 EST"),
            "IRIS 2025.3 (Build 226U)"
        );
    }

    #[test]
    fn summary_never_contains_the_password() {
        let c = Connection {
            name: "a".into(),
            base_url: "http://h:1".into(),
            username: "u".into(),
            password: Some("topsecret-1".into()),
            allow_plain_http: false,
            instance: None,
            setup: Setup::default(),
        };
        assert!(summary_lines(&c)
            .iter()
            .all(|(_, v)| !v.contains("topsecret-1")));
    }
}

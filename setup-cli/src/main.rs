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
use ui::Status;

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

// ---------------------------------------------------------------- sign-in gate

fn sign_in(app: &mut App) -> Option<Session> {
    loop {
        ui::title(None);
        ui::heading("Choose a connection");
        for (i, c) in app.store.connections.iter().enumerate() {
            let saved = if c.password.is_some() {
                "Saved login"
            } else {
                "Session only"
            };
            ui::item(
                &(i + 1).to_string(),
                &format!("{:<12} {:<40}", c.name, c.base_url),
                saved,
            );
        }
        ui::item("N", "New connection", "");
        ui::item("Q", "Exit", "");
        ui::blank();
        let default = if app.store.connections.is_empty() {
            "N"
        } else {
            "1"
        };
        let choice = ui::choose("Connection", default);
        match choice.as_str() {
            "Q" => return None,
            "N" => {
                if let Some(c) = define_connection(app, None) {
                    if let Some(s) = authenticate(app, c, None) {
                        return Some(s);
                    }
                }
            }
            n => match n.parse::<usize>() {
                Ok(i) if i >= 1 && i <= app.store.connections.len() => {
                    if let Some(s) =
                        authenticate(app, app.store.connections[i - 1].clone(), Some(i - 1))
                    {
                        return Some(s);
                    }
                }
                _ => ui::line("Choose a listed number, N or Q."),
            },
        }
    }
}

/// Ask for name, base URL and username. `prefill` keeps earlier answers when editing.
fn define_connection(app: &App, prefill: Option<&Connection>) -> Option<Connection> {
    ui::blank();
    ui::heading(if prefill.is_some() {
        "Edit connection"
    } else {
        "New connection"
    });
    let name = loop {
        let n = ui::ask(
            "Name of this connection",
            prefill.map(|c| c.name.as_str()).unwrap_or(""),
        );
        if n.is_empty() || n.chars().any(char::is_control) || n.len() > 40 {
            ui::line("Enter a short name (up to 40 characters).");
            continue;
        }
        let clash = app.store.find(&n).is_some_and(|i| {
            prefill.is_none_or(|p| !app.store.connections[i].name.eq_ignore_ascii_case(&p.name))
        });
        if clash {
            ui::line(&format!("A connection named '{n}' already exists."));
            continue;
        }
        break n;
    };
    let url = loop {
        ui::dim("Enter the base URL used to connect to the server, or just its hostname/IP.");
        let raw = ui::ask(
            "Base URL  http(s)://host(:port)/pathPrefix",
            prefill.map(|c| c.base_url.as_str()).unwrap_or(""),
        );
        let parsed = match config::parse_base_url(&raw) {
            Ok(UrlInput::Full(u)) => u,
            Ok(UrlInput::NeedsScheme(host)) => match ask_scheme(&host) {
                Some(u) => u,
                None => continue,
            },
            Err(e) => {
                ui::line(&e);
                continue;
            }
        };
        if confirm_url(&parsed) {
            break parsed.as_string();
        }
    };
    let username = loop {
        let u = ui::ask(
            "Username",
            prefill.map(|c| c.username.as_str()).unwrap_or(""),
        );
        if !u.is_empty() && !u.contains(':') {
            break u;
        }
        ui::line("Enter an IRIS username (it cannot contain ':').");
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

fn ask_scheme(host: &str) -> Option<BaseUrl> {
    ui::line(&format!(
        "'{host}' has no scheme. Which one does the IRIS web server use?"
    ));
    ui::item("1", "https", "");
    ui::item("2", "http", "");
    loop {
        match ui::choose("Scheme", "").as_str() {
            "1" | "HTTPS" => {
                return config::with_scheme("https", host)
                    .map_err(|e| ui::line(&e))
                    .ok()
            }
            "2" | "HTTP" => {
                return config::with_scheme("http", host)
                    .map_err(|e| ui::line(&e))
                    .ok()
            }
            _ => ui::line("Enter 1 or 2."),
        }
    }
}

/// Show the URL exactly as it will be used; without a port, warn and ask.
fn confirm_url(u: &BaseUrl) -> bool {
    ui::blank();
    if u.port.is_none() {
        ui::status(Status::Action, "No port was given.");
        ui::detail(&format!("The URL will be used exactly as written, so the {} default port applies. IRIS's private web server usually listens on another port (often 52773). Nothing is assumed.", u.scheme));
    }
    ui::line(&format!("  URL  {}", u.as_string()));
    ui::blank();
    if u.port.is_none() {
        ui::confirm("Use this URL?", false)
    } else {
        true
    }
}

/// Probe, then authenticate. `idx` is the stored connection being used, if any.
fn authenticate(app: &mut App, mut conn: Connection, idx: Option<usize>) -> Option<Session> {
    let mut typed: Option<String> = None;
    loop {
        let (password, remembered) = match typed.take() {
            Some(p) => (p, false),
            None => match conn.saved_password_for(&conn.base_url, &conn.username) {
                Some(p) => (p.to_string(), true),
                None => {
                    ui::blank();
                    ui::line(&format!(
                        "Sign in to {} ({}) as {}",
                        conn.name, conn.base_url, conn.username
                    ));
                    (ui::password("Password"), false)
                }
            },
        };
        log::secret(&password);
        let client = Client::new(&conn.base_url, &conn.username, &password);
        let result = ui::step(&format!("Connecting to {}", conn.base_url), || {
            client.probe()
        });
        let result = result.and_then(|_| {
            if !plain_http_allowed(&mut conn) {
                return Err(Error::Http(0, "cancelled".into()));
            }
            ui::step("Signing in", || client.authenticate())
        });
        match result {
            Ok(server) => {
                if let Some(inst) = conn
                    .instance
                    .as_ref()
                    .filter(|i| !i.guid.is_empty() && i.guid != server.instance_id)
                {
                    ui::error_block(
                        "This URL now reaches a different IRIS instance",
                        &format!("{} was recorded as instance {}, but it now answers as {}. Nothing was changed.", conn.base_url, inst.guid, server.instance_id),
                    );
                    if !ui::confirm("Treat it as this connection's new target? Saved setup choices and the saved password are cleared", false) {
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
                    let path = app.store.path().display().to_string();
                    conn.password = if ui::confirm(
                        &format!("Remember the password? It is saved in plain text in {path}"),
                        true,
                    ) {
                        Some(password)
                    } else {
                        None
                    };
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
                save(app);
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
            Err(Error::Http(0, _)) => return None,
            Err(e) => {
                log::write(&format!("sign-in failed: {} {e}", conn.base_url));
                let unauthorized = matches!(e, Error::Unauthorized);
                if remembered && unauthorized {
                    ui::line("The saved login no longer works. Your connection and setup choices are kept; enter the password again.");
                    continue;
                }
                ui::error_block("Sign-in failed", &log::redact(&e.to_string()));
                ui::item("R", "Retry", "");
                ui::item("E", "Edit connection", "");
                ui::item("B", "Back", "");
                loop {
                    match ui::choose("Choice", "R").as_str() {
                        "R" => {
                            if !unauthorized {
                                typed = Some(password.clone());
                            }
                            break;
                        }
                        "E" => {
                            if let Some(c) = define_connection(app, Some(&conn)) {
                                conn = c;
                            }
                            break;
                        }
                        "B" => return None,
                        _ => ui::line("Enter R, E or B."),
                    }
                }
            }
        }
    }
}

/// Basic credentials over plain http to another host travel unencrypted: ask once.
fn plain_http_allowed(conn: &mut Connection) -> bool {
    let url = match config::parse_base_url(&conn.base_url) {
        Ok(UrlInput::Full(u)) => u,
        _ => return true,
    };
    if url.is_https() || url.is_localhost() || conn.allow_plain_http {
        return true;
    }
    ui::blank();
    ui::status(
        Status::Action,
        "This connection uses plain http to another machine.",
    );
    ui::detail("The username and password would cross the network unencrypted. Prefer an https address if the web server offers one.");
    let ok = ui::confirm("Send the credentials over http anyway?", false);
    conn.allow_plain_http = ok;
    ok
}

fn save(app: &App) {
    if let Err(e) = app.store.save() {
        ui::status(
            Status::Fail,
            &format!("Could not save {}: {e}", app.store.path().display()),
        );
    }
}

// ---------------------------------------------------------------- after sign-in

enum Health {
    NotInstalled,
    Partial,
    Healthy(Verification),
}

fn session_menu(app: &mut App, s: Session) -> Next {
    let Some(info) = load_installer(app, &s) else {
        return Next::SignIn;
    };
    loop {
        let conn = app.store.connections[s.idx].clone();
        ui::title(Some(&header(&conn)));
        let health = inspect(app, &s, &info);
        ui::blank();
        let recommended = match &health {
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
            Health::Healthy(_) => "Show connection details",
        };
        ui::item("1", recommended, "Recommended");
        ui::item("2", "Check installation", "");
        ui::item("3", "Switch connection / sign out", "");
        if conn.password.is_some() {
            ui::item("4", "Forget saved login", "");
        }
        ui::item("5", "Delete connection", "");
        ui::item("Q", "Exit", "");
        ui::blank();
        match ui::choose("Choice", "1").as_str() {
            "1" => {
                let next = match health {
                    Health::Healthy(v) => handoff(app, &s, &v),
                    _ => setup(app, &s, &info),
                };
                if let Some(n) = next {
                    return n;
                }
            }
            "2" => check(app, &s),
            "3" => {
                log::write("signed out");
                return Next::SignIn;
            }
            "4" if conn.password.is_some() => {
                app.store.connections[s.idx].password = None;
                save(app);
                ui::status(
                    Status::Ok,
                    &format!(
                        "Saved password removed from {}. You stay signed in for this session.",
                        app.store.path().display()
                    ),
                );
            }
            "5" => {
                if ui::confirm(
                    &format!(
                        "Delete the local connection '{}'? Nothing on the IRIS server is changed",
                        conn.name
                    ),
                    false,
                ) {
                    app.store.connections.remove(s.idx);
                    save(app);
                    return Next::SignIn;
                }
            }
            "Q" => return Next::Quit,
            _ => ui::line("Choose one of the listed options."),
        }
    }
}

fn header(c: &Connection) -> String {
    format!("{} · {} · signed in as {}", c.name, c.base_url, c.username)
}

/// Load the installer class into %SYS and read what IRIS reports about itself.
fn load_installer(app: &mut App, s: &Session) -> Option<Info> {
    let inst = Installer {
        client: &s.client,
        payload: &app.payload,
    };
    loop {
        let r = ui::step("Loading installer support into %SYS", || inst.bootstrap())
            .and_then(|_| inst.info());
        match r {
            Ok(info) => {
                if let Some(i) = app.store.connections[s.idx].instance.as_mut() {
                    i.platform = info.platform.clone();
                }
                save(app);
                return Some(info);
            }
            Err(e) => {
                ui::error_block("Installer support could not be loaded", &log::redact(&e));
                ui::item("R", "Retry", "");
                ui::item("B", "Back to connections", "");
                if ui::choose("Choice", "R") != "R" {
                    return None;
                }
            }
        }
    }
}

/// Read-only overview: connection, platform, interoperability, backend state.
fn inspect(app: &App, s: &Session, info: &Info) -> Health {
    let conn = &app.store.connections[s.idx];
    let inst = Installer {
        client: &s.client,
        payload: &app.payload,
    };
    ui::status(
        Status::Ok,
        &format!("IRIS connection  {}", short_version(&info.version)),
    );
    let target = info.target();
    match &target {
        payload::Target::Linux(_) => ui::status(
            Status::Ok,
            &format!("Server platform and native artifacts  {}", target.label()),
        ),
        payload::Target::Unsupported(p) => {
            ui::status(Status::Fail, &format!("Server platform not supported: {p}"))
        }
    }
    if s.server.interoperability {
        ui::status(Status::Ok, "Interoperability available");
    } else {
        ui::status(
            Status::Fail,
            "Interoperability is not available on this instance",
        );
    }
    let missing = info.privileges.missing();
    if !missing.is_empty() {
        ui::status(
            Status::Fail,
            &format!("Missing privileges: {}", missing.join(", ")),
        );
    }
    if let Some(p) = conn
        .setup
        .progress
        .as_deref()
        .and_then(|p| p.strip_prefix("running:"))
    {
        ui::status(Status::Action, &format!("A previous run stopped during \"{p}\"; its outcome is unknown. The state below was inspected fresh."));
    }
    let ns = conn.namespace();
    let exists = info
        .namespaces
        .iter()
        .any(|n| n.name.eq_ignore_ascii_case(&ns));
    if !exists {
        ui::status(Status::Todo, "OPC UA backend installation");
        return Health::NotInstalled;
    }
    let sp = ui::Spinner::start("Checking the installation");
    let v = inst.verify(&ns, &conn.app_path());
    sp.stop();
    match v {
        Ok(v) if v.ok => {
            ui::status(Status::Ok, &format!("OPC UA backend installed in {ns}"));
            Health::Healthy(v)
        }
        Ok(v) => {
            ui::status(
                Status::Todo,
                &format!("OPC UA backend in {ns} is incomplete"),
            );
            for c in v.checks.iter().filter(|c| !c.ok) {
                ui::detail(&c.message);
            }
            Health::Partial
        }
        Err(e) => {
            ui::status(Status::Fail, "Installation check failed");
            ui::detail(&log::redact(&e));
            Health::NotInstalled
        }
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

/// Read-only verification plus the API ping.
fn check(app: &App, s: &Session) {
    let conn = &app.store.connections[s.idx];
    let inst = Installer {
        client: &s.client,
        payload: &app.payload,
    };
    ui::blank();
    ui::heading(&format!(
        "Checking {} · namespace {} · {}",
        conn.name,
        conn.namespace(),
        conn.app_path()
    ));
    let sp = ui::Spinner::start("Verifying");
    let v = inst.verify(&conn.namespace(), &conn.app_path());
    sp.stop();
    match v {
        Ok(v) => {
            print_checks(&v);
            if v.check("app").is_some_and(|c| c.ok) {
                print_ping(&inst, conn, &v);
            }
        }
        Err(e) => ui::status(Status::Fail, &log::redact(&e)),
    }
    ui::blank();
    ui::ask("Press Enter to continue", "");
}

fn print_checks(v: &Verification) {
    for c in &v.checks {
        ui::status(if c.ok { Status::Ok } else { Status::Fail }, &c.message);
    }
}

fn print_ping(inst: &Installer, conn: &Connection, v: &Verification) -> bool {
    let url = format!("{}{}", conn.base_url, conn.app_path());
    let sp = ui::Spinner::start("Calling the OPC UA API");
    let p = inst.ping(&conn.app_path(), v.api_access);
    sp.stop();
    match p {
        Ping::Ok => {
            ui::status(
                Status::Ok,
                &format!("API responds at {url} (checked from this machine)"),
            );
            true
        }
        Ping::NoAccess => {
            ui::status(
                Status::Action,
                &format!("API at {url} refused {}", conn.username),
            );
            ui::detail(&format!("The account lacks the {} resource the REST application requires. Grant the {} role (created by this installer) to the accounts that use the webapp.", installer_resource(), installer_role(&conn.namespace())));
            false
        }
        Ping::NotRouted => {
            ui::status(Status::Action, &format!("API not reachable at {url}"));
            ui::detail(&format!("IRIS has the application and this account may use it, but the request returned 404. The web server or gateway in front of IRIS probably does not route {}; add that path to its IRIS application paths.", conn.app_path()));
            false
        }
        Ping::Other(e) => {
            ui::status(
                Status::Action,
                &format!("API check at {url} failed: {}", log::redact(&e)),
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

/// Choose namespace → preflight → review → apply → handoff. `None` returns to the menu.
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
        save(app);
        let inst = Installer {
            client: &s.client,
            payload: &app.payload,
        };
        let plan = loop {
            // Re-read the server each attempt: Retry follows a privilege grant or a manual copy.
            let sp = ui::Spinner::start("Checking prerequisites");
            let r = match inst.info() {
                Ok(fresh) => inst.preflight(&fresh, &ns, &path),
                Err(e) => Err(vec![installer::Blocker {
                    title: "Inspection failed".into(),
                    body: e,
                }]),
            };
            sp.stop();
            match r {
                Ok(plan) => break plan,
                Err(blockers) => {
                    ui::blank();
                    for b in &blockers {
                        ui::status(Status::Fail, &b.title);
                        for l in b.body.lines() {
                            ui::detail(l);
                        }
                        log::write(&format!("preflight: {}: {}", b.title, b.body));
                    }
                    ui::blank();
                    ui::line("Nothing was changed.");
                    ui::item("R", "Retry the checks", "");
                    ui::item("B", "Back", "");
                    ui::item("Q", "Save and exit", "");
                    match ui::choose("Choice", "R").as_str() {
                        "R" => continue,
                        "Q" => return Some(Next::Quit),
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
            Applied::Done(v) => return handoff(app, s, &v),
            Applied::Retry => continue,
            Applied::Menu => return None,
            Applied::Quit => return Some(Next::Quit),
        }
    }
}

fn choose_namespace(app: &App, s: &Session, info: &Info) -> Option<(String, String)> {
    let conn = &app.store.connections[s.idx];
    let inst = Installer {
        client: &s.client,
        payload: &app.payload,
    };
    let mut path = conn.app_path();
    let preferred = conn.namespace();
    loop {
        ui::blank();
        ui::heading(&format!("Choose a dedicated namespace on {}", conn.name));
        let mut options: Vec<(String, String)> = Vec::new();
        let describe = |name: &str| -> String {
            match info
                .namespaces
                .iter()
                .find(|n| n.name.eq_ignore_ascii_case(name))
            {
                None => "Create (recommended)".into(),
                Some(n) => match n.state.as_str() {
                    "owned" => "Reuse — installed by this tool".into(),
                    "backend" => "Reuse — existing OPC UA backend".into(),
                    "empty" => "Reuse — empty interoperability namespace".into(),
                    _ => format!("In use: {}", n.reason),
                },
            }
        };
        options.push((preferred.clone(), describe(&preferred)));
        for n in &info.namespaces {
            if (n.state == "owned" || n.state == "backend")
                && !n.name.eq_ignore_ascii_case(&preferred)
            {
                options.push((n.name.clone(), describe(&n.name)));
            }
        }
        for (i, (name, note)) in options.iter().enumerate() {
            ui::item(&(i + 1).to_string(), name, note);
        }
        ui::item("N", "Enter another name", "");
        ui::item("A", "Advanced settings", &format!("REST path {path}"));
        ui::item("B", "Back", "");
        ui::blank();
        let choice = ui::choose("Namespace", "1");
        let ns = match choice.as_str() {
            "B" => return None,
            "A" => {
                path = advanced(&path);
                continue;
            }
            "N" => {
                let n = ui::ask("Namespace name", "").to_ascii_uppercase();
                if !config::valid_namespace(&n) {
                    ui::line("Use letters, digits, '-' or '_', starting with a letter.");
                    continue;
                }
                n
            }
            c => match c.parse::<usize>() {
                Ok(i) if i >= 1 && i <= options.len() => options[i - 1].0.clone(),
                _ => {
                    ui::line("Choose a listed option.");
                    continue;
                }
            },
        };
        // Validate at once, so a conflict is explained before the review.
        match inst.inspect_namespace(&ns) {
            Ok(c) if c.namespace.state == "conflict" => {
                ui::status(
                    Status::Fail,
                    &format!("Namespace {ns} cannot be used: {}", c.namespace.reason),
                );
                ui::detail("It was not changed. Choose a separate namespace for OPC UA.");
            }
            Ok(_) => return Some((ns, path)),
            Err(e) => ui::status(Status::Fail, &e),
        }
    }
}

fn advanced(current: &str) -> String {
    ui::blank();
    ui::heading("Advanced settings");
    loop {
        let p = ui::ask("REST application path", current);
        if config::valid_app_path(&p) {
            return p;
        }
        ui::line("Use a path such as /csp/opcua/api (letters, digits, '.', '-', '_').");
    }
}

enum Review {
    Install,
    Back,
    Quit,
}

fn review(app: &App, s: &Session, plan: &Plan) -> Review {
    let conn = &app.store.connections[s.idx];
    ui::blank();
    ui::heading(&format!(
        "Ready to install into {} ({})",
        conn.name, conn.base_url
    ));
    let uploads = plan
        .files
        .iter()
        .filter(|f| f.1 == FileAction::Upload)
        .count();
    let native = if uploads > 0 {
        "Upload through IRIS"
    } else {
        "Reuse (already present)"
    };
    row(
        "Namespace",
        &plan.namespace,
        if plan.create_namespace {
            "Create"
        } else {
            "Reuse"
        },
    );
    row("Native adapter", &plan.target.label(), native);
    row("ObjectScript", "OPCUA application", "Import and compile");
    row(
        "REST app",
        &plan.app_path,
        if plan.create_app { "Create" } else { "Reuse" },
    );
    for (a, action, dest) in &plan.files {
        let what = match action {
            FileAction::Upload => "upload",
            FileAction::Reuse => "identical, reuse",
            FileAction::KeepExisting => "keep the existing copy (never replaced)",
        };
        ui::dim(&format!("  {:<20} {what}  → {dest}", a.name));
    }
    if plan.create_app {
        ui::dim(&format!(
            "  The REST app requires resource {}; role {} grants it (both created if missing).",
            installer_resource(),
            installer_role(&plan.namespace)
        ));
    }
    ui::blank();
    loop {
        match ui::choose(
            "Enter Install to continue, B to go back, or Q to save and exit",
            "",
        )
        .as_str()
        {
            "INSTALL" => return Review::Install,
            "B" => return Review::Back,
            "Q" => return Review::Quit,
            _ => ui::line("Type Install, B or Q."),
        }
    }
}

fn row(what: &str, value: &str, action: &str) {
    ui::line(&format!("{what:<15} {value:<22} {action}"));
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

fn apply(app: &mut App, s: &Session, plan: &Plan) -> Applied {
    let _lock = match Lock::acquire(&app.local, &app.store.connections[s.idx].name) {
        Ok(l) => l,
        Err(e) => {
            ui::error_block("Installation not started", &e);
            return Applied::Menu;
        }
    };
    let conn = app.store.connections[s.idx].clone();
    ui::blank();
    ui::heading(&format!(
        "Installing into {} ({}) · namespace {}",
        conn.name, conn.base_url, plan.namespace
    ));
    let steps = [
        "Native libraries installed",
        "Namespace ready",
        "ObjectScript imported and compiled",
        "Native connector registered and loaded",
        "REST application configured",
        "Backend verified",
    ];
    let mut verification = None;
    for (i, name) in steps.iter().enumerate() {
        set_progress(app, s, &format!("running:{name}"));
        let inst = Installer {
            client: &s.client,
            payload: &app.payload,
        };
        let sp = ui::Spinner::start(name);
        let r: Result<String, String> = match i {
            0 => {
                let mut notes = Vec::new();
                let mut res = Ok(());
                for (a, action, _) in &plan.files {
                    if *action == FileAction::Upload {
                        match inst.install_file(a) {
                            Ok(what) => notes.push(format!("{} {what}", a.name)),
                            Err(e) => {
                                res = Err(e);
                                break;
                            }
                        }
                    }
                }
                res.map(|_| {
                    if notes.is_empty() {
                        "all present".into()
                    } else {
                        notes.join(", ")
                    }
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
        };
        sp.stop();
        match r {
            Ok(note) => {
                ui::status(
                    Status::Ok,
                    &if note.is_empty() {
                        name.to_string()
                    } else {
                        format!("{name}  ({note})")
                    },
                );
                log::write(&format!("step ok: {name} {note}"));
            }
            Err(e) => {
                let e = log::redact(&e);
                log::write(&format!("step failed: {name}: {e}"));
                set_progress(app, s, &format!("failed:{name}"));
                ui::status(Status::Fail, name);
                for rest in &steps[i + 1..] {
                    ui::status(Status::Wait, rest);
                }
                ui::error_block(&format!("{name} — failed"), &e);
                ui::line("Completed installation steps have been preserved.");
                if let Some(p) = log::path() {
                    ui::dim(&format!("Log: {}", p.display()));
                }
                ui::blank();
                ui::item("R", "Retry", "");
                ui::item("B", "Back to the menu", "");
                ui::item("Q", "Save and exit", "");
                return match ui::choose("Choice", "R").as_str() {
                    "R" => Applied::Retry,
                    "Q" => Applied::Quit,
                    _ => Applied::Menu,
                };
            }
        }
    }
    set_progress(app, s, "done");
    Applied::Done(verification.expect("verified"))
}

fn set_progress(app: &mut App, s: &Session, p: &str) {
    app.store.connections[s.idx].setup.progress = Some(p.to_string());
    save(app);
}

// ---------------------------------------------------------------- handoff

fn handoff(app: &mut App, s: &Session, v: &Verification) -> Option<Next> {
    let mut v = v.clone();
    loop {
        let conn = app.store.connections[s.idx].clone();
        let inst = Installer {
            client: &s.client,
            payload: &app.payload,
        };
        ui::blank();
        ui::dim(&header(&conn));
        ui::blank();
        let version = v
            .check("library")
            .and_then(|c| c.value.clone())
            .map(|x| x.as_str().map(String::from).unwrap_or(x.to_string()))
            .unwrap_or_default();
        ui::status(Status::Ok, "Classes compiled");
        ui::status(
            Status::Ok,
            &format!("Native connector loaded  (version {version})"),
        );
        ui::status(
            Status::Ok,
            &format!(
                "REST application configured  ({} in {})",
                conn.app_path(),
                conn.namespace()
            ),
        );
        let reachable = print_ping(&inst, &conn, &v);
        ui::blank();
        ui::heading(if reachable {
            "Backend installed"
        } else {
            "Backend installed; HTTP access not yet verified"
        });

        let checked = format!("{}{}", conn.base_url, conn.app_path());
        let proposed = conn
            .setup
            .api_url
            .clone()
            .filter(|u| u.ends_with(&conn.app_path()))
            .unwrap_or_else(|| checked.clone());
        ui::dim("The browser may reach IRIS through a different address than this machine did.");
        let api = loop {
            let a = ui::ask("API Base URL for the webapp", &proposed);
            match config::parse_base_url(&a) {
                Ok(UrlInput::Full(u)) => break u.as_string(),
                _ => ui::line("Enter a full http(s):// URL."),
            }
        };
        app.store.connections[s.idx].setup.api_url = Some(api.clone());
        save(app);
        let label = if api == checked && reachable {
            "(checked from this machine)"
        } else {
            "(not checked)"
        };
        ui::blank();
        ui::line("In the webapp, open Settings → IRIS API Gateway:");
        ui::blank();
        ui::line(&format!("  API Base URL   {api}  {label}"));
        ui::line(&format!(
            "  Username       Use your authorized IRIS API account (it needs the {} role)",
            installer_role(&conn.namespace())
        ));
        ui::blank();
        ui::line("Then configure your OPC UA servers in the webapp.");
        ui::blank();
        loop {
            ui::item("1", "Show connection details", "");
            ui::item("2", "Run checks again", "");
            ui::item("3", "Export setup summary (no passwords)", "");
            ui::item("B", "Back to the menu", "");
            ui::item("Q", "Exit", "");
            ui::blank();
            match ui::choose("Choice", "Q").as_str() {
                "1" => details(app, s),
                "2" => {
                    let sp = ui::Spinner::start("Verifying");
                    let r = inst.verify(&conn.namespace(), &conn.app_path());
                    sp.stop();
                    match r {
                        Ok(nv) => {
                            print_checks(&nv);
                            if !nv.ok {
                                return None;
                            }
                            v = nv;
                        }
                        Err(e) => ui::status(Status::Fail, &log::redact(&e)),
                    }
                    break;
                }
                "3" => export(app, s),
                "B" => return None,
                "Q" => return Some(Next::Quit),
                _ => ui::line("Choose one of the listed options."),
            }
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
    ui::blank();
    for (k, v) in summary_lines(c) {
        ui::line(&format!("  {k:<16} {v}"));
    }
    let saved = if c.password.is_some() {
        format!("saved in {}", app.store.path().display())
    } else {
        "session only".into()
    };
    ui::line(&format!("  {:<16} {saved}", "Password"));
    if let Some(p) = log::path() {
        ui::line(&format!("  {:<16} {}", "Log file", p.display()));
    }
    ui::blank();
}

fn export(app: &App, s: &Session) {
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
        Ok(()) => ui::status(
            Status::Ok,
            &format!("Summary written to {}", path.display()),
        ),
        Err(e) => ui::status(
            Status::Fail,
            &format!("Could not write {}: {e}", path.display()),
        ),
    }
    ui::blank();
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

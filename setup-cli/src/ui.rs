//! Prompts, status lines, colors and the spinner. Output stays in scrollback: no
//! screen clearing and no cursor movement except the spinner's own line on a TTY.

use console::{style, Key, Term};
use std::io::{self, Write};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Status {
    Ok,
    Fail,
    Action,
    Todo,
    Wait,
}

impl Status {
    fn label(self) -> &'static str {
        match self {
            Status::Ok => "OK",
            Status::Fail => "FAIL",
            Status::Action => "ACTION",
            Status::Todo => "TODO",
            Status::Wait => "WAIT",
        }
    }
}

/// Enable colors only for an interactive terminal that asks for them.
pub fn init() {
    let no_color = std::env::var_os("NO_COLOR").is_some_and(|v| !v.is_empty())
        || std::env::var("TERM").is_ok_and(|t| t == "dumb");
    let tty = Term::stdout().is_term();
    console::set_colors_enabled(tty && !no_color);
    console::set_colors_enabled_stderr(Term::stderr().is_term() && !no_color);
}

pub fn stdin_is_terminal() -> bool {
    use std::io::IsTerminal;
    io::stdin().is_terminal()
}

pub fn title(sub: Option<&str>) {
    println!();
    println!("{}", style("IRIS OPC UA Setup").cyan().bold());
    if let Some(s) = sub {
        println!("{}", style(s).dim());
    }
    println!();
}

pub fn heading(text: &str) {
    println!("{}", style(text).bold());
    println!();
}

pub fn line(text: &str) {
    println!("{text}");
}

pub fn blank() {
    println!();
}

pub fn dim(text: &str) {
    println!("{}", style(text).dim());
}

pub fn status(s: Status, text: &str) {
    let label = format!("{:<7}", s.label());
    let label = match s {
        Status::Ok => style(label).green(),
        Status::Fail => style(label).red().bold(),
        Status::Action => style(label).yellow(),
        Status::Todo => style(label).yellow(),
        Status::Wait => style(label).dim(),
    };
    println!("  {label}{text}");
}

/// An indented explanation under a status line.
/// Lines starting with two spaces are preformatted (paths, hashes) and never wrapped.
pub fn detail(text: &str) {
    if text.starts_with("  ") {
        println!("        {text}");
        return;
    }
    for l in wrap(text, width().saturating_sub(10).max(40)) {
        println!("        {l}");
    }
}

pub fn error_block(headline: &str, body: &str) {
    println!();
    status(Status::Fail, headline);
    println!();
    for l in wrap(body, width().saturating_sub(2).max(40)) {
        println!("{l}");
    }
    println!();
}

/// A numbered or lettered menu item: `  1  Set up backend     Recommended`.
pub fn item(key: &str, label: &str, note: &str) {
    if note.is_empty() {
        println!("  {}  {label}", style(format!("{key:>2}")).cyan());
    } else {
        println!(
            "  {}  {label:<30}  {}",
            style(format!("{key:>2}")).cyan(),
            style(note).dim()
        );
    }
}

fn width() -> usize {
    let (_, cols) = Term::stdout().size();
    (cols as usize).clamp(40, 100)
}

fn wrap(text: &str, max: usize) -> Vec<String> {
    let mut out = Vec::new();
    for para in text.split('\n') {
        let mut cur = String::new();
        for word in para.split(' ') {
            if !cur.is_empty() && cur.chars().count() + 1 + word.chars().count() > max {
                out.push(std::mem::take(&mut cur));
            }
            if !cur.is_empty() {
                cur.push(' ');
            }
            cur.push_str(word);
        }
        out.push(cur);
    }
    out
}

/// Read a line; Enter returns `default`. End of input ends the program cleanly.
pub fn ask(label: &str, default: &str) -> String {
    if default.is_empty() {
        print!("{label}: ");
    } else {
        print!("{label} [{default}]: ");
    }
    let _ = io::stdout().flush();
    let mut s = String::new();
    match io::stdin().read_line(&mut s) {
        Ok(0) | Err(_) => {
            println!();
            quit("Input closed.");
        }
        Ok(_) => {}
    }
    let s = s.trim().to_string();
    if s.is_empty() {
        default.to_string()
    } else {
        s
    }
}

/// A single upper-cased choice.
pub fn choose(label: &str, default: &str) -> String {
    ask(label, default).to_ascii_uppercase()
}

pub fn confirm(label: &str, default_yes: bool) -> bool {
    loop {
        let a = ask(
            &format!("{label} (y/n)"),
            if default_yes { "Y" } else { "N" },
        )
        .to_ascii_lowercase();
        match a.as_str() {
            "y" | "yes" => return true,
            "n" | "no" => return false,
            _ => line("Please answer y or n."),
        }
    }
}

/// Masked password entry. Reads key by key in raw mode so Ctrl+C restores the
/// terminal before exiting, instead of leaving echo switched off.
pub fn password(label: &str) -> String {
    print!("{label}: ");
    let _ = io::stdout().flush();
    let term = Term::stdout();
    let mut pw = String::new();
    loop {
        match term.read_key_raw() {
            Ok(Key::Enter) => break,
            Ok(Key::Backspace) => {
                pw.pop();
            }
            Ok(Key::Char(c)) if !c.is_control() => pw.push(c),
            Ok(Key::CtrlC) | Err(_) => {
                println!();
                quit("Cancelled.");
            }
            Ok(_) => {}
        }
    }
    println!();
    pw
}

pub fn quit(msg: &str) -> ! {
    dim(msg);
    std::process::exit(130);
}

/// An ASCII spinner on stderr, only when stderr is a terminal. Stop it before any prompt.
pub struct Spinner {
    stop: Arc<AtomicBool>,
    handle: Option<JoinHandle<()>>,
}

impl Spinner {
    pub fn start(text: &str) -> Spinner {
        let stop = Arc::new(AtomicBool::new(false));
        let term = Term::stderr();
        if !term.is_term() {
            return Spinner { stop, handle: None };
        }
        let flag = stop.clone();
        let text = text.to_string();
        let handle = std::thread::spawn(move || {
            let frames = ['|', '/', '-', '\\'];
            let started = Instant::now();
            let mut i = 0;
            while !flag.load(Ordering::Relaxed) {
                let secs = started.elapsed().as_secs();
                let _ = term.write_str(&format!(
                    "\r  {}   {} {}",
                    style(frames[i % 4]).cyan(),
                    text,
                    style(format!("{secs}s")).dim()
                ));
                i += 1;
                std::thread::sleep(Duration::from_millis(120));
            }
            let _ = term.clear_line();
        });
        Spinner {
            stop,
            handle: Some(handle),
        }
    }

    pub fn stop(mut self) {
        self.finish();
    }

    fn finish(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
        if let Some(h) = self.handle.take() {
            let _ = h.join();
        }
    }
}

impl Drop for Spinner {
    fn drop(&mut self) {
        self.finish();
    }
}

/// Run `f` with a spinner, then leave one final status line.
pub fn step<T, E>(text: &str, f: impl FnOnce() -> Result<T, E>) -> Result<T, E> {
    let sp = Spinner::start(text);
    let r = f();
    sp.stop();
    status(if r.is_ok() { Status::Ok } else { Status::Fail }, text);
    r
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wrapping_keeps_words_whole() {
        let w = wrap("aaa bbb ccc ddd", 7);
        assert_eq!(w, vec!["aaa bbb", "ccc ddd"]);
        assert_eq!(wrap("one\ntwo", 80), vec!["one", "two"]);
    }
}

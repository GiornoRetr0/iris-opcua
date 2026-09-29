//! Screens, menus, inputs and the spinner.
//!
//! On an interactive terminal every step is its own full-window screen: it is
//! redrawn from the top, menus move with the arrow keys, and the last screen stays
//! visible after exit. With redirected output or `TERM=dumb` the same screens are
//! printed one after another and menus read a typed choice instead.

use console::{measure_text_width, style, Key, Term};
use std::io::{self, Write};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

static FULLSCREEN: AtomicBool = AtomicBool::new(false);
static UNICODE: AtomicBool = AtomicBool::new(false);

/// Marks a frame line that the spinner animates while work runs.
const SPIN: char = '\u{1}';

#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Status {
    Ok,
    Fail,
    Action,
    Todo,
    Wait,
}

impl Status {
    fn label(self) -> String {
        let text = match self {
            Status::Ok => "OK",
            Status::Fail => "FAIL",
            Status::Action => "ACTION",
            Status::Todo => "TODO",
            Status::Wait => "WAIT",
        };
        let padded = format!("{text:<7}");
        match self {
            Status::Ok => style(padded).green().to_string(),
            Status::Fail => style(padded).red().bold().to_string(),
            Status::Action | Status::Todo => style(padded).yellow().to_string(),
            Status::Wait => style(padded).dim().to_string(),
        }
    }
}

pub fn init() {
    let dumb = std::env::var("TERM").is_ok_and(|t| t == "dumb");
    let no_color = std::env::var_os("NO_COLOR").is_some_and(|v| !v.is_empty()) || dumb;
    let out = Term::stdout().is_term();
    console::set_colors_enabled(out && !no_color);
    console::set_colors_enabled_stderr(Term::stderr().is_term() && !no_color);
    FULLSCREEN.store(out && stdin_is_terminal() && !dumb, Ordering::Relaxed);
    let lang = ["LC_ALL", "LC_CTYPE", "LANG"]
        .iter()
        .filter_map(|v| std::env::var(v).ok())
        .next()
        .unwrap_or_default();
    UNICODE.store(
        cfg!(target_os = "macos") || lang.to_ascii_uppercase().contains("UTF-8"),
        Ordering::Relaxed,
    );
}

pub fn fullscreen() -> bool {
    FULLSCREEN.load(Ordering::Relaxed)
}

fn unicode() -> bool {
    UNICODE.load(Ordering::Relaxed)
}

pub fn stdin_is_terminal() -> bool {
    use std::io::IsTerminal;
    io::stdin().is_terminal()
}

fn cols() -> usize {
    let (_, c) = Term::stdout().size();
    (c as usize).max(40)
}

/// Text width available inside the screen margin.
fn text_width() -> usize {
    cols().saturating_sub(4).min(110)
}

// ---------------------------------------------------------------- frames

/// One screen: context line, title, body, an optional notice and error.
#[derive(Clone, Default)]
pub struct Frame {
    context: String,
    title: String,
    lines: Vec<String>,
    pub notice: Option<(Status, String)>,
    pub error: Option<String>,
}

impl Frame {
    pub fn new(title: &str) -> Frame {
        Frame {
            title: title.to_string(),
            ..Default::default()
        }
    }

    pub fn context(mut self, ctx: &str) -> Frame {
        self.context = ctx.to_string();
        self
    }

    pub fn blank(&mut self) {
        self.lines.push(String::new());
    }

    /// A wrapped paragraph.
    pub fn text(&mut self, s: &str) {
        self.lines.extend(wrap(s, text_width()));
    }

    pub fn dim(&mut self, s: &str) {
        self.lines.extend(
            wrap(s, text_width())
                .into_iter()
                .map(|l| style(l).dim().to_string()),
        );
    }

    pub fn heading(&mut self, s: &str) {
        self.lines.push(style(s).bold().to_string());
    }

    pub fn status(&mut self, st: Status, text: &str) {
        self.lines.push(format!("{}{text}", st.label()));
    }

    /// Indented explanation under a status line. Lines starting with two spaces
    /// (paths, hashes) are kept exactly as written.
    pub fn detail(&mut self, text: &str) {
        for part in text.lines() {
            if part.starts_with("  ") {
                self.lines.push(format!("       {part}"));
            } else {
                self.lines.extend(
                    wrap(part, text_width().saturating_sub(7))
                        .into_iter()
                        .map(|l| format!("       {l}")),
                );
            }
        }
    }

    pub fn kv(&mut self, key: &str, value: &str) {
        self.lines
            .push(format!("{} {value}", style(format!("{key:<16}")).dim()));
    }

    /// A line the spinner animates while `busy` runs.
    pub fn spinning(&mut self, text: &str) {
        self.lines.push(format!("{SPIN}{text}"));
    }

    fn header(&self) -> Vec<String> {
        let rule = if unicode() && fullscreen() {
            "─"
        } else {
            "-"
        };
        let mut top = style("IRIS OPC UA Setup").cyan().bold().to_string();
        if !self.context.is_empty() {
            top.push_str(&format!("   {}", style(&self.context).dim()));
        }
        vec![
            String::new(),
            top,
            style(rule.repeat(text_width().min(72))).dim().to_string(),
            String::new(),
            style(&self.title).bold().to_string(),
            String::new(),
        ]
    }
}

fn spin_frame(i: usize) -> char {
    ['|', '/', '-', '\\'][i % 4]
}

/// Build every line of a screen. `spin` animates `SPIN` lines.
fn compose(
    frame: &Frame,
    extra: &[String],
    footer: &str,
    spin: Option<(usize, u64)>,
) -> Vec<String> {
    let mut out = frame.header();
    for l in &frame.lines {
        if let Some(text) = l.strip_prefix(SPIN) {
            let glyph = spin.map(|(i, _)| spin_frame(i)).unwrap_or('-');
            let secs = spin
                .map(|(_, s)| format!(" {}", style(format!("{s}s")).dim()))
                .unwrap_or_default();
            out.push(format!(
                "{}{text}{secs}",
                style(format!("{glyph:<7}")).cyan()
            ));
        } else {
            out.push(l.clone());
        }
    }
    if let Some((st, msg)) = &frame.notice {
        out.push(String::new());
        out.push(format!("{}{msg}", st.label()));
    }
    if !extra.is_empty() {
        out.push(String::new());
        out.extend(extra.iter().cloned());
    }
    if let Some(e) = &frame.error {
        out.push(String::new());
        out.extend(
            wrap(e, text_width())
                .into_iter()
                .map(|l| style(l).red().to_string()),
        );
    }
    if !footer.is_empty() && fullscreen() {
        out.push(String::new());
        out.push(style(footer).dim().to_string());
    }
    out
}

/// Draw a screen. Full-screen: from the top of the window, replacing what was there.
fn draw(lines: &[String]) {
    let mut s = String::new();
    if fullscreen() {
        s.push_str("\x1b[H");
        let max = cols();
        for l in lines {
            if measure_text_width(l) + 3 > max {
                s.push_str("  ");
                s.push_str(&console::truncate_str(l, max - 3, "…"));
            } else {
                s.push_str("  ");
                s.push_str(l);
            }
            s.push_str("\x1b[K\r\n");
        }
        s.push_str("\x1b[J");
    } else {
        s.push('\n');
        for l in lines.iter().skip(1) {
            s.push_str("  ");
            s.push_str(l);
            s.push('\n');
        }
    }
    let mut out = io::stdout();
    let _ = out.write_all(s.as_bytes());
    let _ = out.flush();
}

/// Show a screen with no interaction (the last one before exiting).
pub fn show(frame: &Frame) {
    draw(&compose(frame, &[], "", None));
}

// ---------------------------------------------------------------- menus

pub enum Entry {
    Item {
        key: String,
        label: String,
        note: String,
        enabled: bool,
    },
    Section(String),
    Gap,
    /// A key that works but is only listed in the footer (Q Quit).
    Hidden(String),
}

/// Q quits from this screen; shown in the footer, not in the list.
pub fn quit_key() -> Entry {
    Entry::Hidden("Q".into())
}

pub fn item(key: impl Into<String>, label: impl Into<String>, note: impl Into<String>) -> Entry {
    Entry::Item {
        key: key.into(),
        label: label.into(),
        note: note.into(),
        enabled: true,
    }
}

/// Shown but not selectable; `note` says why.
pub fn disabled(label: impl Into<String>, note: impl Into<String>) -> Entry {
    Entry::Item {
        key: String::new(),
        label: label.into(),
        note: note.into(),
        enabled: false,
    }
}

pub fn section(s: &str) -> Entry {
    Entry::Section(s.to_string())
}

pub fn gap() -> Entry {
    Entry::Gap
}

fn selectable(entries: &[Entry]) -> Vec<usize> {
    entries
        .iter()
        .enumerate()
        .filter(|(_, e)| matches!(e, Entry::Item { enabled: true, .. }))
        .map(|(i, _)| i)
        .collect()
}

fn key_of(e: &Entry) -> &str {
    match e {
        Entry::Item { key, .. } | Entry::Hidden(key) => key,
        _ => "",
    }
}

/// Entries a typed key may choose: enabled items and hidden keys.
fn keyed(entries: &[Entry]) -> impl Iterator<Item = &Entry> {
    entries
        .iter()
        .filter(|e| matches!(e, Entry::Item { enabled: true, .. } | Entry::Hidden(_)))
}

fn render_entries(entries: &[Entry], selected: Option<usize>) -> Vec<String> {
    let label_w = entries
        .iter()
        .filter_map(|e| match e {
            Entry::Item { label, .. } => Some(measure_text_width(label)),
            _ => None,
        })
        .max()
        .unwrap_or(0)
        .clamp(12, 40);
    let marker = if unicode() { "➤" } else { ">" };
    entries
        .iter()
        .enumerate()
        .filter(|(_, e)| !matches!(e, Entry::Hidden(_)))
        .map(|(i, e)| match e {
            Entry::Section(s) => style(s).bold().to_string(),
            Entry::Gap | Entry::Hidden(_) => String::new(),
            Entry::Item {
                key,
                label,
                note,
                enabled,
            } => {
                let pad = " ".repeat(label_w.saturating_sub(measure_text_width(label)));
                let key = format!("{key:>2}");
                if !enabled {
                    format!("      {}{pad}  {}", style(label).dim(), style(note).dim())
                } else if selected == Some(i) {
                    format!(
                        "{} {}  {}{pad}  {}",
                        style(marker).cyan(),
                        style(key).cyan().bold(),
                        style(label).cyan().bold(),
                        style(note).cyan()
                    )
                } else {
                    format!(
                        "  {}  {label}{pad}  {}",
                        style(key).cyan(),
                        style(note).dim()
                    )
                }
            }
        })
        .collect()
}

fn footer_for(entries: &[Entry]) -> String {
    let arrows = if unicode() { "↑↓" } else { "Up/Down" };
    let mut parts = vec![arrows.to_string(), "Enter".to_string()];
    for (k, name) in [("B", "Back"), ("Q", "Quit")] {
        if entries.iter().any(|e| key_of(e).eq_ignore_ascii_case(k)) {
            parts.push(format!("{k} {name}"));
        }
    }
    parts.join("  |  ")
}

/// Choose an entry; returns its key upper-cased. Arrow keys move, Enter selects,
/// a key selects directly, and Esc means Back when there is one.
pub fn menu(frame: &Frame, entries: &[Entry], default: &str) -> String {
    let choices = selectable(entries);
    if choices.is_empty() {
        return String::new();
    }
    if !fullscreen() {
        return menu_plain(frame, entries, default);
    }
    let term = Term::stdout();
    let mut pos = choices
        .iter()
        .position(|&i| key_of(&entries[i]).eq_ignore_ascii_case(default))
        .unwrap_or(0);
    let footer = footer_for(entries);
    let _ = term.hide_cursor();
    let result = loop {
        draw(&compose(
            frame,
            &render_entries(entries, Some(choices[pos])),
            &footer,
            None,
        ));
        match term.read_key_raw() {
            Ok(Key::ArrowUp) => pos = (pos + choices.len() - 1) % choices.len(),
            Ok(Key::ArrowDown) | Ok(Key::Tab) => pos = (pos + 1) % choices.len(),
            Ok(Key::Enter) => break key_of(&entries[choices[pos]]).to_ascii_uppercase(),
            Ok(Key::Escape) if entries.iter().any(|e| key_of(e).eq_ignore_ascii_case("B")) => {
                break "B".into()
            }
            Ok(Key::Char(c)) => {
                let c = c.to_string();
                if let Some(e) = keyed(entries).find(|e| key_of(e).eq_ignore_ascii_case(&c)) {
                    break key_of(e).to_ascii_uppercase();
                }
            }
            Ok(Key::CtrlC) | Err(_) => quit("Cancelled."),
            _ => {}
        }
    };
    let _ = term.show_cursor();
    result
}

fn menu_plain(frame: &Frame, entries: &[Entry], default: &str) -> String {
    let mut lines = render_entries(entries, None);
    // No footer here, so name the hidden keys once.
    if entries.iter().any(|e| matches!(e, Entry::Hidden(_))) {
        lines.push(String::new());
        lines.push(style("   Q  Quit").dim().to_string());
    }
    draw(&compose(frame, &lines, "", None));
    loop {
        let a = read_line(&format!("Choice [{default}]: ")).to_ascii_uppercase();
        let a = if a.is_empty() {
            default.to_ascii_uppercase()
        } else {
            a
        };
        if keyed(entries).any(|e| key_of(e).eq_ignore_ascii_case(&a)) {
            return a;
        }
        println!("  Choose one of the listed keys.");
    }
}

pub fn yes_no(frame: &Frame, yes: &str, no: &str, default_yes: bool) -> bool {
    let entries = [item("Y", yes, ""), item("N", no, "")];
    menu(frame, &entries, if default_yes { "Y" } else { "N" }) == "Y"
}

// ---------------------------------------------------------------- inputs

fn read_line(prompt: &str) -> String {
    print!("  {prompt}");
    let _ = io::stdout().flush();
    let mut s = String::new();
    match io::stdin().read_line(&mut s) {
        Ok(0) | Err(_) => quit("Input closed."),
        Ok(_) => {}
    }
    s.trim().to_string()
}

/// A text field below the screen. Enter keeps `default`.
pub fn input(frame: &Frame, label: &str, default: &str) -> String {
    let footer = if default.is_empty() {
        "Enter to confirm  |  Ctrl+C to quit"
    } else {
        "Enter keeps the value in brackets  |  Ctrl+C to quit"
    };
    draw(&compose(frame, &[], footer, None));
    if fullscreen() {
        println!();
    }
    let prompt = if default.is_empty() {
        format!("{label}: ")
    } else {
        format!("{label} [{default}]: ")
    };
    let s = read_line(&prompt);
    if s.is_empty() {
        default.to_string()
    } else {
        s
    }
}

/// Masked password field. Reads key by key in raw mode so Ctrl+C restores the
/// terminal before exiting, instead of leaving echo switched off.
pub fn secret(frame: &Frame, label: &str) -> String {
    draw(&compose(
        frame,
        &[],
        "Enter to sign in  |  Ctrl+C to quit",
        None,
    ));
    if fullscreen() {
        println!();
    }
    print!("  {label}: ");
    let _ = io::stdout().flush();
    let term = Term::stdout();
    let mut pw = String::new();
    loop {
        match term.read_key_raw() {
            Ok(Key::Enter) => break,
            Ok(Key::Backspace) => {
                if pw.pop().is_some() {
                    print!("\x08 \x08");
                }
            }
            Ok(Key::Char(c)) if !c.is_control() => {
                pw.push(c);
                print!("*");
            }
            Ok(Key::CtrlC) | Err(_) => quit("Cancelled."),
            _ => {}
        }
        let _ = io::stdout().flush();
    }
    println!();
    pw
}

pub fn quit(msg: &str) -> ! {
    let _ = Term::stdout().show_cursor();
    println!();
    println!("  {}", style(msg).dim());
    std::process::exit(130);
}

// ---------------------------------------------------------------- work in progress

/// Run `f` while the screen shows a spinner. If the frame has no `spinning` line,
/// one is added with `label`. Without a full screen, a spinner runs on stderr.
pub fn busy<T>(frame: &Frame, label: &str, f: impl FnOnce() -> T) -> T {
    let mut frame = frame.clone();
    if !frame.lines.iter().any(|l| l.starts_with(SPIN)) {
        frame.blank();
        frame.spinning(label);
    }
    let stop = Arc::new(AtomicBool::new(false));
    let handle = if fullscreen() {
        let flag = stop.clone();
        Some(std::thread::spawn(move || {
            let started = Instant::now();
            let mut i = 0;
            while !flag.load(Ordering::Relaxed) {
                draw(&compose(
                    &frame,
                    &[],
                    "Working…",
                    Some((i, started.elapsed().as_secs())),
                ));
                i += 1;
                std::thread::sleep(Duration::from_millis(120));
            }
        }))
    } else {
        let term = Term::stderr();
        term.is_term().then(|| {
            let flag = stop.clone();
            let text = label.to_string();
            std::thread::spawn(move || {
                let mut i = 0;
                while !flag.load(Ordering::Relaxed) {
                    let _ = term.write_str(&format!("\r  {}  {text}", spin_frame(i)));
                    i += 1;
                    std::thread::sleep(Duration::from_millis(120));
                }
                let _ = term.clear_line();
            })
        })
    };
    let r = f();
    stop.store(true, Ordering::Relaxed);
    if let Some(h) = handle {
        let _ = h.join();
    }
    r
}

pub fn wrap(text: &str, max: usize) -> Vec<String> {
    let mut out = Vec::new();
    for para in text.split('\n') {
        let mut cur = String::new();
        for word in para.split(' ') {
            if !cur.is_empty() && measure_text_width(&cur) + 1 + measure_text_width(word) > max {
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wrapping_keeps_words_whole() {
        assert_eq!(wrap("aaa bbb ccc ddd", 7), vec!["aaa bbb", "ccc ddd"]);
        assert_eq!(wrap("one\ntwo", 80), vec!["one", "two"]);
    }

    #[test]
    fn disabled_entries_are_not_selectable() {
        let e = [
            section("S"),
            item("1", "a", ""),
            disabled("b", "why"),
            gap(),
            quit_key(),
        ];
        // Q is typed, never reached with the arrows, and listed only in the footer.
        assert_eq!(selectable(&e), vec![1]);
        assert_eq!(keyed(&e).map(key_of).collect::<Vec<_>>(), vec!["1", "Q"]);
        assert_eq!(render_entries(&e, None).len(), 4);
        assert!(footer_for(&e).contains("Q Quit") && !footer_for(&e).contains("Back"));
    }
}

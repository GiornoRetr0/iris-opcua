#!/usr/bin/env node
/**
 * Template guard — catches the class of defect that shipped F2 and F12.
 *
 * Four of the audit's findings were mechanically detectable and none were
 * detected: a duplicate `class` attribute silently dropped `w-full` from the
 * telemetry bars (Angular keeps the last attribute of a repeated name), a
 * `(click)` on a non-interactive tag, and elements styled as controls with
 * nothing behind them. `tsc` does not look inside templates and the Angular
 * compiler treats a repeated attribute as legal, so nothing in the toolchain
 * would have said a word.
 *
 * Rules
 *   1. DUPE-ATTR   — the same attribute or binding twice on one element.
 *                    This is the F2 root cause and is always a bug.
 *   2. CLICK-ROLE  — (click) on a non-interactive tag with no role/tabindex.
 *                    A div that responds to a click but not to Enter.
 *
 * Rule 2 has a recorded baseline (see BASELINE below): existing violations are
 * reported but do not fail the build, while any *new* one does. The baseline is
 * a ratchet — it may shrink, never grow.
 *
 * Usage: node tools/check-templates.mjs [--list]
 */
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { parseTemplate } from '@angular/compiler';

const ROOT = new URL('..', import.meta.url).pathname;
const SRC = join(ROOT, 'src');

/**
 * Tags that are focusable and keyboard-operable on their own. Anything else
 * carrying a (click) needs an explicit role plus tabindex to be reachable.
 */
const INTERACTIVE = new Set([
  'a', 'button', 'input', 'select', 'textarea', 'summary', 'details',
  'label', 'option', 'audio', 'video',
]);

/**
 * Known CLICK-ROLE violations, as `file:tag` counts. Reported every run so they
 * stay visible, but tolerated so the guard can be adopted without a
 * simultaneous a11y sweep. Lower these numbers as the divs become buttons;
 * the guard fails if any count goes *up*.
 */
const BASELINE = {
  'app/layout/top-nav/top-nav.component.ts': 1,
  'app/pages/schema-builder/schema-builder.component.ts': 1,
  'app/shared/settings-modal/settings-modal.component.ts': 4,
};

/** Recursively collect .ts files under a directory. */
function collectTs(dir, out = []) {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) collectTs(full, out);
    else if (entry.endsWith('.ts') && !entry.endsWith('.spec.ts')) out.push(full);
  }
  return out;
}

/**
 * Pull the inline `template:` backtick literal out of a component source.
 * Returns { text, lineOffset } so reported lines map back to the .ts file.
 * Angular templates use {{ }} rather than ${ }, so a plain scan to the closing
 * backtick is sufficient here — no expression nesting to track.
 */
function extractTemplate(source) {
  const marker = /(^|\s)template:\s*`/m.exec(source);
  if (!marker) return null;
  const start = marker.index + marker[0].length;
  let i = start;
  while (i < source.length) {
    if (source[i] === '\\') { i += 2; continue; }
    if (source[i] === '`') break;
    i++;
  }
  if (i >= source.length) return null;
  return {
    text: source.slice(start, i),
    lineOffset: source.slice(0, start).split('\n').length - 1,
  };
}

/**
 * Walk every node the parser can produce. Blocks (@if/@for/@switch/@defer)
 * hold their children under differently-named arrays, so rather than enumerate
 * the AST classes we visit any array-valued property that contains nodes.
 */
function walk(nodes, visit) {
  for (const node of nodes ?? []) {
    if (!node || typeof node !== 'object') continue;
    if (Array.isArray(node.attributes) && typeof node.name === 'string') visit(node);
    for (const key of ['children', 'branches', 'cases', 'placeholder', 'loading', 'error', 'empty', 'body']) {
      const value = node[key];
      if (Array.isArray(value)) walk(value, visit);
      else if (value && typeof value === 'object') walk([value], visit);
    }
  }
}

const findings = [];
const clickRoleByFile = {};

for (const file of collectTs(SRC)) {
  const rel = relative(SRC, file);
  const source = readFileSync(file, 'utf8');
  const tpl = extractTemplate(source);
  if (!tpl) continue;

  const parsed = parseTemplate(tpl.text, file, { preserveWhitespaces: true });
  if (parsed.errors?.length) {
    for (const e of parsed.errors) {
      findings.push({ rule: 'PARSE', rel, line: '?', msg: e.msg, hard: true });
    }
    continue;
  }

  walk(parsed.nodes, (el) => {
    const line = tpl.lineOffset + el.startSourceSpan.start.line + 1;

    // Rule 1 — the same attribute or binding declared twice. Angular keeps the
    // last and silently discards the rest.
    // `[(ngModel)]="x" (ngModelChange)="f()"` is the idiomatic way to run a side
    // effect alongside a two-way binding: the banana-in-a-box desugars to its own
    // ngModelChange output and Angular calls *both* handlers, so this particular
    // repetition drops nothing. Every other duplicate does.
    const twoWay = new Set(
      (el.inputs ?? []).filter((i) => i.name === 'ngModel').map(() => 'ngModelChange')
    );
    const named = [
      ...el.attributes.map((a) => a.name),
      ...(el.inputs ?? []).map((a) => `[${a.name}]`),
      ...(el.outputs ?? []).map((a) => `(${a.name})`),
    ];
    const seen = new Set();
    for (const name of named) {
      if (name === '(ngModelChange)' && twoWay.has('ngModelChange')) continue;
      if (seen.has(name)) {
        findings.push({
          rule: 'DUPE-ATTR', rel, line, hard: true,
          msg: `<${el.name}> declares "${name}" more than once — Angular keeps the last and drops the rest`,
        });
      }
      seen.add(name);
    }

    // Rule 2 — a click target that the keyboard cannot reach.
    const hasClick = (el.outputs ?? []).some((o) => o.name === 'click');
    if (hasClick && !INTERACTIVE.has(el.name)) {
      const attrNames = new Set([
        ...el.attributes.map((a) => a.name),
        ...(el.inputs ?? []).map((a) => a.name),
      ]);
      if (!attrNames.has('role') && !attrNames.has('tabindex')) {
        clickRoleByFile[rel] = (clickRoleByFile[rel] ?? 0) + 1;
        findings.push({
          rule: 'CLICK-ROLE', rel, line, hard: false,
          msg: `<${el.name}> has (click) but no role/tabindex — not reachable by keyboard`,
        });
      }
    }
  });
}

const listOnly = process.argv.includes('--list');
let failed = false;

for (const f of findings.filter((f) => f.hard)) {
  console.error(`✗ ${f.rule} ${f.rel}:${f.line} — ${f.msg}`);
  failed = true;
}

// Ratchet: report the baselined findings, fail only if a file gained one.
for (const [rel, count] of Object.entries(clickRoleByFile)) {
  const allowed = BASELINE[rel] ?? 0;
  const soft = findings.filter((f) => f.rule === 'CLICK-ROLE' && f.rel === rel);
  if (count > allowed) {
    console.error(`✗ CLICK-ROLE ${rel} — ${count} violations, baseline allows ${allowed}`);
    for (const f of soft) console.error(`    :${f.line} — ${f.msg}`);
    failed = true;
  } else if (listOnly) {
    for (const f of soft) console.log(`· CLICK-ROLE ${rel}:${f.line} — ${f.msg} (baselined)`);
  }
}

// A baseline that is now too generous is itself a finding — keep it honest.
for (const [rel, allowed] of Object.entries(BASELINE)) {
  const actual = clickRoleByFile[rel] ?? 0;
  if (actual < allowed) {
    console.error(
      `✗ BASELINE ${rel} — allows ${allowed} CLICK-ROLE violations but only ${actual} remain; ` +
      `lower it in tools/check-templates.mjs`
    );
    failed = true;
  }
}

if (failed) {
  console.error('\nTemplate guard failed. See webapp/tools/check-templates.mjs for the rules.');
  process.exit(1);
}
console.log(`✓ template guard: ${findings.length === 0 ? 'clean' : `${findings.length} baselined`}`);

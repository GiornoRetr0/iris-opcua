import { Component, input, inject, signal, effect, untracked, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { TreeNode, NodeReadResult } from '../../../core/models/opcua.models';
import { ApiService } from '../../../core/services/api.service';
import { ConfigService } from '../../../core/services/config.service';
import { severityOf, statusText, statusDetail } from '../../../core/opcua-status';

@Component({
  selector: 'app-node-detail',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    @if (!node()) {
      <!-- Empty state -->
      <div class="flex flex-col items-center justify-center min-h-[60vh] text-on-surface-variant">
        <span class="material-symbols-outlined text-8xl opacity-10 mb-4">account_tree</span>
        <h2 class="text-xl font-semibold text-primary mb-2">Select a Node</h2>
        <p class="text-sm text-on-surface-muted">Browse the address space tree on the left to view node details.</p>
      </div>
    } @else {
      <div class="max-w-6xl mx-auto space-y-8">
        <!-- Header Breadcrumb/Title -->
        <div class="flex items-end justify-between">
          <div>
            <!-- A real path, walked from parentRef. The first segment used to be the
                 hardcoded string "Objects", so this read "Objects > Objects" at the
                 root and "Objects > SA1" for nodes not under Objects at all. -->
            <nav class="flex items-center gap-2 text-xs font-medium text-on-surface-variant mb-2">
              @for (seg of breadcrumb(); track $index; let last = $last) {
                <span [class]="last ? 'text-primary font-semibold' : ''">{{ seg }}</span>
                @if (!last) {
                  <span class="material-symbols-outlined text-xs">chevron_right</span>
                }
              }
            </nav>
            <h1 class="text-2xl font-semibold text-primary">{{ node()!.displayName }}</h1>
          </div>
          <div class="flex items-center gap-4">
            <!-- A switch, not a checkbox: this takes effect immediately rather than
                 on a submit, which is the convention a switch signals. Still a real
                 checkbox input underneath, so it keeps its keyboard behaviour and
                 label association for free. -->
            <label class="flex items-center gap-2 text-sm font-medium text-on-surface-variant cursor-pointer select-none">
              <span class="relative inline-flex items-center">
                <input type="checkbox" [(ngModel)]="autoRefresh"
                       (ngModelChange)="onAutoRefreshToggle()"
                       class="peer sr-only">
                <span class="switch-track h-5 w-9 rounded-full bg-surface-container-highest transition-colors
                             peer-checked:bg-primary peer-focus-visible:ring-2 peer-focus-visible:ring-primary/40"></span>
                <span class="switch-knob absolute left-0.5 h-4 w-4 rounded-full bg-white shadow transition-transform"></span>
              </span>
              Auto-refresh
            </label>
            <button (click)="readValue()"
                    class="flex items-center gap-2 bg-surface-container-lowest text-primary px-4 py-2 rounded-lg text-sm font-bold shadow-sm border border-outline-variant/20 hover:bg-white transition-colors">
              <span class="material-symbols-outlined text-sm">refresh</span>
              Read
            </button>
          </div>
        </div>

        <!-- Bento Grid Layout -->
        <div class="grid grid-cols-1 md:grid-cols-12 gap-6">
          <!-- Main Value Hero Card -->
          <div class="md:col-span-8 bg-surface-container-lowest rounded-xl p-8 shadow-sm relative overflow-hidden flex flex-col justify-between min-h-[320px]">
            <div class="absolute top-0 right-0 p-8 opacity-5">
              <span class="material-symbols-outlined text-9xl">analytics</span>
            </div>
            <div>
              <p class="text-[10px] font-bold text-on-surface-variant uppercase tracking-[0.2em] mb-1">Current Process Value</p>
              <h2 class="text-sm font-medium text-on-surface-muted">{{ node()!.displayName }}</h2>
            </div>

            <!-- The failure is surfaced on the card that owns the value, not only on
                 the nav-rail dot on its independent 15s timer. Vocabulary mirrors the
                 business service side, which names the consequence rather than the mechanism. -->
            @if (isStale()) {
              <div class="flex items-start gap-2.5 rounded-lg px-3 py-2.5 mt-4 border"
                   [class]="freshness() === 'disconnected'
                     ? 'bg-error-container/25 border-error/20'
                     : 'bg-amber-50 border-amber-300'">
                <span class="material-symbols-outlined text-lg shrink-0"
                      [class]="freshness() === 'disconnected' ? 'text-error' : 'text-amber-700'">history</span>
                <div class="min-w-0">
                  <p class="text-sm font-bold"
                     [class]="freshness() === 'disconnected' ? 'text-on-error-container' : 'text-amber-900'">
                    {{ freshness() === 'disconnected' ? 'Not reading this node' : 'This value may be out of date' }}
                  </p>
                  <p class="text-xs mt-0.5"
                     [class]="freshness() === 'disconnected' ? 'text-on-error-container/80' : 'text-amber-900/80'">
                    {{ stalenessMessage() }}
                  </p>
                </div>
              </div>
            }
            <div class="flex items-baseline gap-4 mt-8"
                 [class.opacity-60]="isStale()">
              @if (readResult()) {
                <!-- Size bound to length: 120px only holds about six characters, so a
                     long string used to overflow its card silently. getUnit() and its
                     always-empty text-2xl span are gone (D3) — engineering units need
                     an EUInformation read the C++ layer does not expose, which is its
                     own piece of work, not a reserved empty box. -->
                <span class="font-bold leading-none tracking-tighter break-all"
                      [class]="heroSizeClass()">
                  {{ formatHeroValue(readResult()!) }}
                </span>
              } @else if (readLoading()) {
                <span class="text-4xl font-bold text-on-surface-variant opacity-30">Reading...</span>
              } @else {
                <span class="text-4xl font-bold text-on-surface-variant opacity-30">—</span>
              }
            </div>
            <div class="mt-8 pt-6 border-t border-surface-container">
              <div class="flex gap-12">
                <div>
                  <p class="text-[10px] font-bold text-on-surface-variant uppercase tracking-widest mb-1">Read</p>
                  <span class="inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-xs font-bold"
                        [class]="ageChipClass()"
                        [title]="lastSuccessAt() ? 'Last successful read at ' + lastSuccessClock() : 'No successful read yet'">
                    @if (isStale()) {
                      <span class="material-symbols-outlined text-[13px]">history</span>
                    }
                    {{ ageLabel() }}
                  </span>
                </div>
                <div>
                  <p class="text-[10px] font-bold text-on-surface-variant uppercase tracking-widest mb-1">Status</p>
                  <div class="flex items-center gap-2">
                    <span class="h-2 w-2 rounded-full" [class]="severityDotClass()"></span>
                    <span class="text-sm font-bold text-on-surface" [title]="statusTitle()">
                      {{ statusLabel() }}
                    </span>
                  </div>
                </div>
                <div>
                  <p class="text-[10px] font-bold text-on-surface-variant uppercase tracking-widest mb-1">Last Updated</p>
                  <p class="text-sm font-bold text-on-surface">{{ formatTimestamp(readResult()?.serverTimestamp) }}</p>
                </div>
                <div>
                  <p class="text-[10px] font-bold text-on-surface-variant uppercase tracking-widest mb-1">Source Timestamp</p>
                  <!-- SourceTimestamp is genuinely optional in OPC UA, so its absence is
                       information rather than an error — say "not reported", not a dash.
                       This used to render the word "Synchronized" while holding the real
                       timestamp, which asserted a sync state nothing had measured. -->
                  @if (sourceTimestampText(); as ts) {
                    <p class="text-sm font-bold text-on-surface">{{ ts }}</p>
                  } @else {
                    <p class="text-sm font-medium text-on-surface-muted italic">not reported</p>
                  }
                </div>
              </div>
            </div>
          </div>

          <!-- Node Identification Sidebar (dark card) -->
          <div class="md:col-span-4 bg-primary text-white rounded-xl p-8 shadow-lg flex flex-col justify-between">
            <div>
              <p class="text-[10px] font-bold text-on-primary-container uppercase tracking-widest mb-4">Node Identification</p>
              <div class="space-y-6">
                <div>
                  <p class="text-[10px] text-on-primary-muted uppercase font-bold tracking-widest">Node ID</p>
                  <p class="text-lg font-mono font-medium truncate">ns={{ node()!.nodeNs }};{{ idPrefix() }}={{ node()!.nodeId }}</p>
                </div>
                <div>
                  <p class="text-[10px] text-on-primary-muted uppercase font-bold tracking-widest">Namespace</p>
                  <p class="text-md font-medium">{{ node()!.nodeNs }}</p>
                </div>
                <div>
                  <p class="text-[10px] text-on-primary-muted uppercase font-bold tracking-widest">ID Type</p>
                  <div class="mt-1 inline-block px-2 py-1 bg-white/10 rounded text-xs font-bold uppercase tracking-wider">
                    {{ idTypeName() }}
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- Detailed Properties Grid.
               Two cards, not three: CATEGORY used to render nodeCategory twice in one
               card ("Folder" then "Node Category: folder"), and TYPE DEFINITION
               headlined a data type inferred from the *value read* — so a folder,
               whose read necessarily fails, displayed "String". That did not mean
               "this is a string"; it meant "the read failed". They are now one card
               that separates node class (from browse, always known) from data type
               (from the read, sometimes not). -->
          <div class="md:col-span-12 grid grid-cols-1 md:grid-cols-2 gap-6">
            <!-- Node class + data type -->
            <div class="bg-surface-container-lowest p-6 rounded-xl shadow-sm border border-outline-variant/5">
              <div class="flex items-center gap-3 mb-4">
                <div class="bg-secondary-container/50 p-2 rounded-lg text-primary">
                  <span class="material-symbols-outlined">category</span>
                </div>
                <p class="text-[10px] font-bold text-on-surface-variant uppercase tracking-widest">Node Class &amp; Type</p>
              </div>
              <p class="text-[10px] font-bold text-on-surface-muted uppercase tracking-widest">Node class</p>
              <p class="text-xl font-bold text-on-surface capitalize">{{ node()!.nodeCategory }}</p>

              <p class="text-[10px] font-bold text-on-surface-muted uppercase tracking-widest mt-3">Data type</p>
              <p class="text-sm font-semibold"
                 [class]="dataTypeKnown() ? 'text-on-surface' : 'text-on-surface-muted italic'">
                {{ dataTypeLabel() }}
              </p>
              <p class="text-xs text-on-surface-muted mt-2">TypeDef: ns={{ node()!.typeDefNs }}, id={{ node()!.typeDefId }}</p>
            </div>
            <!-- Reference -->
            <div class="bg-surface-container-lowest p-6 rounded-xl shadow-sm border border-outline-variant/5">
              <div class="flex items-center gap-3 mb-4">
                <div class="bg-secondary-container/50 p-2 rounded-lg text-primary">
                  <span class="material-symbols-outlined">link</span>
                </div>
                <p class="text-[10px] font-bold text-on-surface-variant uppercase tracking-widest">Reference</p>
              </div>
              <p class="text-xl font-bold text-on-surface">{{ node()!.referenceType }}</p>
              <p class="text-xs text-on-surface-muted mt-2">Reference Type</p>
            </div>
          </div>
        </div>
      </div>
    }
  `,
})
export class NodeDetailComponent implements OnDestroy {
  node = input<TreeNode | null>(null);

  private api = inject(ApiService);
  config = inject(ConfigService);

  readResult = signal<NodeReadResult | null>(null);
  readLoading = signal(false);
  autoRefresh = true;
  private refreshInterval: any;

  // ── Staleness tracking ──────────────────────────────────────────────────────
  // The REST API is stateless: every read opens a connection, reads, and
  // disconnects. A failed read used to leave the previous result on screen
  // untouched — same value, same status, same timestamp — so an operator could
  // watch "31 / Good / 12:04:07" while the server had been unreachable for a
  // minute. The only signal was the nav rail's dot, on its own 15s timer, in a
  // different part of the screen, reporting server reachability rather than "the
  // value you are looking at is stale". That is the dangerous failure mode in a
  // tool whose decisions reach physical equipment.

  /** When the last *successful* read landed. Null until one does. */
  lastSuccessAt = signal<number | null>(null);
  /** Why the most recent read failed, or '' if it succeeded. */
  lastError = signal('');
  /** Consecutive failures. Reset by any success. */
  consecutiveFailures = signal(0);
  /** Ticks every second so the rendered age stays true without a re-read. */
  private now = signal(Date.now());
  private ageTicker: any;

  constructor() {
    // Only the selected node should drive this. Everything the body calls is
    // untracked because `setupAutoRefresh` and `readValue` both read the config
    // signal on their way to an interval and a URL: tracked, that made an
    // unrelated settings save re-enter the effect, which calls `resetFreshness()`
    // — so changing any preference silently threw away the staleness history and
    // made a stale value look freshly read. The node is the dependency; the rest
    // is the work.
    effect(() => {
      const n = this.node();
      untracked(() => {
        if (n) {
          // A different node means the previous node's history says nothing about
          // this one. Clearing is what stops one node's freshness vouching for
          // another's.
          this.resetFreshness();
          this.readValue();
          this.setupAutoRefresh();
        } else {
          this.clearAutoRefresh();
          this.readResult.set(null);
          this.resetFreshness();
        }
      });
    });

    this.ageTicker = setInterval(() => this.now.set(Date.now()), 1000);
  }

  ngOnDestroy(): void {
    this.clearAutoRefresh();
    if (this.ageTicker) clearInterval(this.ageTicker);
  }

  private resetFreshness(): void {
    this.lastSuccessAt.set(null);
    this.lastError.set('');
    this.consecutiveFailures.set(0);
  }

  readValue(): void {
    const n = this.node();
    if (!n) return;
    this.readLoading.set(true);
    this.api.read(n.nodeNs, n.nodeId, n.nodeIdType).subscribe({
      next: (result) => {
        this.readResult.set(result);
        this.readLoading.set(false);
        // A transported read whose StatusCode is Bad is not a successful reading.
        // Counting it as fresh would let a server that answers "I can't tell you"
        // keep the card looking live.
        if (result.readError) {
          this.recordFailure(result.readError);
        } else {
          this.lastSuccessAt.set(Date.now());
          this.lastError.set('');
          this.consecutiveFailures.set(0);
        }
      },
      error: (err) => {
        // The error callback used to only clear the spinner. Recording the
        // failure is what makes staleness visible at all.
        this.readLoading.set(false);
        this.recordFailure(err?.error?.error || err?.message || 'The read failed');
      },
    });
  }

  private recordFailure(message: string): void {
    this.lastError.set(message);
    this.consecutiveFailures.update((n) => n + 1);
  }

  /** Seconds since the last successful read, or null if there has never been one. */
  ageSeconds(): number | null {
    const at = this.lastSuccessAt();
    if (at == null) return null;
    return Math.max(0, Math.round((this.now() - at) / 1000));
  }

  /**
   * Freshness, derived from the refresh interval rather than hardcoded — a 30s
   * interval should not be called stale at 15s (D4).
   *
   *   live         a recent successful read
   *   stale        no success for ~3 intervals — the value may no longer be true
   *   disconnected no success for ~6 intervals — treat the value as historical
   */
  freshness(): 'unknown' | 'live' | 'stale' | 'disconnected' {
    const age = this.ageSeconds();
    if (age == null) return 'unknown';
    const interval = this.config.get().autoRefreshInterval || 5;
    // Without auto-refresh nothing is re-reading, so age is the user's own doing
    // and decaying the value would be misleading rather than informative.
    if (!this.autoRefresh) return 'live';
    if (age >= interval * 6) return 'disconnected';
    if (age >= interval * 3) return 'stale';
    return 'live';
  }

  /** True once the value on screen should stop claiming to be current. */
  isStale(): boolean {
    const f = this.freshness();
    return f === 'stale' || f === 'disconnected';
  }

  /** "4s ago" / "2m ago", for the age chip beside the value. */
  ageLabel(): string {
    const age = this.ageSeconds();
    if (age == null) return 'never read';
    if (age < 2) return 'just now';
    if (age < 60) return `${age}s ago`;
    if (age < 3600) return `${Math.floor(age / 60)}m ago`;
    return `${Math.floor(age / 3600)}h ago`;
  }

  ageChipClass(): string {
    switch (this.freshness()) {
      case 'stale': return 'text-amber-700 bg-amber-50 border-amber-300';
      case 'disconnected': return 'text-error bg-error-container/40 border-error/30';
      default: return 'text-on-surface-muted bg-surface-container-low border-outline-variant/20';
    }
  }

  /** The clock time the on-screen value was actually read at. */
  lastSuccessClock(): string {
    const at = this.lastSuccessAt();
    if (at == null) return '';
    return new Date(at).toLocaleTimeString('en-US', {
      hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit',
    });
  }

  /**
   * The banner text. Mirrors the business service side's vocabulary, which already gets
   * this right: name the consequence, not the mechanism.
   */
  stalenessMessage(): string {
    const f = this.freshness();
    const failures = this.consecutiveFailures();
    const detail = this.lastError() ? ` ${this.lastError()}` : '';
    if (f === 'disconnected') {
      return `Not reading — ${failures} failed attempt${failures === 1 ? '' : 's'} since ` +
        `${this.lastSuccessClock()}. The value below is historical.${detail}`;
    }
    return `Last read failed${failures > 1 ? ` (${failures} attempts)` : ''} — ` +
      `this value is from ${this.lastSuccessClock()}.${detail}`;
  }

  onAutoRefreshToggle(): void {
    if (this.autoRefresh) {
      this.setupAutoRefresh();
    } else {
      this.clearAutoRefresh();
    }
  }

  private setupAutoRefresh(): void {
    this.clearAutoRefresh();
    if (!this.autoRefresh) return;
    const interval = (this.config.get().autoRefreshInterval || 5) * 1000;
    this.refreshInterval = setInterval(() => this.readValue(), interval);
  }

  private clearAutoRefresh(): void {
    if (this.refreshInterval) {
      clearInterval(this.refreshInterval);
      this.refreshInterval = null;
    }
  }

  /**
   * The hero value. Truncation is marked with an ellipsis — it used to
   * `substring(0, 20)` silently, so a 40-character value rendered as its first 20
   * and looked complete.
   */
  formatHeroValue(result: NodeReadResult): string {
    if (result.readError) return 'no reading';
    const val = result.value;
    if (val == null || val === '') return 'empty';
    const num = parseFloat(val);
    if (!isNaN(num) && String(val).trim() !== '') {
      return num % 1 === 0 ? String(Math.round(num)) : num.toFixed(2);
    }
    const s = String(val);
    return s.length > 20 ? s.slice(0, 20) + '…' : s;
  }

  /**
   * 120px fits roughly six characters in this card. Anything longer steps down
   * rather than overflowing.
   */
  heroSizeClass(): string {
    const r = this.readResult();
    if (!r) return 'text-5xl text-on-surface-muted';
    const rendered = this.formatHeroValue(r);
    // 'no reading' / 'empty' are statements about absence, not values, so they get
    // the muted treatment. The colour lives here rather than in the static class
    // list, so there is one source of truth for it.
    if (r.readError || rendered === 'empty' || rendered === 'no reading') {
      return 'text-4xl text-on-surface-muted italic font-medium';
    }
    if (rendered.length <= 6) return 'text-[120px] text-primary';
    if (rendered.length <= 12) return 'text-6xl text-primary';
    return 'text-4xl text-primary';
  }

  /**
   * The path to this node, walked up parentRef. Falls back to the node's own name
   * when it has no threaded parent (a server root, or a node reached directly).
   */
  breadcrumb(): string[] {
    const segments: string[] = [];
    let cur: TreeNode | null | undefined = this.node();
    // Guard against a malformed cycle rather than hanging the render.
    for (let i = 0; cur && i < 32; i++) {
      segments.unshift(cur.displayName);
      cur = cur.parentRef;
    }
    return segments;
  }

  /**
   * OPC UA severity, from the top two bits of the StatusCode.
   * 0 = Good, 1 = Uncertain, 2/3 = Bad. See OPC UA Part 4, 7.34.
   *
   * The dot used to branch on `readError` alone while the label beside it read
   * `statusCode`, so a Bad status that transported successfully — no read error,
   * statusCode 0x80350000 — rendered on the healthy green dot.
   */
  severity(): 'good' | 'uncertain' | 'bad' | 'unknown' {
    const r = this.readResult();
    if (!r) return 'unknown';
    if (r.readError) return 'bad';
    if (r.statusCode == null) return 'unknown';
    return severityOf(r.statusCode);
  }

  severityDotClass(): string {
    switch (this.severity()) {
      case 'good': return 'bg-tertiary';
      case 'uncertain': return 'bg-amber-500';
      case 'bad': return 'bg-error';
      default: return 'bg-on-surface-variant/40';
    }
  }

  /** The status in words. See core/opcua-status.ts for where the table comes from. */
  statusLabel(): string {
    const r = this.readResult();
    if (!r) return '—';
    if (r.readError) return 'Read failed';
    if (r.statusCode == null) return 'Unknown';
    return statusText(r.statusCode);
  }

  /**
   * Hover text: the spec identifier and hex, which are what appear in the event
   * log and in vendor documentation — so they are the useful things to be able to
   * read off and search for.
   */
  statusTitle(): string {
    const r = this.readResult();
    if (!r) return '';
    if (r.readError) return r.readError;
    return r.statusCode != null ? statusDetail(r.statusCode) : '';
  }

  /**
   * The source timestamp as a clock time, or '' when the server did not report
   * one. Returning '' rather than a placeholder lets the template pick the
   * treatment: real data gets the bold on-surface style, absence gets muted
   * italics and says so in words.
   */
  sourceTimestampText(): string {
    const ts = this.readResult()?.sourceTimestamp;
    return this.isMissingTimestamp(ts) ? '' : this.formatTimestamp(ts);
  }

  /**
   * True when a timestamp field carries no timestamp.
   *
   * Three ways that happens, and only one of them is a missing string: the OPC UA
   * null DateTime is 1601-01-01 (the Windows FILETIME epoch), and the server
   * sends it in full for a node that has no timestamp to report. A folder read
   * comes back with "1601-01-01 00:00:00.0000000" — truthy, parseable, and
   * rendering as a confident "00:00:00" if you only check for absence.
   */
  private isMissingTimestamp(ts: string | undefined): boolean {
    if (!ts) return true;
    const d = new Date(ts);
    return isNaN(d.getTime()) || d.getUTCFullYear() <= 1601;
  }

  /**
   * A clock time, HH:MM:SS.
   *
   * Milliseconds are dropped deliberately: on a 5-second refresh they are false
   * precision. This previously passed `fractionalSecondDigits` *alone*, which
   * asks for the fractional part of a time whose hours, minutes and seconds were
   * never requested — hence the bare "235" the audit found.
   */
  formatTimestamp(ts: string | undefined): string {
    if (this.isMissingTimestamp(ts)) return '—';
    return new Date(ts!).toLocaleTimeString('en-US', {
      hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit',
    });
  }

  get idPrefix(): () => string {
    return () => {
      const n = this.node();
      if (!n) return 'i';
      switch (n.nodeIdType) {
        case 0: return 'i';
        case 1: return 's';
        case 2: return 'g';
        case 3: return 's';
        default: return 'i';
      }
    };
  }

  get idTypeName(): () => string {
    return () => {
      const n = this.node();
      if (!n) return 'Numeric';
      switch (n.nodeIdType) {
        case 0: return 'Numeric';
        case 1: return 'String';
        case 2: return 'GUID';
        case 3: return 'String';
        default: return 'Numeric';
      }
    };
  }

  /**
   * Whether the data type on screen came from a successful read.
   *
   * `inferredType` is derived by reading the node's value and pattern-matching the
   * result, and `ReadService` substitutes StringDataValue as a blanket default when
   * that fails. So "String" arrives identically for a genuine string, an
   * unreadable node, a folder, and an unreachable server — and must not be
   * presented as a type in the last three cases.
   */
  dataTypeKnown(): boolean {
    const r = this.readResult();
    if (!r || r.readError || !r.inferredType) return false;
    if (this.node()?.nodeCategory !== 'variable') return false;
    return this.severity() === 'good' || this.severity() === 'uncertain';
  }

  dataTypeLabel(): string {
    const r = this.readResult();
    if (!r) return 'not read yet';
    if (this.node()?.nodeCategory !== 'variable') return 'not applicable — this node has no value';
    if (!this.dataTypeKnown()) return 'not readable';
    const parts = r.inferredType!.split('.');
    return parts[parts.length - 1].replace('DataValue', '');
  }
}

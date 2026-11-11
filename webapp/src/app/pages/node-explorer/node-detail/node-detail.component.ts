import { Component, input, inject, signal, computed, effect, untracked, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Subscription } from 'rxjs';
import { TreeNode, NodeReadResult, ServerProfile } from '../../../core/models/opcua.models';
import { ApiService, apiErrorMessage } from '../../../core/services/api.service';
import { ConfigService } from '../../../core/services/config.service';
import { severityOf, statusText, statusDetail } from '../../../core/opcua-status';
import { parseIrisUtc, localClock, localDateTime } from '../../../core/util/iris-time';

/**
 * NodeId identifier types as the native layer reports them (open62541's
 * UA_NodeIdType, mirrored in Constants.inc): 0 Numeric, 3 String, 4 GUID,
 * 5 ByteString. This used to map 1/2/3, so a GUID or ByteString node showed as
 * "Numeric" with an `i=` prefix.
 */
const ID_TYPES: Record<number, { prefix: string; name: string }> = {
  0: { prefix: 'i', name: 'Numeric' },
  3: { prefix: 's', name: 'String' },
  4: { prefix: 'g', name: 'GUID' },
  5: { prefix: 'b', name: 'ByteString' },
};

/** A plain decimal number, nothing before or after it. */
const NUMERIC = /^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$/;
const INTEGER = /^[+-]?\d+$/;

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
  /**
   * The read in flight, if any. Each read opens its own OPC UA connection (a Sign &
   * Encrypt one takes noticeably longer) and may take up to the 15s request timeout,
   * so without this a 5s timer stacked reads whose answers could land out of order,
   * and a read for the previous node could land after the user selected another.
   */
  private inflight: Subscription | null = null;
  /** Seconds between auto-refresh reads; tracked so a settings change applies at once. */
  private interval = computed(() => this.config.config().autoRefreshInterval || 5);

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
        // The previous node's read, if still running, must not land on this one.
        this.cancelRead();
        // So must its value: it is not this node's.
        this.readResult.set(null);
        if (n) {
          // A different node means the previous node's history says nothing about
          // this one. Clearing is what stops one node's freshness vouching for
          // another's.
          this.resetFreshness();
          this.readValue();
          this.setupAutoRefresh();
        } else {
          this.clearAutoRefresh();
          this.resetFreshness();
        }
      });
    });

    // The refresh interval alone, so changing it in settings reschedules the timer
    // instead of waiting for the next node selection. `freshness()` reads the new
    // value at once; a timer still on the old one made on-schedule reads look stale.
    // Only rescheduling happens here, never a reset of the freshness history.
    effect(() => {
      this.interval();
      untracked(() => {
        if (this.node() && this.autoRefresh) this.setupAutoRefresh();
      });
    });

    this.ageTicker = setInterval(() => this.now.set(Date.now()), 1000);
  }

  ngOnDestroy(): void {
    this.clearAutoRefresh();
    this.cancelRead();
    if (this.ageTicker) clearInterval(this.ageTicker);
  }

  /** The server profile a node was browsed from; undefined for a node without one. */
  private serverOf(n: TreeNode): ServerProfile | undefined {
    return n.serverId ? this.config.getServer(n.serverId) : undefined;
  }

  private cancelRead(): void {
    this.inflight?.unsubscribe();
    this.inflight = null;
    this.readLoading.set(false);
  }

  private resetFreshness(): void {
    this.lastSuccessAt.set(null);
    this.lastError.set('');
    this.consecutiveFailures.set(0);
  }

  /**
   * Reads the selected node from the server it was browsed from.
   *
   * The node's server used to be left out, so every read went to the legacy
   * single-server URL in settings: a node browsed on one server was read from
   * another, which answered BadNodeIdUnknown or, worse, a different node's value.
   *
   * A timer tick is skipped while a read is still running; a manual Read replaces
   * the running one. Either way at most one read is in flight, so answers cannot
   * arrive out of order.
   */
  readValue(fromTimer = false): void {
    const n = this.node();
    if (!n) return;
    if (fromTimer && this.inflight) return;
    this.cancelRead();

    const server = this.serverOf(n);
    if (n.serverId && !server) {
      // Never fall back to the default server: that is the wrong-server read again.
      this.recordFailure('This server is no longer configured.');
      return;
    }

    this.readLoading.set(true);
    const sub = new Subscription();
    this.inflight = sub;
    const settle = () => {
      if (this.inflight === sub) this.inflight = null;
      this.readLoading.set(false);
    };
    sub.add(this.api.read(n.nodeNs, n.nodeId, n.nodeIdType, server).subscribe({
      next: (result) => {
        if (this.node() !== n) return;
        settle();
        this.readResult.set(result);
        // A transported read whose StatusCode is Bad is not a successful reading.
        // Counting it as fresh would let a server that answers "I can't tell you"
        // keep the card looking live. This used to check readError alone, so a Bad
        // status showed as "3s ago" and never went stale.
        const failure = result.readError
          || (result.statusCode != null && severityOf(result.statusCode) === 'bad'
            ? `The server answered ${statusText(result.statusCode)} (${statusDetail(result.statusCode)}).`
            : '');
        if (failure) {
          this.recordFailure(failure);
        } else {
          this.lastSuccessAt.set(Date.now());
          this.lastError.set('');
          this.consecutiveFailures.set(0);
        }
      },
      error: (err) => {
        if (this.node() !== n) return;
        // The error callback used to only clear the spinner. Recording the
        // failure is what makes staleness visible at all.
        settle();
        this.recordFailure(apiErrorMessage(err, 'The read failed'));
      },
    }));
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
    const interval = this.interval();
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
    this.refreshInterval = setInterval(() => this.readValue(true), this.interval() * 1000);
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
   *
   * Numbers are recognised only when the whole value is one. This used
   * `parseFloat`, which reads a leading number and ignores the rest, so CurrentTime
   * ("2026-11-10 23:…") showed as 2026 and "3 phases" as 3. Integers are shown as
   * sent rather than through Math.round, which keeps the digits of an Int64 the API
   * sends as a string. Booleans and timestamps are shown as what they are.
   */
  formatHeroValue(result: NodeReadResult): string {
    if (result.readError) return 'no reading';
    const val = result.value;
    if (val == null || val === '') return 'empty';
    const type = result.inferredType ?? '';

    let s: string;
    if (typeof val === 'object') {
      s = JSON.stringify(val);
    } else if (type.endsWith('.BooleanDataValue')) {
      const t = String(val).trim().toLowerCase();
      s = t === '1' || t === 'true' ? 'true' : t === '0' || t === 'false' ? 'false' : String(val);
    } else if (type.endsWith('.TimeStampDataValue')) {
      const d = parseIrisUtc(String(val));
      s = d ? localDateTime(d) : String(val);
    } else {
      s = String(val).trim();
      if (INTEGER.test(s)) {
        s = s.replace(/^\+/, '');
      } else if (NUMERIC.test(s)) {
        const num = Number(s);
        // Two decimals, unless that would turn a small non-zero value into 0.00.
        s = num === 0 || Math.abs(num) >= 0.01 ? num.toFixed(2) : num.toPrecision(3);
      }
    }
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
    const n = this.node();
    let cur: TreeNode | null | undefined = n;
    // Guard against a malformed cycle rather than hanging the render.
    for (let i = 0; cur && i < 32; i++) {
      segments.unshift(cur.displayName);
      cur = cur.parentRef;
    }
    // With several servers in the tree, "Objects > Server > LocalTime" does not say
    // which one. The top-level nodes have no parentRef to their server row, so the
    // server's name is added here.
    const server = n ? this.serverOf(n) : undefined;
    if (server?.name) segments.unshift(server.name);
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
    const d = parseIrisUtc(this.readResult()?.sourceTimestamp);
    return d ? localClock(d) : '';
  }

  /**
   * A local clock time, HH:MM:SS, or a dash when there is no timestamp: missing,
   * unparseable, or the OPC UA null DateTime (1601-01-01), which a server sends in
   * full for a node with no timestamp to report.
   *
   * The API sends UTC without an offset; `new Date()` read that as local time, so
   * every timestamp was off by the browser's UTC offset. `parseIrisUtc` reads it as
   * UTC. Milliseconds are dropped deliberately: on a 5-second refresh they are false
   * precision.
   */
  formatTimestamp(ts: string | undefined): string {
    const d = parseIrisUtc(ts);
    return d ? localClock(d) : '—';
  }

  idPrefix(): string {
    const t = this.node()?.nodeIdType ?? 0;
    return ID_TYPES[t]?.prefix ?? '?';
  }

  idTypeName(): string {
    const t = this.node()?.nodeIdType ?? 0;
    return ID_TYPES[t]?.name ?? `Unknown (${t})`;
  }

  /**
   * Whether the node has a value to read. A Property is a Variable in OPC UA (the
   * backend calls a HasProperty child "property"); checking for 'variable' alone
   * told the user that LocalTime, NamespaceArray and every other Property had none.
   */
  private hasValue(): boolean {
    const c = this.node()?.nodeCategory;
    return c === 'variable' || c === 'property';
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
    if (!this.hasValue()) return false;
    return this.severity() === 'good' || this.severity() === 'uncertain';
  }

  dataTypeLabel(): string {
    const r = this.readResult();
    if (!r) return 'not read yet';
    if (!this.hasValue()) return 'not applicable — this node has no value';
    if (!this.dataTypeKnown()) return 'not readable';
    const parts = r.inferredType!.split('.');
    return parts[parts.length - 1].replace('DataValue', '');
  }
}

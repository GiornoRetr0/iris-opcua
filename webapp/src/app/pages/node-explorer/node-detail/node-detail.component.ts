import { Component, input, inject, signal, effect, OnDestroy } from '@angular/core';
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
        <h2 class="text-xl font-semibold mb-2">Select a Node</h2>
        <p class="text-sm text-on-surface-muted">Browse the address space tree on the left to view node details.</p>
      </div>
    } @else {
      <div class="max-w-6xl mx-auto space-y-8">
        <!-- Header Breadcrumb/Title -->
        <div class="flex items-end justify-between">
          <div>
            <nav class="flex items-center gap-2 text-xs font-medium text-on-surface-variant mb-2">
              <span>Objects</span>
              <span class="material-symbols-outlined text-xs">chevron_right</span>
              <span class="text-primary">{{ node()!.displayName }}</span>
            </nav>
            <h1 class="text-2xl font-semibold text-primary">Node Details: {{ node()!.displayName }}</h1>
          </div>
          <div class="flex items-center gap-4">
            <label class="flex items-center gap-2 text-sm font-medium text-on-surface-variant cursor-pointer">
              <input type="checkbox" [(ngModel)]="autoRefresh"
                     (ngModelChange)="onAutoRefreshToggle()"
                     class="rounded border-outline-variant text-primary focus:ring-primary h-4 w-4">
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
            <div class="flex items-baseline gap-4 mt-8">
              @if (readResult()) {
                <span class="text-[120px] font-bold leading-none tracking-tighter text-primary">
                  {{ formatHeroValue(readResult()!) }}
                </span>
                <div class="flex flex-col">
                  <span class="text-2xl font-bold text-tertiary">{{ getUnit() }}</span>
                </div>
              } @else if (readLoading()) {
                <span class="text-4xl font-bold text-on-surface-variant opacity-30">Reading...</span>
              } @else {
                <span class="text-4xl font-bold text-on-surface-variant opacity-30">—</span>
              }
            </div>
            <div class="mt-8 pt-6 border-t border-surface-container">
              <div class="flex gap-12">
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

          <!-- Detailed Properties Grid (3 cards) -->
          <div class="md:col-span-12 grid grid-cols-1 md:grid-cols-3 gap-6">
            <!-- Category -->
            <div class="bg-surface-container-lowest p-6 rounded-xl shadow-sm border border-outline-variant/5">
              <div class="flex items-center gap-3 mb-4">
                <div class="bg-secondary-container/50 p-2 rounded-lg text-primary">
                  <span class="material-symbols-outlined">category</span>
                </div>
                <p class="text-[10px] font-bold text-on-surface-variant uppercase tracking-widest">Category</p>
              </div>
              <p class="text-xl font-bold text-on-surface capitalize">{{ node()!.nodeCategory }}</p>
              <p class="text-xs text-on-surface-variant mt-2">Node Category: {{ node()!.nodeCategory }}</p>
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
              <p class="text-xs text-on-surface-variant mt-2">Reference Type</p>
            </div>
            <!-- Type Definition -->
            <div class="bg-surface-container-lowest p-6 rounded-xl shadow-sm border border-outline-variant/5">
              <div class="flex items-center gap-3 mb-4">
                <div class="bg-secondary-container/50 p-2 rounded-lg text-primary">
                  <span class="material-symbols-outlined">model_training</span>
                </div>
                <p class="text-[10px] font-bold text-on-surface-variant uppercase tracking-widest">Type Definition</p>
              </div>
              <p class="text-xl font-bold text-on-surface">{{ inferredTypeName() }}</p>
              <p class="text-xs text-on-surface-variant mt-2">TypeDef: ns={{ node()!.typeDefNs }}, id={{ node()!.typeDefId }}</p>
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

  constructor() {
    effect(() => {
      const n = this.node();
      if (n) {
        this.readValue();
        this.setupAutoRefresh();
      } else {
        this.clearAutoRefresh();
        this.readResult.set(null);
      }
    });
  }

  ngOnDestroy(): void {
    this.clearAutoRefresh();
  }

  readValue(): void {
    const n = this.node();
    if (!n) return;
    this.readLoading.set(true);
    this.api.read(n.nodeNs, n.nodeId, n.nodeIdType).subscribe({
      next: (result) => {
        this.readResult.set(result);
        this.readLoading.set(false);
      },
      error: () => this.readLoading.set(false),
    });
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

  formatHeroValue(result: NodeReadResult): string {
    if (result.readError) return '!';
    const val = result.value;
    if (val == null || val === '') return '—';
    const num = parseFloat(val);
    if (!isNaN(num)) {
      return num % 1 === 0 ? String(Math.round(num)) : num.toFixed(2);
    }
    return String(val).substring(0, 20);
  }

  getUnit(): string {
    const type = this.readResult()?.inferredType || '';
    if (type.includes('Double') || type.includes('Float')) return '';
    if (type.includes('Int')) return '';
    if (type.includes('Boolean')) return '';
    return '';
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

  get inferredTypeName(): () => string {
    return () => {
      const r = this.readResult();
      if (!r?.inferredType) return '—';
      const parts = r.inferredType.split('.');
      return parts[parts.length - 1].replace('DataValue', '');
    };
  }
}

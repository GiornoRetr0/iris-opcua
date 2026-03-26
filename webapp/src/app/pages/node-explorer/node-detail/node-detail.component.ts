import { Component, input, inject, signal, effect, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { TreeNode, NodeReadResult } from '../../../core/models/opcua.models';
import { ApiService } from '../../../core/services/api.service';
import { ConfigService } from '../../../core/services/config.service';

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
        <p class="text-sm opacity-60">Browse the address space tree on the left to view node details.</p>
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
              <h2 class="text-sm font-medium text-on-surface-variant opacity-60">{{ node()!.displayName }}</h2>
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
                    <span class="h-2 w-2 rounded-full"
                          [class]="readResult()?.readError ? 'bg-error' : 'bg-tertiary'"></span>
                    <span class="text-sm font-bold text-on-surface">
                      {{ readResult()?.readError ? 'Error' : (readResult()?.statusCode === 0 ? 'Good' : (readResult() ? 'Status ' + readResult()!.statusCode : '—')) }}
                    </span>
                  </div>
                </div>
                <div>
                  <p class="text-[10px] font-bold text-on-surface-variant uppercase tracking-widest mb-1">Last Updated</p>
                  <p class="text-sm font-bold text-on-surface">{{ formatTimestamp(readResult()?.serverTimestamp) }}</p>
                </div>
                <div>
                  <p class="text-[10px] font-bold text-on-surface-variant uppercase tracking-widest mb-1">Source Timestamp</p>
                  <p class="text-sm font-bold text-on-surface">{{ readResult()?.sourceTimestamp ? 'Synchronized' : '—' }}</p>
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
                  <p class="text-[10px] text-on-primary-container uppercase font-bold tracking-widest opacity-60">Node ID</p>
                  <p class="text-lg font-mono font-medium truncate">ns={{ node()!.nodeNs }};{{ idPrefix() }}={{ node()!.nodeId }}</p>
                </div>
                <div>
                  <p class="text-[10px] text-on-primary-container uppercase font-bold tracking-widest opacity-60">Namespace</p>
                  <p class="text-md font-medium">{{ node()!.nodeNs }}</p>
                </div>
                <div>
                  <p class="text-[10px] text-on-primary-container uppercase font-bold tracking-widest opacity-60">ID Type</p>
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

          <!-- Telemetry Stream -->
          <div class="md:col-span-12 bg-white/40 backdrop-blur-md rounded-xl p-8 border border-white/20">
            <div class="flex items-center justify-between mb-6">
              <h3 class="text-sm font-bold text-primary uppercase tracking-widest">Telemetry Stream</h3>
              <div class="flex gap-2">
                <span class="w-2 h-2 rounded-full bg-tertiary"></span>
                <span class="w-2 h-2 rounded-full bg-tertiary opacity-40"></span>
                <span class="w-2 h-2 rounded-full bg-tertiary opacity-40"></span>
              </div>
            </div>
            <div class="h-48 w-full bg-surface-container-low rounded-lg relative flex items-center justify-center">
              <div class="absolute inset-0 opacity-10 pointer-events-none"
                   style="background-image: radial-gradient(circle at 2px 2px, #131c79 1px, transparent 0); background-size: 24px 24px;"></div>
              <!-- Bar visualization from history -->
              <div class="w-full h-full px-8 py-4 flex items-end justify-between gap-1">
                @for (val of telemetryBars(); track $index) {
                  <div class="w-full rounded-t-sm transition-all duration-300"
                       [style.height.%]="val"
                       [style.opacity]="0.1 + (val / 100) * 0.9"
                       class="bg-primary"></div>
                }
              </div>
              <p class="absolute bottom-4 left-1/2 -translate-x-1/2 text-[10px] font-bold text-on-surface-variant uppercase tracking-widest">
                Real-time sampling: {{ config.get().autoRefreshInterval }}s intervals
              </p>
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
  telemetryBars = signal<number[]>(Array(10).fill(20));
  private telemetryHistory: number[] = [];

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
        this.pushTelemetry(result.value);
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

  private pushTelemetry(value: any): void {
    const num = parseFloat(value);
    if (isNaN(num)) return;
    this.telemetryHistory.push(num);
    if (this.telemetryHistory.length > 10) this.telemetryHistory.shift();
    const max = Math.max(...this.telemetryHistory, 1);
    this.telemetryBars.set(
      this.telemetryHistory.map((v) => Math.max(10, (Math.abs(v) / max) * 100))
    );
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

  formatTimestamp(ts: string | undefined): string {
    if (!ts) return '—';
    try {
      const d = new Date(ts);
      return d.toLocaleTimeString('en-US', { hour12: false, fractionalSecondDigits: 3 });
    } catch {
      return ts;
    }
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

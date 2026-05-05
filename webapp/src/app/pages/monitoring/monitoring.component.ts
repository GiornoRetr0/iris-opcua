import { Component, OnDestroy, OnInit, computed, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ApiService } from '../../core/services/api.service';
import { ConfigService } from '../../core/services/config.service';
import { Metric, MetricsSnapshot } from '../../core/models/opcua.models';

interface PipelineHealth {
  name: string;
  enabled: boolean | null;
  running: boolean | null;
  rowSources: number | null;
  columns: number | null;
  rows: number | null;
  interopMessages: number | null;
  interopQueued: number | null;
  interopErrors: number | null;
  lastActivity: number | null;
}

@Component({
  selector: 'app-monitoring',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="p-8 max-w-7xl mx-auto">
      <!-- Page Header -->
      <div class="flex justify-between items-end mb-10">
        <div class="space-y-1">
          <h1 class="text-3xl font-semibold text-primary tracking-tight">Monitoring</h1>
          <p class="text-on-surface-variant">
            Live IRIS instance health and per-pipeline OPC UA metrics.
            @if (snapshot(); as snap) {
              <span class="text-xs text-slate-500 ml-2">Last scrape: {{ snap.scrapedAt }}</span>
            }
          </p>
        </div>
        <div class="flex gap-3">
          <button (click)="refresh()"
                  class="px-4 py-2 rounded-lg bg-white border border-slate-200/80 text-xs font-bold uppercase tracking-wider text-slate-600 hover:text-primary hover:border-primary/30 transition-all flex items-center gap-2"
                  [disabled]="loading()">
            <span class="material-symbols-outlined text-base"
                  [class.animate-spin]="loading()">refresh</span>
            Refresh
          </button>
        </div>
      </div>

      @if (error(); as err) {
        <div class="mb-6 p-4 rounded-xl bg-red-50 border border-red-200 text-red-800 text-sm flex items-start gap-3">
          <span class="material-symbols-outlined text-red-500">error</span>
          <div>
            <p class="font-semibold">Metrics endpoint unavailable</p>
            <p class="text-xs mt-1 text-red-700">{{ err }}</p>
          </div>
        </div>
      }

      <!-- System Health Strip -->
      <div class="grid grid-cols-1 md:grid-cols-4 gap-6 mb-10">
        <div class="bg-white p-6 rounded-2xl shadow-[0_2px_12px_-2px_rgba(19,28,121,0.08),0_4px_6px_-2px_rgba(19,28,121,0.04)] border border-slate-200/60 relative overflow-hidden group">
          <span class="material-symbols-outlined absolute right-4 top-1/2 -translate-y-1/2 opacity-40 text-slate-300/40" style="font-size:80px">speed</span>
          <div class="relative z-10">
            <div class="text-[0.65rem] font-bold text-slate-400 uppercase tracking-widest mb-3">CPU Usage</div>
            <div class="flex items-baseline gap-2">
              <span class="text-4xl font-black text-primary">{{ formatPercent(cpuUsage()) }}</span>
              <span class="text-sm font-bold text-slate-400">%</span>
            </div>
          </div>
        </div>

        <div class="bg-white p-6 rounded-2xl shadow-[0_2px_12px_-2px_rgba(19,28,121,0.08),0_4px_6px_-2px_rgba(19,28,121,0.04)] border border-slate-200/60 relative overflow-hidden group">
          <span class="material-symbols-outlined absolute right-4 top-1/2 -translate-y-1/2 opacity-40 text-emerald-400/30" style="font-size:80px">monitor_heart</span>
          <div class="relative z-10">
            <div class="text-[0.65rem] font-bold text-slate-400 uppercase tracking-widest mb-3">IRIS State</div>
            <div class="flex items-baseline gap-2">
              <span class="text-4xl font-black" [class]="stateColor(irisState())">{{ stateLabel(irisState()) }}</span>
            </div>
          </div>
        </div>

        <div class="bg-white p-6 rounded-2xl shadow-[0_2px_12px_-2px_rgba(19,28,121,0.08),0_4px_6px_-2px_rgba(19,28,121,0.04)] border border-slate-200/60 relative overflow-hidden group">
          <span class="material-symbols-outlined absolute right-4 top-1/2 -translate-y-1/2 opacity-40 text-primary/20" style="font-size:80px">database</span>
          <div class="relative z-10">
            <div class="text-[0.65rem] font-bold text-slate-400 uppercase tracking-widest mb-3">Total DB Size</div>
            <div class="flex items-baseline gap-2">
              <span class="text-4xl font-black text-primary">{{ formatMb(totalDbMb()) }}</span>
              <span class="text-sm font-bold text-slate-400">MB</span>
            </div>
          </div>
        </div>

        <div class="bg-white p-6 rounded-2xl shadow-[0_2px_12px_-2px_rgba(19,28,121,0.08),0_4px_6px_-2px_rgba(19,28,121,0.04)] border border-slate-200/60 relative overflow-hidden group">
          <span class="material-symbols-outlined absolute right-4 top-1/2 -translate-y-1/2 opacity-40 text-amber-400/30" style="font-size:80px">warning</span>
          <div class="relative z-10">
            <div class="text-[0.65rem] font-bold text-slate-400 uppercase tracking-widest mb-3">System Alerts</div>
            <div class="flex items-baseline gap-2">
              <span class="text-4xl font-black text-amber-500">{{ alertsCount() }}</span>
              <span class="text-sm font-bold text-amber-500/60">Total</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Pipeline Cards -->
      <div class="mb-10">
        <h2 class="text-sm font-bold text-slate-500 uppercase tracking-widest mb-4">Pipelines ({{ pipelineHealth().length }})</h2>

        @if (pipelineHealth().length === 0 && !loading()) {
          <div class="bg-white rounded-2xl border border-slate-200/60 p-10 text-center text-on-surface-variant">
            <span class="material-symbols-outlined text-6xl opacity-20">account_tree</span>
            <p class="mt-3 text-sm">No pipelines deployed yet.</p>
          </div>
        }

        <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-6">
          @for (p of pipelineHealth(); track p.name) {
            <div class="bg-white p-6 rounded-2xl shadow-[0_2px_12px_-2px_rgba(19,28,121,0.08),0_4px_6px_-2px_rgba(19,28,121,0.04)] border border-slate-200/60">
              <div class="flex items-start justify-between mb-4">
                <div class="min-w-0">
                  <p class="text-xs font-bold text-slate-400 uppercase tracking-widest mb-1">Pipeline</p>
                  <p class="text-lg font-bold text-primary truncate" [title]="p.name">{{ p.name }}</p>
                </div>
                <span class="shrink-0 inline-flex items-center gap-1 px-2 py-1 rounded-md text-[10px] font-bold uppercase tracking-wider"
                      [class]="p.running
                        ? 'bg-emerald-50 text-emerald-700'
                        : (p.enabled ? 'bg-amber-50 text-amber-700' : 'bg-slate-100 text-slate-500')">
                  <span class="w-1.5 h-1.5 rounded-full"
                        [class]="p.running ? 'bg-emerald-500' : (p.enabled ? 'bg-amber-500' : 'bg-slate-400')"></span>
                  {{ p.running ? 'Running' : (p.enabled ? 'Enabled' : 'Stopped') }}
                </span>
              </div>

              <div class="grid grid-cols-3 gap-3 mb-4">
                <div>
                  <div class="text-[0.6rem] font-bold text-slate-400 uppercase tracking-widest">Devices</div>
                  <div class="text-xl font-black text-primary mt-0.5">{{ p.rowSources ?? '—' }}</div>
                </div>
                <div>
                  <div class="text-[0.6rem] font-bold text-slate-400 uppercase tracking-widest">Columns</div>
                  <div class="text-xl font-black text-primary mt-0.5">{{ p.columns ?? '—' }}</div>
                </div>
                <div>
                  <div class="text-[0.6rem] font-bold text-slate-400 uppercase tracking-widest">Rows</div>
                  <div class="text-xl font-black text-primary mt-0.5">{{ p.rows ?? '—' }}</div>
                </div>
              </div>

              <div class="border-t border-slate-100 pt-4 space-y-2">
                <div class="flex justify-between text-xs">
                  <span class="text-slate-500">Messages processed</span>
                  <span class="font-bold text-slate-800">{{ p.interopMessages ?? '—' }}</span>
                </div>
                <div class="flex justify-between text-xs">
                  <span class="text-slate-500">Queued</span>
                  <span class="font-bold"
                        [class]="(p.interopQueued ?? 0) > 0 ? 'text-amber-600' : 'text-slate-800'">
                    {{ p.interopQueued ?? '—' }}
                  </span>
                </div>
                <div class="flex justify-between text-xs">
                  <span class="text-slate-500">Errored</span>
                  <span class="font-bold"
                        [class]="(p.interopErrors ?? 0) > 0 ? 'text-red-600' : 'text-slate-800'">
                    {{ p.interopErrors ?? '—' }}
                  </span>
                </div>
              </div>
            </div>
          }
        </div>
      </div>

      <!-- Raw metrics table -->
      <div class="bg-white rounded-2xl border border-slate-200/60 overflow-hidden">
        <button (click)="showRaw.set(!showRaw())"
                class="w-full px-6 py-4 flex items-center justify-between hover:bg-slate-50/80 transition-colors">
          <div class="flex items-center gap-3">
            <span class="material-symbols-outlined text-slate-500">data_table</span>
            <span class="text-sm font-bold text-slate-700">Raw metrics ({{ filteredMetrics().length }})</span>
          </div>
          <span class="material-symbols-outlined text-slate-400"
                [class]="showRaw() ? 'rotate-180' : ''" style="transition: transform 0.2s">expand_more</span>
        </button>

        @if (showRaw()) {
          <div class="px-6 pb-6 border-t border-slate-100">
            <input type="text" [value]="filter()" (input)="filter.set($any($event.target).value)"
                   placeholder="Filter by name or label…"
                   class="w-full mt-4 mb-4 px-3 py-2 rounded-lg border border-slate-200 text-sm font-mono focus:outline-none focus:border-primary" />
            <div class="max-h-[500px] overflow-auto rounded-lg border border-slate-100">
              <table class="w-full text-xs font-mono">
                <thead class="bg-slate-50 sticky top-0">
                  <tr>
                    <th class="text-left px-4 py-2 font-bold text-slate-500 uppercase tracking-wider">Name</th>
                    <th class="text-left px-4 py-2 font-bold text-slate-500 uppercase tracking-wider">Labels</th>
                    <th class="text-right px-4 py-2 font-bold text-slate-500 uppercase tracking-wider">Value</th>
                  </tr>
                </thead>
                <tbody>
                  @for (m of filteredMetrics(); track $index) {
                    <tr class="border-t border-slate-100 hover:bg-slate-50/50">
                      <td class="px-4 py-1.5 text-slate-700"
                          [class.text-primary]="m.name.startsWith('opcua_')">{{ m.name }}</td>
                      <td class="px-4 py-1.5 text-slate-500">{{ formatLabels(m.labels) }}</td>
                      <td class="px-4 py-1.5 text-right text-slate-900 font-semibold">{{ m.value ?? '—' }}</td>
                    </tr>
                  }
                </tbody>
              </table>
            </div>
          </div>
        }
      </div>
    </div>
  `,
})
export class MonitoringComponent implements OnInit, OnDestroy {
  private api = inject(ApiService);
  private config = inject(ConfigService);

  snapshot = signal<MetricsSnapshot | null>(null);
  loading = signal(false);
  error = signal<string | null>(null);
  showRaw = signal(false);
  filter = signal('');

  private pollTimer: any;

  metrics = computed(() => this.snapshot()?.metrics ?? []);

  cpuUsage = computed(() => this.findMetric('iris_cpu_usage')?.value ?? null);
  irisState = computed(() => this.findMetric('iris_system_state')?.value ?? null);
  alertsCount = computed(() => this.findMetric('iris_system_alerts_log')?.value ?? 0);
  totalDbMb = computed(() => {
    let sum = 0;
    let any = false;
    for (const m of this.metrics()) {
      if (m.name === 'iris_db_size_mb' && m.value != null) {
        sum += m.value;
        any = true;
      }
    }
    return any ? sum : null;
  });

  pipelineHealth = computed<PipelineHealth[]>(() => {
    const byName: Record<string, PipelineHealth> = {};

    const ensure = (name: string): PipelineHealth => {
      if (!byName[name]) {
        byName[name] = {
          name,
          enabled: null,
          running: null,
          rowSources: null,
          columns: null,
          rows: null,
          interopMessages: null,
          interopQueued: null,
          interopErrors: null,
          lastActivity: null,
        };
      }
      return byName[name];
    };

    // Pass 1: register pipelines only from opcua_* metrics (real OPC UA pipelines)
    for (const m of this.metrics()) {
      if (!m.name.startsWith('opcua_')) continue;
      const name = m.labels['id'] || m.labels['pipeline'];
      if (!name) continue;
      const p = ensure(name);
      if (m.name === 'opcua_pipeline_enabled') p.enabled = !!m.value;
      else if (m.name === 'opcua_pipeline_running') p.running = !!m.value;
      else if (m.name === 'opcua_pipeline_rowsources') p.rowSources = m.value;
      else if (m.name === 'opcua_pipeline_columns') p.columns = m.value;
      else if (m.name === 'opcua_pipeline_rows') p.rows = m.value;
    }

    // Pass 2: enrich with iris_interop_* but only for pipelines we already know about
    for (const m of this.metrics()) {
      if (!m.name.startsWith('iris_interop_')) continue;
      const host = m.labels['host'];
      if (!host || !byName[host]) continue;
      const p = byName[host];
      if (m.name === 'iris_interop_messages') p.interopMessages = m.value;
      else if (m.name === 'iris_interop_queued') p.interopQueued = m.value;
      else if (m.name === 'iris_interop_messages_errored') p.interopErrors = m.value;
      else if (m.name === 'iris_interop_last_activity') p.lastActivity = m.value;
    }

    return Object.values(byName).sort((a, b) => a.name.localeCompare(b.name));
  });

  filteredMetrics = computed(() => {
    const f = this.filter().toLowerCase().trim();
    if (!f) return this.metrics();
    return this.metrics().filter(
      (m) =>
        m.name.toLowerCase().includes(f) ||
        Object.entries(m.labels).some(
          ([k, v]) => k.toLowerCase().includes(f) || v.toLowerCase().includes(f)
        )
    );
  });

  ngOnInit(): void {
    this.refresh();
    const intervalMs = (this.config.get().autoRefreshInterval || 5) * 1000;
    this.pollTimer = setInterval(() => this.refresh(), intervalMs);
  }

  ngOnDestroy(): void {
    if (this.pollTimer) clearInterval(this.pollTimer);
  }

  refresh(): void {
    if (this.loading()) return;
    this.loading.set(true);
    this.api.getMetrics().subscribe({
      next: (snap) => {
        this.snapshot.set(snap);
        this.error.set(null);
        this.loading.set(false);
      },
      error: (err) => {
        this.error.set(err?.message || String(err));
        this.loading.set(false);
      },
    });
  }

  private findMetric(name: string): Metric | undefined {
    return this.metrics().find((m) => m.name === name);
  }

  formatPercent(v: number | null): string {
    if (v == null) return '—';
    return v.toFixed(1);
  }

  formatMb(v: number | null): string {
    if (v == null) return '—';
    if (v >= 1024) return (v / 1024).toFixed(1) + 'k';
    return v.toFixed(0);
  }

  stateLabel(v: number | null): string {
    // 0 OK, 1 Warning, 2 Alert, 3 Fatal (per IRIS System Monitor Health State)
    if (v == null) return '—';
    if (v === 0) return 'OK';
    if (v === 1) return 'Warn';
    if (v === 2) return 'Alert';
    return 'Fatal';
  }

  stateColor(v: number | null): string {
    if (v == null) return 'text-slate-400';
    if (v === 0) return 'text-emerald-600';
    if (v === 1) return 'text-amber-500';
    return 'text-red-600';
  }

  formatLabels(labels: Record<string, string>): string {
    const entries = Object.entries(labels);
    if (!entries.length) return '';
    return entries.map(([k, v]) => `${k}="${v}"`).join(', ');
  }
}

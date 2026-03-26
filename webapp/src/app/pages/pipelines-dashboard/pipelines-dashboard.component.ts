import { Component, inject, signal, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';
import { ApiService } from '../../core/services/api.service';
import { ConfigService } from '../../core/services/config.service';
import { Pipeline } from '../../core/models/opcua.models';

@Component({
  selector: 'app-pipelines-dashboard',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="p-8 max-w-7xl mx-auto">
      <!-- Page Header -->
      <div class="flex justify-between items-end mb-10">
        <div class="space-y-1">
          <h1 class="text-3xl font-semibold text-primary tracking-tight">Pipelines</h1>
          <p class="text-on-surface-variant">Monitor and orchestrate your OPC UA data streams in real-time.</p>
        </div>
        <div class="flex gap-3">
          <div class="flex bg-surface-container p-1 rounded-lg">
            <button (click)="activeFilter.set('active')"
                    class="px-4 py-1.5 rounded-md text-xs font-bold uppercase tracking-wider transition-all"
                    [class]="activeFilter() === 'active' ? 'bg-surface-container-lowest text-primary shadow-sm' : 'text-on-surface-variant hover:text-primary'">
              Active
            </button>
            <button (click)="activeFilter.set('archived')"
                    class="px-4 py-1.5 rounded-md text-xs font-bold uppercase tracking-wider transition-all"
                    [class]="activeFilter() === 'archived' ? 'bg-surface-container-lowest text-primary shadow-sm' : 'text-on-surface-variant hover:text-primary'">
              Archived
            </button>
          </div>
        </div>
      </div>

      <!-- Dashboard Stats Grid -->
      <div class="grid grid-cols-1 md:grid-cols-4 gap-6 mb-12">
        <div class="bg-surface-container-lowest p-6 rounded-xl shadow-sm border border-outline-variant/10">
          <div class="text-[0.65rem] font-bold text-on-surface-variant uppercase tracking-[0.15em] mb-2">Total Pipelines</div>
          <div class="flex items-baseline gap-2">
            <span class="text-3xl font-bold text-primary">{{ pipelines().length }}</span>
            <span class="text-sm font-medium text-on-surface-variant">Total</span>
          </div>
        </div>
        <div class="bg-surface-container-lowest p-6 rounded-xl shadow-sm border border-outline-variant/10">
          <div class="text-[0.65rem] font-bold text-on-surface-variant uppercase tracking-[0.15em] mb-2">Running Streams</div>
          <div class="flex items-baseline gap-2">
            <span class="text-3xl font-bold text-tertiary">{{ runningCount() }}</span>
            <span class="text-sm font-medium text-on-surface-variant">Active</span>
          </div>
        </div>
        <div class="bg-surface-container-lowest p-6 rounded-xl shadow-sm border border-outline-variant/10">
          <div class="text-[0.65rem] font-bold text-on-surface-variant uppercase tracking-[0.15em] mb-2">Error Warnings</div>
          <div class="flex items-baseline gap-2">
            <span class="text-3xl font-bold text-error">{{ errorCount() }}</span>
            <span class="text-sm font-medium text-on-surface-variant">Pending</span>
          </div>
        </div>
        <div class="bg-surface-container-lowest p-6 rounded-xl shadow-sm border border-outline-variant/10">
          <div class="text-[0.65rem] font-bold text-on-surface-variant uppercase tracking-[0.15em] mb-2">Stopped</div>
          <div class="flex items-baseline gap-2">
            <span class="text-3xl font-bold text-primary">{{ stoppedCount() }}</span>
            <span class="text-sm font-medium text-on-surface-variant">Inactive</span>
          </div>
        </div>
      </div>

      <!-- Pipeline Cards -->
      <div class="space-y-6">
        @if (loading()) {
          <div class="flex items-center justify-center py-20 text-on-surface-variant">
            <span class="material-symbols-outlined text-2xl animate-spin mr-3">progress_activity</span>
            Loading pipelines...
          </div>
        }

        @if (!loading() && pipelines().length === 0) {
          <div class="flex flex-col items-center justify-center py-20 text-on-surface-variant">
            <span class="material-symbols-outlined text-8xl opacity-10 mb-4">account_tree</span>
            <h2 class="text-xl font-semibold mb-2">No Pipelines Yet</h2>
            <p class="text-sm opacity-60 mb-6">Deploy your first pipeline to start monitoring OPC UA data.</p>
            <button (click)="createPipeline()"
                    class="px-6 py-3 bg-primary text-on-primary font-bold rounded-lg shadow-xl shadow-primary/30 flex items-center gap-2 hover:brightness-110 active:scale-95 transition-all">
              <span class="material-symbols-outlined">add</span>
              Create Pipeline
            </button>
          </div>
        }

        @for (pipeline of pipelines(); track pipeline.name) {
          <!-- Pipeline Card -->
          <div class="group rounded-xl p-6 shadow-sm hover:shadow-md transition-shadow"
               [class]="isStopped(pipeline)
                 ? 'bg-surface-container-low/50 border border-outline-variant/5 hover:border-outline-variant/20 opacity-80 hover:opacity-100'
                 : 'bg-surface-container-lowest border border-outline-variant/10'">

            <!-- Card Header: title + status + actions -->
            <div class="flex items-start justify-between mb-8">
              <div class="flex items-center gap-4">
                <div class="h-12 w-12 rounded-lg flex items-center justify-center"
                     [class]="getStatusIconBg(pipeline)">
                  <span class="material-symbols-outlined text-2xl">{{ getStatusIcon(pipeline) }}</span>
                </div>
                <div>
                  <h3 class="text-lg font-semibold"
                      [class]="isStopped(pipeline) ? 'text-primary opacity-60' : 'text-primary'">{{ pipeline.name }}</h3>
                  <div class="flex items-center gap-2">
                    <span class="w-2 h-2 rounded-full" [class]="getStatusDotClass(pipeline)"></span>
                    <span class="text-xs font-bold uppercase tracking-widest" [class]="getStatusTextClass(pipeline)">
                      {{ getStatusLabel(pipeline) }}
                    </span>
                    @if (pipeline.mode) {
                      <span class="text-xs text-on-surface-variant ml-2">{{ pipeline.mode }}</span>
                    }
                  </div>
                </div>
              </div>
              <div class="flex items-center gap-2">
                @if (isRunning(pipeline)) {
                  <button (click)="togglePipeline(pipeline)"
                          class="p-2 text-on-surface-variant hover:text-error transition-colors rounded-lg hover:bg-error-container/20">
                    <span class="material-symbols-outlined">stop_circle</span>
                  </button>
                } @else {
                  <button (click)="togglePipeline(pipeline)"
                          class="p-2 text-on-surface-variant hover:text-tertiary transition-colors rounded-lg hover:bg-tertiary-fixed/20">
                    <span class="material-symbols-outlined">play_circle</span>
                  </button>
                }
                <button (click)="editPipeline(pipeline)"
                        class="p-2 text-on-surface-variant hover:text-primary transition-colors rounded-lg hover:bg-primary-fixed/20">
                  <span class="material-symbols-outlined">edit_square</span>
                </button>
                @if (isStopped(pipeline)) {
                  <button (click)="deletePipeline(pipeline)"
                          class="p-2 text-on-surface-variant hover:text-error transition-colors rounded-lg hover:bg-error-container/20">
                    <span class="material-symbols-outlined">delete</span>
                  </button>
                }
                <button class="p-2 text-on-surface-variant hover:text-on-surface transition-colors">
                  <span class="material-symbols-outlined">more_vert</span>
                </button>
              </div>
            </div>

            <!-- ═══ Flow Visualization (3-box: Nodes → Service → Table) ═══ -->
            <div class="flex justify-center mb-6"
                 [style.filter]="isStopped(pipeline) ? 'grayscale(1)' : 'none'"
                 [style.opacity]="isStopped(pipeline) ? '0.4' : '1'">
              <div class="inline-grid grid-cols-[auto_1fr_auto_1fr_auto] items-center gap-0 w-[85%] mx-auto">

                <!-- Left box: NODES -->
                <div class="relative z-10">
                  <div class="bg-tertiary-fixed/10 border border-tertiary-fixed-dim/20 rounded-lg px-6 py-4 text-center min-w-[120px]">
                    <p class="text-[0.55rem] font-bold text-on-surface-variant uppercase tracking-widest mb-1">Nodes</p>
                    <p class="text-2xl font-bold text-primary leading-tight">{{ getNodeCount(pipeline) }}</p>
                    @if (getNodeNames(pipeline)) {
                      <p class="text-[10px] text-on-surface-variant truncate max-w-[100px] mt-0.5">{{ getNodeNames(pipeline) }}</p>
                    }
                  </div>
                </div>

                <!-- Left connector -->
                <div class="relative h-[2px] w-full bg-tertiary-fixed-dim/30 self-center overflow-hidden">
                  <div class="flow-dot absolute top-1/2 -translate-y-1/2 w-2 h-2 rounded-full bg-tertiary-fixed-dim"></div>
                </div>

                <!-- Center box: SERVICE (blue) -->
                <div class="relative z-10">
                  <div class="rounded-lg px-6 py-4 text-center shadow-lg min-w-[170px]"
                       [class]="isRunning(pipeline)
                         ? 'bg-primary text-on-primary border border-primary-container'
                         : 'bg-primary/80 text-on-primary border border-primary-container'">
                    <p class="text-[0.55rem] font-bold uppercase tracking-widest mb-0.5 opacity-70">Service</p>
                    <p class="text-sm font-bold">{{ pipeline.name }}</p>
                    <p class="text-[10px] mt-0.5 opacity-70">{{ getIntervalLabel(pipeline) }}</p>
                  </div>
                </div>

                <!-- Right connector -->
                <div class="relative h-[2px] w-full bg-tertiary-fixed-dim/30 self-center overflow-hidden">
                  <div class="flow-dot absolute top-1/2 -translate-y-1/2 w-2 h-2 rounded-full bg-tertiary-fixed-dim"></div>
                </div>

                <!-- Right box: TABLE -->
                <div class="relative z-10">
                  <div class="bg-tertiary-fixed/10 border border-tertiary-fixed-dim/20 rounded-lg px-6 py-4 text-center min-w-[120px]">
                    <p class="text-[0.55rem] font-bold text-on-surface-variant uppercase tracking-widest mb-1">Table</p>
                    <p class="text-xs font-semibold text-primary truncate max-w-[180px]">{{ getTableName(pipeline) }}</p>
                  </div>
                </div>

              </div>
            </div>

            <!-- v2 Row Sources -->
            @if (pipeline.pipelineVersion === 2 && pipeline.rowSources?.length) {
              <div class="flex items-center gap-2 mb-4 px-2">
                <span class="material-symbols-outlined text-sm text-amber-600">device_hub</span>
                <span class="text-xs font-bold text-on-surface-variant">{{ pipeline.rowSources!.length }} row source{{ pipeline.rowSources!.length !== 1 ? 's' : '' }}</span>
                <span class="text-[10px] text-on-surface-variant font-mono truncate">
                  {{ getRowSourcePaths(pipeline) }}
                </span>
              </div>
            }

            <!-- Footer: server URL + metrics -->
            <div class="flex items-center justify-between pt-4 border-t border-outline-variant/10">
              <div class="flex items-center gap-2 text-on-surface-variant">
                <span class="material-symbols-outlined text-sm">language</span>
                <span class="text-xs font-medium">{{ getServerUrl(pipeline) }}</span>
              </div>
              <div class="flex items-center gap-6">
                <div class="space-y-0.5 text-right">
                  <div class="text-[0.6rem] font-bold text-on-surface-variant uppercase tracking-widest">Rows</div>
                  <div class="text-sm font-semibold" [class]="isStopped(pipeline) ? 'text-primary opacity-40' : 'text-primary'">
                    {{ pipeline.rowCount != null ? pipeline.rowCount : '—' }}
                  </div>
                </div>
                <div class="space-y-0.5 text-right">
                  <div class="text-[0.6rem] font-bold text-on-surface-variant uppercase tracking-widest">Frequency</div>
                  <div class="text-sm font-semibold" [class]="isStopped(pipeline) ? 'text-primary opacity-40' : 'text-primary'">
                    {{ getIntervalLabel(pipeline) }}
                  </div>
                </div>
                <div class="space-y-0.5 text-right">
                  <div class="text-[0.6rem] font-bold text-on-surface-variant uppercase tracking-widest">Last Activity</div>
                  <div class="text-sm font-semibold" [class]="isStopped(pipeline) ? 'text-primary opacity-40' : 'text-primary'">
                    {{ pipeline.lastActivity || '—' }}
                  </div>
                </div>
              </div>
            </div>
          </div>
        }
      </div>
    </div>

    <!-- FAB -->
    <div class="fixed bottom-10 right-10 z-50">
      <button (click)="createPipeline()"
              class="flex items-center gap-2.5 bg-primary text-on-primary pl-3.5 pr-5 py-3 rounded-full shadow-[0_20px_40px_rgba(19,28,121,0.25)] hover:shadow-[0_25px_50px_rgba(19,28,121,0.35)] transition-all transform active:scale-95">
        <span class="material-symbols-outlined bg-on-primary text-primary h-7 w-7 flex items-center justify-center rounded-full text-lg leading-none">add</span>
        <span class="font-bold text-sm tracking-wide">Create New Pipeline</span>
      </button>
    </div>
  `,
})
export class PipelinesDashboardComponent implements OnInit {
  private api = inject(ApiService);
  private router = inject(Router);
  config = inject(ConfigService);

  pipelines = signal<Pipeline[]>([]);
  loading = signal(false);
  activeFilter = signal<'active' | 'archived'>('active');

  runningCount = signal(0);
  errorCount = signal(0);
  stoppedCount = signal(0);

  ngOnInit(): void {
    this.loadPipelines();
  }

  loadPipelines(): void {
    this.loading.set(true);
    this.api.listPipelines().subscribe({
      next: (pipelines) => {
        this.pipelines.set(pipelines);
        this.runningCount.set(pipelines.filter((p) => this.isRunning(p)).length);
        this.errorCount.set(pipelines.filter((p) => p.status === 'error' || p.status === 'warning').length);
        this.stoppedCount.set(pipelines.filter((p) => this.isStopped(p)).length);
        this.loading.set(false);
      },
      error: () => {
        this.loading.set(false);
        this.pipelines.set([]);
      },
    });
  }

  createPipeline(): void {
    this.router.navigate(['/pipelines/new']);
  }

  togglePipeline(pipeline: Pipeline): void {
    this.api.togglePipeline(pipeline.name).subscribe({
      next: () => this.loadPipelines(),
    });
  }

  editPipeline(pipeline: Pipeline): void {
    this.router.navigate(['/pipelines/edit', pipeline.name]);
  }

  deletePipeline(pipeline: Pipeline): void {
    if (!confirm(`Delete pipeline "${pipeline.name}"?`)) return;
    this.api.deletePipeline(pipeline.name).subscribe({
      next: () => this.loadPipelines(),
    });
  }

  /** API returns: enabled=1/0, running=1/0 */
  isRunning(p: Pipeline): boolean {
    const r: any = (p as any).running;
    if (r === 1 || r === true || r === '1') return true;
    const e: any = p.enabled;
    if (e === 1 || e === true || e === '1') return true;
    return false;
  }

  isStopped(p: Pipeline): boolean {
    return !this.isRunning(p);
  }

  getStatusIcon(p: Pipeline): string {
    if (this.isRunning(p)) return 'sync_alt';
    if (p.status === 'warning') return 'warning';
    if (p.status === 'error') return 'error';
    return 'pause_circle';
  }

  getStatusIconBg(p: Pipeline): string {
    if (this.isRunning(p)) return 'bg-tertiary-fixed/20 text-tertiary';
    if (p.status === 'warning' || p.status === 'error') return 'bg-error-container/10 text-error';
    return 'bg-surface-container-highest text-on-surface-variant';
  }

  getStatusDotClass(p: Pipeline): string {
    if (this.isRunning(p)) return 'bg-tertiary';
    if (p.status === 'warning') return 'bg-error animate-pulse';
    if (p.status === 'error') return 'bg-error';
    return 'bg-on-surface-variant/40';
  }

  getStatusTextClass(p: Pipeline): string {
    if (this.isRunning(p)) return 'text-tertiary';
    if (p.status === 'warning' || p.status === 'error') return 'text-error';
    return 'text-on-surface-variant';
  }

  getStatusLabel(p: Pipeline): string {
    if (this.isRunning(p)) return 'Running';
    if (p.status === 'warning') return 'Warning';
    if (p.status === 'error') return 'Error';
    if (this.isStopped(p)) return 'Stopped';
    return p.status || 'Unknown';
  }

  /** Derive a source label from pipeline name (e.g. "from-PLC-SA1" → "PLC_SA1") */
  getSourceLabel(p: Pipeline): string {
    const name = p.name || '';
    const cleaned = name.replace(/^from[-_]/i, '').replace(/-/g, '_');
    return cleaned.substring(0, 16).toUpperCase();
  }

  getServiceIcon(p: Pipeline): string {
    if (p.mode === 'subscription') return 'sync_alt';
    return 'terminal';
  }

  getServiceLabel(p: Pipeline): string {
    if (p.mode === 'subscription') return 'Subscription Svc';
    return 'Polling Service';
  }

  /** Extract node count — API may return nodes as number, array, or object */
  getNodeCount(p: Pipeline): number {
    const n: any = p.nodes;
    if (n == null) return 1;
    if (typeof n === 'number') return n;
    if (Array.isArray(n)) return n.length;
    if (typeof n === 'object') {
      if (n.count != null) return n.count;
      return Object.keys(n).length || 1;
    }
    return 1;
  }

  /** Extract node names — API returns nodes: [{property: "SA1", nodeId: "SA1"}] */
  getNodeNames(p: Pipeline): string {
    const n: any = p.nodes;
    if (Array.isArray(n)) {
      return n.map((item: any) => item?.property || item?.nodeId || item?.displayName || item?.name || '').filter(Boolean).join(', ');
    }
    return '';
  }

  /** API returns: tableName, dataSourceClass, className */
  getTableName(p: Pipeline): string {
    return (p as any).tableName || (p as any).dataSourceClass || p.dataSourceName || p.className || '—';
  }

  /** API returns: url = "opc.tcp://plc:4840" */
  getServerUrl(p: Pipeline): string {
    return (p as any).url || p.serverUrl || this.config.get().serverUrl || '—';
  }

  getRowSourcePaths(p: Pipeline): string {
    return (p.rowSources || []).map((rs) => rs.path).join(', ');
  }

  /** API returns: callInterval="5" (polling), publishingInterval="1000" (subscription) */
  getIntervalLabel(p: Pipeline): string {
    if (p.mode === 'subscription') return 'event-driven';
    const ci: any = (p as any).callInterval;
    if (ci && ci !== '' && ci !== '0') return `every ${ci}s`;
    return 'every 5s';
  }
}

import { Component, inject, signal, computed, OnInit, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { ApiService } from '../../core/services/api.service';
import { ConfigService } from '../../core/services/config.service';
import { Pipeline, PipelineHealth } from '../../core/models/opcua.models';
import { ConfirmDialogComponent } from '../../shared/confirm-dialog/confirm-dialog.component';

@Component({
  selector: 'app-pipelines-dashboard',
  standalone: true,
  imports: [CommonModule, FormsModule, ConfirmDialogComponent],
  template: `
    <div class="p-8 max-w-7xl mx-auto">
      <!-- Page Header -->
      <div class="flex justify-between items-end mb-10">
        <div class="space-y-1">
          <h1 class="text-3xl font-semibold text-primary tracking-tight">Business Services</h1>
          <p class="text-on-surface-variant">Monitor and orchestrate your OPC UA data streams in real-time.</p>
        </div>
      </div>

      <!-- Sort and filter. This is the slot the inert ARCHIVED control used to
           occupy (T1.10); it now carries controls that do something. Only shown
           once there is enough to be worth filtering. -->
      @if (pipelines().length > 3) {
        <div class="flex flex-wrap items-center gap-2 mb-6">
          <div class="relative flex-1 min-w-[12rem] max-w-xs">
            <span class="material-symbols-outlined absolute left-2.5 top-1/2 -translate-y-1/2 text-base text-on-surface-muted pointer-events-none">search</span>
            <input type="text" [ngModel]="search()" (ngModelChange)="search.set($event)"
                   placeholder="Filter by name or schema" spellcheck="false"
                   class="w-full rounded-lg border border-outline-variant/30 bg-surface-container-lowest pl-8 pr-3 py-1.5 text-xs text-on-surface placeholder:text-on-surface-muted focus:border-primary focus:ring-1 focus:ring-primary/30" />
          </div>

          <div class="flex bg-surface-container p-1 rounded-lg">
            @for (opt of healthFilters; track opt.key) {
              <button (click)="healthFilter.set(opt.key)"
                      class="px-3 py-1 rounded-md text-[11px] font-bold uppercase tracking-wider transition-all"
                      [class]="healthFilter() === opt.key
                        ? 'bg-surface-container-lowest text-primary shadow-sm'
                        : 'text-on-surface-variant hover:text-primary'">
                {{ opt.label }}
              </button>
            }
          </div>

          <label class="flex items-center gap-1.5 text-[11px] font-medium text-on-surface-muted">
            Sort
            <select [ngModel]="sortBy()" (ngModelChange)="sortBy.set($event)"
                    class="rounded-lg border border-outline-variant/30 bg-surface-container-lowest px-2 py-1.5 text-xs text-on-surface focus:border-primary focus:ring-1 focus:ring-primary/30">
              <option value="name">Name</option>
              <option value="health">Health</option>
              <option value="mode">Mode</option>
              <option value="rows">Rows</option>
            </select>
          </label>

          <button (click)="setExpandAll(!isMostlyExpanded())"
                  class="ml-auto flex items-center gap-1.5 rounded-lg border border-outline-variant/30 px-3 py-1.5 text-[11px] font-bold uppercase tracking-wider text-on-surface-variant hover:text-primary hover:border-primary/40 transition-colors">
            <span class="material-symbols-outlined text-base">{{ isMostlyExpanded() ? 'unfold_less' : 'unfold_more' }}</span>
            {{ isMostlyExpanded() ? 'Collapse all' : 'Expand all' }}
          </button>
        </div>
      }

      <!-- Dashboard Stats Grid.
           Skipped entirely with no pipelines: four zeros say nothing the empty
           state below doesn't say better. -->
      @if (pipelines().length) {
      <div class="grid grid-cols-1 md:grid-cols-4 gap-6 mb-12">
        <!-- Total Pipelines -->
        <div class="bg-white p-6 rounded-2xl shadow-[0_2px_12px_-2px_rgba(19,28,121,0.08),0_4px_6px_-2px_rgba(19,28,121,0.04)] border border-slate-200/60 relative overflow-hidden group">
          <span class="material-symbols-outlined absolute right-4 top-1/2 -translate-y-1/2 text-slate-300/25 group-hover:text-slate-300/40 transition-colors" style="font-size:56px">account_tree</span>
          <div class="relative z-10">
            <div class="text-[0.65rem] font-bold text-on-surface-muted uppercase tracking-widest mb-3">Total Services</div>
            <div class="flex items-baseline gap-2">
              <span class="text-4xl font-black text-primary">{{ pipelines().length }}</span>
              <span class="text-sm font-bold text-on-surface-muted">Deployed</span>
            </div>
          </div>
        </div>
        <!-- Running Streams -->
        <div class="bg-white p-6 rounded-2xl shadow-[0_2px_12px_-2px_rgba(19,28,121,0.08),0_4px_6px_-2px_rgba(19,28,121,0.04)] border border-slate-200/60 relative overflow-hidden group">
          <span class="material-symbols-outlined absolute right-4 top-1/2 -translate-y-1/2 transition-colors" style="font-size:56px"
                [class]="runningCount() ? 'text-emerald-400/25 group-hover:text-emerald-400/40' : 'text-slate-300/25'">bolt</span>
          <div class="relative z-10">
            <div class="text-[0.65rem] font-bold text-on-surface-muted uppercase tracking-widest mb-3">Running Streams</div>
            <div class="flex items-baseline gap-2">
              <span class="text-4xl font-black" [class]="runningCount() ? 'text-emerald-700' : 'text-on-surface-variant'">
                {{ runningCount() }}
              </span>
              <span class="text-sm font-bold text-on-surface-muted">{{ runningCount() ? 'Active' : 'None' }}</span>
            </div>
          </div>
        </div>
        <!-- Error Warnings — alarm styling only when something is actually wrong.
             A permanent amber tile at zero spends an operator's trained reflex on
             noise, and over a shift teaches people to stop looking. -->
        <div class="bg-white p-6 rounded-2xl shadow-[0_2px_12px_-2px_rgba(19,28,121,0.08),0_4px_6px_-2px_rgba(19,28,121,0.04)] border relative overflow-hidden group"
             [class]="errorCount() ? 'border-amber-300' : 'border-slate-200/60'">
          <span class="material-symbols-outlined absolute right-4 top-1/2 -translate-y-1/2 transition-colors" style="font-size:56px"
                [class]="errorCount() ? 'text-amber-400/30 group-hover:text-amber-400/50' : 'text-slate-300/25'">
            {{ errorCount() ? 'warning' : 'check_circle' }}
          </span>
          <div class="relative z-10">
            <div class="text-[0.65rem] font-bold text-on-surface-muted uppercase tracking-widest mb-3">Error Warnings</div>
            <div class="flex items-baseline gap-2">
              <!-- amber-700 is 5.02:1, so this holds up as body text and does not
                   lean on the large-text exemption the way amber-600 (3.19:1) would. -->
              <span class="text-4xl font-black" [class]="errorCount() ? 'text-amber-700' : 'text-on-surface-variant'">
                {{ errorCount() }}
              </span>
              <span class="text-sm font-bold text-on-surface-muted">{{ errorCount() ? 'Critical' : 'None' }}</span>
            </div>
          </div>
        </div>
        <!-- Stopped -->
        <div class="bg-white p-6 rounded-2xl shadow-[0_2px_12px_-2px_rgba(19,28,121,0.08),0_4px_6px_-2px_rgba(19,28,121,0.04)] border border-slate-200/60 relative overflow-hidden group">
          <span class="material-symbols-outlined absolute right-4 top-1/2 -translate-y-1/2 transition-colors" style="font-size:56px"
                [class]="stoppedCount() ? 'text-primary/20 group-hover:text-primary/30' : 'text-slate-300/25'">pause_circle</span>
          <div class="relative z-10">
            <div class="text-[0.65rem] font-bold text-on-surface-muted uppercase tracking-widest mb-3">Stopped</div>
            <div class="flex items-baseline gap-2">
              <span class="text-4xl font-black" [class]="stoppedCount() ? 'text-primary' : 'text-on-surface-variant'">
                {{ stoppedCount() }}
              </span>
              <span class="text-sm font-bold text-on-surface-muted">{{ stoppedCount() ? 'Inactive' : 'None' }}</span>
            </div>
          </div>
        </div>
      </div>
      }

      <!-- Pipeline Cards -->
      <div class="space-y-6">
        @if (loading()) {
          <div class="flex items-center justify-center py-20 text-on-surface-variant">
            <span class="material-symbols-outlined text-2xl animate-spin mr-3">progress_activity</span>
            Loading business services...
          </div>
        }

        @if (!loading() && pipelines().length === 0) {
          <div class="flex flex-col items-center justify-center py-20 text-on-surface-variant">
            <span class="material-symbols-outlined text-8xl opacity-10 mb-4">account_tree</span>
            <h2 class="text-xl font-semibold text-primary mb-2">No Business Services Yet</h2>
            <p class="text-sm text-on-surface-muted mb-6">
              A business service is a schema bound to a list of devices. Start by choosing a schema.
            </p>
            <button (click)="createPipeline()"
                    class="px-6 py-3 bg-primary text-on-primary font-bold rounded-lg shadow-xl shadow-primary/30 flex items-center gap-2 hover:brightness-110 active:scale-95 transition-all">
              <span class="material-symbols-outlined">add_circle</span>
              Create Business Service
            </button>
          </div>
        }

        @if (pipelines().length && !visiblePipelines().length) {
          <div class="flex flex-col items-center justify-center py-16 text-on-surface-variant">
            <span class="material-symbols-outlined text-5xl text-on-surface-muted mb-3">filter_alt_off</span>
            <p class="text-sm">No business service matches this filter.</p>
            <button (click)="clearFilters()"
                    class="mt-3 text-xs font-bold uppercase tracking-wider text-primary hover:underline">
              Clear filters
            </button>
          </div>
        }

        @for (pipeline of visiblePipelines(); track pipeline.name) {
          <!-- Pipeline Card -->
          <div class="group rounded-xl p-6 shadow-sm hover:shadow-md transition-shadow"
               [class]="isFailing(pipeline)
                 ? 'bg-surface-container-lowest border border-error/30'
                 : isStopped(pipeline)
                   ? 'bg-surface-container-low/50 border border-outline-variant/5 hover:border-outline-variant/20 opacity-80 hover:opacity-100'
                   : 'bg-surface-container-lowest border border-outline-variant/10'">

            <!-- Card Header: title + status + actions.
                 The flow diagram is excellent at n=1 and wrong at n=20 — each card
                 runs ~320px, so ten pipelines was ~3,200px of scrolling. Rather than
                 delete the thing that works, it collapses: full cards while there is
                 little to scan, compact rows once the list is long enough for height
                 to be the problem, and one click either way. -->
            <div class="flex items-start justify-between" [class]="isExpanded(pipeline) ? 'mb-8' : ''">
              <div class="flex items-center gap-4 min-w-0">
                <button (click)="toggleExpanded(pipeline)"
                        [attr.aria-expanded]="isExpanded(pipeline)"
                        [title]="isExpanded(pipeline) ? 'Collapse' : 'Show the flow diagram'"
                        class="shrink-0 text-on-surface-variant hover:text-primary focus:outline-none focus-visible:ring-2 focus-visible:ring-primary/40 rounded transition-colors">
                  <span class="material-symbols-outlined">{{ isExpanded(pipeline) ? 'expand_less' : 'expand_more' }}</span>
                </button>
                <div class="h-12 w-12 rounded-lg flex items-center justify-center shrink-0"
                     [class]="getStatusIconBg(pipeline)">
                  <span class="material-symbols-outlined text-2xl">{{ getStatusIcon(pipeline) }}</span>
                </div>
                <div class="min-w-0">
                  <!-- Both names, whenever they differ. The label is what an operator
                       chose to call it; the config item name is what Ens_Util.Log and
                       the Management Portal will show them, so hiding it would leave
                       them unable to match a log entry to a card. -->
                  <h3 class="text-lg font-semibold truncate"
                      [class]="isStopped(pipeline) ? 'text-on-surface-variant' : 'text-primary'">{{ title(pipeline) }}</h3>
                  @if (hasDisplayName(pipeline)) {
                    <p class="text-[11px] font-mono text-on-surface-muted truncate"
                       title="The interop identity — this is the name in the event log and the Management Portal">
                      {{ pipeline.name }}
                    </p>
                  }
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
              </div>
            </div>

            <!-- Enabled but not collecting: say so, and say what to do about it.
                 Without this the card looked identical to a healthy one. -->
            @if (isFailing(pipeline)) {
              <div class="flex items-start gap-3 mb-6 bg-error-container/25 border border-error/20 rounded-lg px-4 py-3">
                <span class="material-symbols-outlined text-error text-xl shrink-0">report</span>
                <div class="min-w-0">
                  <p class="text-sm font-bold text-on-error-container">Enabled, but not collecting data</p>
                  <p class="text-xs text-on-error-container/80 mt-0.5">{{ getFailureHint(pipeline) }}</p>
                </div>
              </div>
            }

            <!-- Running dry: health is ok, cycles are being completed, and no row has
                 ever landed. The adapter is genuinely fine — nothing is failing — so
                 this is not an error, and styling it as one would be crying wolf. It
                 is the gap the audit named: a card that looks entirely healthy while
                 the table stays empty. Extends the existing "not collecting"
                 vocabulary rather than inventing new language. -->
            @else if (isRunningDry(pipeline)) {
              <div class="flex items-start gap-3 mb-6 bg-amber-50 border border-amber-300 rounded-lg px-4 py-3">
                <span class="material-symbols-outlined text-amber-700 text-xl shrink-0">table_rows</span>
                <div class="min-w-0">
                  <p class="text-sm font-bold text-amber-900">
                    Running, no rows yet — {{ pipeline.cycles }} cycles completed
                  </p>
                  <p class="text-xs text-amber-900/80 mt-0.5">
                    The service is polling without errors but nothing is being stored.
                    Check that the bound devices actually expose the schema's columns —
                    Edit shows the coverage.
                  </p>
                </div>
              </div>
            }

            <!-- Collapsed: one line carrying what the diagram would have said, so a
                 compact row is still informative rather than just shorter. -->
            @if (!isExpanded(pipeline)) {
              <div class="flex flex-wrap items-center gap-x-4 gap-y-1 mt-2 pl-[5.5rem] text-xs text-on-surface-variant">
                <span class="flex items-center gap-1.5">
                  <span class="material-symbols-outlined text-sm text-tertiary">schema</span>
                  <span class="font-mono">{{ getSchemaName(pipeline) || getTableName(pipeline) }}</span>
                </span>
                @if (getDeviceCount(pipeline)) {
                  <span class="flex items-center gap-1.5">
                    <span class="material-symbols-outlined text-sm text-amber-600">device_hub</span>
                    {{ getDeviceCount(pipeline) }} device{{ getDeviceCount(pipeline) === 1 ? '' : 's' }}
                  </span>
                }
                <span class="flex items-center gap-1.5">
                  <span class="material-symbols-outlined text-sm">table_rows</span>
                  <strong class="font-bold text-primary">{{ pipeline.rowCount != null ? pipeline.rowCount : '—' }}</strong> rows
                </span>
                <span>{{ getIntervalLabel(pipeline) }}</span>
                <span [title]="lastActivityTitle(pipeline)">{{ lastActivityLabel(pipeline) }}</span>
              </div>
            }

            @if (isExpanded(pipeline)) {
            <!-- ═══ Flow Visualization (3-box: Nodes → Service → Table) ═══ -->
            <!-- grayscale(1) alone carries the stopped state (S7) and preserves
                 luminance contrast. The opacity that used to sit alongside it is what
                 pushed SERVICE to 1.54:1 — dropping it keeps the design idea intact. -->
            <div class="flex justify-center mb-6"
                 [style.filter]="isStopped(pipeline) ? 'grayscale(1)' : 'none'">
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
                  <!-- One background for both states. The stopped look is carried by the
                       wrapper's grayscale(1); a bg-primary/80 here was a further opacity
                       on top of it, and measuring the rendered pixels put the SERVICE
                       label at 3.51:1 even after the other three were fixed. -->
                  <div class="rounded-lg px-6 py-4 text-center shadow-lg min-w-[170px]
                              bg-primary text-on-primary border border-primary-container">
                    <p class="text-[0.55rem] font-bold uppercase tracking-widest mb-0.5 text-on-primary-muted">Service</p>
                    <!-- The config item name deliberately, not the label: this box
                         depicts the running business service, and that is the name it
                         runs under and reports under. -->
                    <p class="text-sm font-bold" title="The business service's config item name">{{ pipeline.name }}</p>
                    <p class="text-[10px] mt-0.5 text-on-primary-muted">{{ getIntervalLabel(pipeline) }}</p>
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

            <!-- v2: the schema it binds, and the devices bound to it -->
            @if (pipeline.pipelineVersion === 2) {
              <div class="flex flex-wrap items-center gap-x-4 gap-y-2 mb-4 px-2">
                @if (pipeline['dataSourceClass']) {
                  <button (click)="viewSchemas()"
                          title="Open the schema library"
                          class="flex items-center gap-1.5 text-xs text-on-surface-variant hover:text-primary transition-colors">
                    <span class="material-symbols-outlined text-sm text-tertiary">schema</span>
                    <span class="font-mono">{{ getSchemaName(pipeline) }}</span>
                  </button>
                }
                @if (getDeviceCount(pipeline)) {
                  <div class="flex items-center gap-1.5 min-w-0">
                    <span class="material-symbols-outlined text-sm text-amber-600">device_hub</span>
                    <span class="text-xs font-bold text-on-surface-variant shrink-0">
                      {{ getDeviceCount(pipeline) }} device{{ getDeviceCount(pipeline) === 1 ? '' : 's' }}
                    </span>
                    <span class="text-[10px] text-on-surface-variant font-mono truncate">
                      {{ getRowSourcePaths(pipeline) }}
                    </span>
                  </div>
                }
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
                  <div class="text-[0.6rem] font-medium text-on-surface-muted uppercase tracking-widest">Rows</div>
                  <div class="text-sm font-bold" [class]="isStopped(pipeline) ? 'text-on-surface-variant' : 'text-primary'">
                    {{ pipeline.rowCount != null ? pipeline.rowCount : '—' }}
                  </div>
                </div>
                <div class="space-y-0.5 text-right">
                  <div class="text-[0.6rem] font-medium text-on-surface-muted uppercase tracking-widest">Frequency</div>
                  <div class="text-sm font-bold" [class]="isStopped(pipeline) ? 'text-on-surface-variant' : 'text-primary'">
                    {{ getIntervalLabel(pipeline) }}
                  </div>
                </div>
                <div class="space-y-0.5 text-right">
                  <div class="text-[0.6rem] font-medium text-on-surface-muted uppercase tracking-widest">Last Activity</div>
                  <div class="text-sm font-bold" [class]="isStopped(pipeline) ? 'text-on-surface-variant' : 'text-primary'">
                    <span [title]="lastActivityTitle(pipeline)">{{ lastActivityLabel(pipeline) }}</span>
                  </div>
                </div>
              </div>
            </div>
            }
          </div>
        }
      </div>
    </div>

    @if (pendingDelete()) {
      <app-confirm-dialog
        [title]="'Delete business service &quot;' + title(pendingDelete()!) + '&quot;?'"
        [detail]="deleteDetail()"
        confirmLabel="Delete business service"
        (confirmed)="confirmDelete()"
        (cancelled)="pendingDelete.set(null)" />
    }
  `,
})
export class PipelinesDashboardComponent implements OnInit, OnDestroy {
  private api = inject(ApiService);
  private router = inject(Router);
  config = inject(ConfigService);

  pipelines = signal<Pipeline[]>([]);
  loading = signal(false);

  // ── Density, sort and filter (T3.5) ───────────────────────────────────────
  // Each full card runs ~320px, so ten pipelines was ~3,200px of scrolling with no
  // sort, filter or search — the flow diagram is genuinely good at n=1 and wrong at
  // n=20. Rather than delete it, it collapses.

  search = signal('');
  healthFilter = signal<'all' | 'running' | 'problem' | 'stopped'>('all');
  sortBy = signal<'name' | 'health' | 'mode' | 'rows'>('name');
  /** Overrides the size-based default in both directions. */
  expandAll = signal<boolean | null>(null);
  /** Per-pipeline overrides, keyed by config item name. */
  private manualExpand = signal<Record<string, boolean>>({});

  readonly healthFilters = [
    { key: 'all' as const, label: 'All' },
    { key: 'running' as const, label: 'Running' },
    { key: 'problem' as const, label: 'Problem' },
    { key: 'stopped' as const, label: 'Stopped' },
  ];

  /**
   * Full cards at 1-3, compact rows above that (D4 in the density question).
   * Keeps the diagram as the first impression when there is little to scan, and
   * switches once height is the problem.
   */
  private readonly EXPANDED_BY_DEFAULT_UP_TO = 3;

  visiblePipelines = computed(() => {
    const q = this.search().trim().toLowerCase();
    const health = this.healthFilter();
    const sort = this.sortBy();

    let list = this.pipelines().filter((p) => {
      if (q) {
        // Both names are searchable: someone who renamed a pipeline will search for
        // the label, someone who came from the event log will search for the
        // config item name, and neither should come up empty.
        const haystack =
          `${p.name} ${p.displayName || ''} ${this.getSchemaName(p)} ${this.getTableName(p)}`.toLowerCase();
        if (!haystack.includes(q)) return false;
      }
      switch (health) {
        case 'running': return this.health(p) === 'ok';
        // "Problem" is error *or* starting-forever: both mean not collecting now.
        case 'problem': return this.health(p) === 'error' || this.health(p) === 'starting';
        case 'stopped': return this.isStopped(p);
        default: return true;
      }
    });

    // Rank by how much attention it needs, so a failing pipeline sorts to the top
    // where "health" is chosen.
    const rank = (p: Pipeline) => {
      switch (this.health(p)) {
        case 'error': return 0;
        case 'starting': return 1;
        case 'ok': return 2;
        default: return 3;
      }
    };

    // Alphabetical on the *rendered* title, not the config item name — sorting by a
    // string the user cannot see reads as unsorted.
    const byTitle = (a: Pipeline, b: Pipeline) => this.title(a).localeCompare(this.title(b));

    list = [...list].sort((a, b) => {
      switch (sort) {
        case 'health': return rank(a) - rank(b) || byTitle(a, b);
        case 'mode': return (a.mode || '').localeCompare(b.mode || '') || byTitle(a, b);
        case 'rows': return (b.rowCount ?? -1) - (a.rowCount ?? -1) || byTitle(a, b);
        default: return byTitle(a, b);
      }
    });
    return list;
  });

  isExpanded(p: Pipeline): boolean {
    const manual = this.manualExpand()[p.name];
    if (manual !== undefined) return manual;
    const all = this.expandAll();
    if (all !== null) return all;
    return this.pipelines().length <= this.EXPANDED_BY_DEFAULT_UP_TO;
  }

  toggleExpanded(p: Pipeline): void {
    const next = !this.isExpanded(p);
    this.manualExpand.update((m) => ({ ...m, [p.name]: next }));
  }

  /** True if most visible rows are open, so the button offers the useful action. */
  isMostlyExpanded(): boolean {
    const list = this.visiblePipelines();
    if (!list.length) return false;
    return list.filter((p) => this.isExpanded(p)).length * 2 >= list.length;
  }

  /** Clears per-item overrides too, or the button would appear to do nothing. */
  setExpandAll(value: boolean): void {
    this.manualExpand.set({});
    this.expandAll.set(value);
  }

  clearFilters(): void {
    this.search.set('');
    this.healthFilter.set('all');
  }

  runningCount = signal(0);
  errorCount = signal(0);
  stoppedCount = signal(0);

  private refreshTimer: any;

  ngOnInit(): void {
    this.loadPipelines();

    // Health changes on its own — a device goes offline, resolution starts
    // failing, a rebind takes a poll cycle to take effect — so a card loaded once
    // will keep asserting whatever was true when the page opened. Re-fetch on a
    // timer so what's on screen stays true.
    const seconds = this.config.get().autoRefreshInterval || 5;
    this.refreshTimer = setInterval(() => this.loadPipelines(true), seconds * 1000);
  }

  ngOnDestroy(): void {
    if (this.refreshTimer) clearInterval(this.refreshTimer);
  }

  /**
   * @param background true for timer-driven refreshes, which must not touch the
   * loading flag — flashing the spinner every few seconds would make the page
   * look broken, and would blank the list mid-read on a transient failure.
   */
  loadPipelines(background = false): void {
    if (!background) this.loading.set(true);
    this.api.listPipelines().subscribe({
      next: (pipelines) => {
        this.pipelines.set(pipelines);
        // "Running" now means collecting, not merely enabled — a failing pipeline
        // must not be counted in both tiles.
        this.runningCount.set(pipelines.filter((p) => this.health(p) === 'ok').length);
        this.errorCount.set(pipelines.filter((p) => this.isFailing(p)).length);
        this.stoppedCount.set(pipelines.filter((p) => this.isStopped(p)).length);
        this.loading.set(false);
      },
      error: () => {
        this.loading.set(false);
        // Keep the last known list on a background failure: a blip in the API
        // shouldn't wipe the dashboard.
        if (!background) this.pipelines.set([]);
      },
    });
  }

  /** Creating a business service starts by picking the schema to bind devices to. */
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

  /** Which pipeline the confirmation dialog is about, or null when it is closed. */
  pendingDelete = signal<Pipeline | null>(null);

  deletePipeline(pipeline: Pipeline): void {
    this.pendingDelete.set(pipeline);
  }

  /**
   * The consequence, kept verbatim from the native prompt this replaced — the copy
   * was the good part. Says what survives: the schema and its table are kept, so
   * this is not the data-losing operation a bare "Delete business service?" implies.
   *
   * Names the config item explicitly when a label is hiding it. The heading uses the
   * friendly name, but this is irreversible and reaches equipment, so the thing
   * actually being destroyed has to be identified unambiguously.
   */
  deleteDetail(): string {
    const p = this.pendingDelete();
    if (!p) return '';
    const parts: string[] = [];
    if (this.hasDisplayName(p)) parts.push(`This is the business service "${p.name}".`);
    const schema = this.getSchemaName(p);
    if (schema) {
      parts.push(
        `The "${schema}" schema and its collected data are kept. ` +
        `Delete the schema from the Schemas page if you no longer need it.`
      );
    }
    return parts.join(' ');
  }

  confirmDelete(): void {
    const p = this.pendingDelete();
    if (!p) return;
    this.pendingDelete.set(null);
    this.api.deletePipeline(p.name).subscribe({
      next: () => this.loadPipelines(),
    });
  }

  /** Pipeline is running only if the production is running AND the item is enabled */
  isRunning(p: Pipeline): boolean {
    const prodRunning: any = (p as any).productionRunning;
    if (!(prodRunning === 1 || prodRunning === true || prodRunning === '1')) return false;
    const r: any = (p as any).running;
    if (r === 1 || r === true || r === '1') return true;
    return false;
  }

  isStopped(p: Pipeline): boolean {
    return !this.isRunning(p);
  }

  /**
   * Real collection health, as reported by the adapter.
   *
   * Falls back to running/stopped when the field is absent, so an older backend
   * degrades to the previous behaviour rather than reporting everything as
   * "starting".
   */
  health(p: Pipeline): PipelineHealth {
    return p.health ?? (this.isRunning(p) ? 'ok' : 'stopped');
  }

  /** Running but not collecting — the case that used to look healthy. */
  isFailing(p: Pipeline): boolean {
    return this.health(p) === 'error';
  }

  getStatusIcon(p: Pipeline): string {
    switch (this.health(p)) {
      case 'ok': return 'sync_alt';
      case 'error': return 'error';
      case 'starting': return 'hourglass_top';
      default: return 'pause_circle';
    }
  }

  getStatusIconBg(p: Pipeline): string {
    switch (this.health(p)) {
      case 'ok': return 'bg-tertiary-fixed/20 text-tertiary';
      case 'error': return 'bg-error-container/20 text-error';
      case 'starting': return 'bg-amber-100 text-amber-600';
      default: return 'bg-surface-container-highest text-on-surface-variant';
    }
  }

  getStatusDotClass(p: Pipeline): string {
    switch (this.health(p)) {
      case 'ok': return 'bg-tertiary';
      case 'error': return 'bg-error animate-pulse';
      case 'starting': return 'bg-amber-500 animate-pulse';
      default: return 'bg-on-surface-variant/40';
    }
  }

  getStatusTextClass(p: Pipeline): string {
    switch (this.health(p)) {
      case 'ok': return 'text-tertiary';
      case 'error': return 'text-error';
      case 'starting': return 'text-amber-600';
      default: return 'text-on-surface-variant';
    }
  }

  getStatusLabel(p: Pipeline): string {
    switch (this.health(p)) {
      case 'ok': return 'Running';
      // "Not collecting" rather than "Error": it names the consequence, which is
      // what a user scanning the list actually needs to know.
      case 'error': return 'Not collecting';
      case 'starting': return 'Starting';
      case 'disabled': return 'Disabled';
      default: return 'Stopped';
    }
  }

  /** Why a pipeline isn't collecting, when we can tell from config alone. */
  getFailureHint(p: Pipeline): string {
    if (!this.isFailing(p)) return '';
    return 'The service is retrying but not collecting. Check the event log for the reason.';
  }

  /**
   * Whether an operator-chosen label exists and says something the config item name
   * doesn't. Equal strings mean there is nothing to disambiguate, so showing the
   * same text twice would be noise.
   */
  hasDisplayName(p: Pipeline): boolean {
    const label = (p.displayName || '').trim();
    return label !== '' && label !== p.name;
  }

  /** The label if there is one, else the config item name. */
  title(p: Pipeline): string {
    return this.hasDisplayName(p) ? p.displayName!.trim() : p.name;
  }

  /**
   * Healthy, cycling, and still empty — the `ok`-but-zero-rows gap (R27).
   *
   * The cycle threshold matters: the first cycle legitimately completes before any
   * row is written, so flagging at 1 would accuse every pipeline of running dry for
   * a few seconds after every start. Requiring more than two means the `starting`
   * state has been through and left. A backend without `cycles` returns undefined,
   * which fails the comparison and shows nothing — degrading to the previous
   * behaviour rather than to a false alarm.
   */
  isRunningDry(p: Pipeline): boolean {
    return this.health(p) === 'ok' && p.rowCount === 0 && (p.cycles ?? 0) > 2;
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

  /** Short schema name — the full class name is long and mostly package. */
  getSchemaName(p: Pipeline): string {
    const cls: string = p['dataSourceClass'] || '';
    return cls.split('.').pop() || cls;
  }

  /**
   * Device count, preferring the DeviceNodePaths setting (the source of truth)
   * and falling back to the described row sources.
   */
  getDeviceCount(p: Pipeline): number {
    const setting: string = p['deviceNodePaths'] || '';
    if (setting) {
      return setting
        .split(/\r?\n/)
        .map((l) => l.trim())
        .filter((l) => l !== '' && !l.startsWith('#')).length;
    }
    return (p.rowSources || []).length;
  }

  viewSchemas(): void {
    this.router.navigate(['/schemas']);
  }

  /**
   * `lastActivity` as sent by the backend: `$$$GetHostMonitor` output, formatted
   * `2026-08-03 13:07:29.980` — **no timezone offset, and it is IRIS server time.**
   *
   * That matters, because `new Date('2026-08-03 13:07:29.980')` parses as *local*
   * time. In this compose environment IRIS runs UTC while the host is CEST, so
   * naive parsing was two hours out. Appending 'Z' is right for a UTC IRIS; the
   * container sets that, and the timezone we render makes the interpretation
   * visible rather than silent. If IRIS is ever configured to local time this needs
   * an offset from the backend to stay correct — which is the real fix, and a
   * backend change.
   */
  private parseLastActivity(p: Pipeline): Date | null {
    const raw = (p.lastActivity || '').trim();
    if (!raw) return null;
    const d = new Date(raw.replace(' ', 'T') + 'Z');
    return isNaN(d.getTime()) ? null : d;
  }

  /**
   * Relative age, which is what an operator needs at a glance. Millisecond
   * precision on a field that updates every few seconds was false precision.
   * Falls back to the raw string rather than rendering "Invalid Date".
   */
  lastActivityLabel(p: Pipeline): string {
    const raw = (p.lastActivity || '').trim();
    if (!raw) return 'never';
    const d = this.parseLastActivity(p);
    if (!d) return raw;
    const secs = Math.max(0, Math.round((Date.now() - d.getTime()) / 1000));
    if (secs < 5) return 'just now';
    if (secs < 60) return `${secs}s ago`;
    if (secs < 3600) return `${Math.floor(secs / 60)}m ago`;
    if (secs < 86400) return `${Math.floor(secs / 3600)}h ago`;
    return `${Math.floor(secs / 86400)}d ago`;
  }

  /**
   * The absolute time on hover, **with the timezone named** — the audit calls its
   * absence a hazard in a system talking to equipment across sites.
   */
  lastActivityTitle(p: Pipeline): string {
    const d = this.parseLastActivity(p);
    if (!d) return (p.lastActivity || '').trim() || 'No activity reported yet';
    return d.toLocaleString(undefined, {
      year: 'numeric', month: 'short', day: 'numeric',
      hour: '2-digit', minute: '2-digit', second: '2-digit',
      timeZoneName: 'short',
    });
  }

  /** API returns: callInterval="5" (polling), publishingInterval="1000" (subscription) */
  getIntervalLabel(p: Pipeline): string {
    if (p.mode === 'subscription') return 'event-driven';
    const ci: any = (p as any).callInterval;
    if (ci && ci !== '' && ci !== '0') return `every ${ci}s`;
    return 'every 5s';
  }
}

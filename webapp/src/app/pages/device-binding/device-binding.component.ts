import { Component, inject, signal, computed, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router, ActivatedRoute } from '@angular/router';
import { ApiService } from '../../core/services/api.service';
import { ConfigService } from '../../core/services/config.service';
import { Schema, ServerProfile, DeviceBinding, DeviceValidation } from '../../core/models/opcua.models';

/**
 * Bind devices to an existing schema and deploy a pipeline.
 *
 * This is the flow that used to require a full wizard re-run: pick a schema,
 * paste or type device nodepaths, dry-run them against the live server to see
 * exactly which columns resolve per device, then deploy. The dry run is the point
 * — it moves "does this device really have these nodes?" back to before deploy,
 * which is what makes name-based resolution safe to rely on.
 */
@Component({
  selector: 'app-device-binding',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="p-8 max-w-5xl mx-auto">
      <!-- Header -->
      <div class="mb-8">
        <button (click)="back()"
                class="text-xs font-bold uppercase tracking-widest text-on-surface-variant hover:text-primary transition-colors flex items-center gap-1 mb-3">
          <span class="material-symbols-outlined text-base">arrow_back</span>
          Schemas
        </button>
        <h1 class="text-3xl font-semibold text-primary tracking-tight">Bind Devices</h1>
        <p class="text-on-surface-variant mt-1">
          One row per device, per poll cycle. Nodes are matched by name at connect time.
        </p>
      </div>

      @if (error()) {
        <div class="mb-6 flex items-start gap-3 bg-error-container/40 border border-error/20 rounded-xl px-4 py-3">
          <span class="material-symbols-outlined text-error text-xl">error</span>
          <p class="text-sm font-semibold text-on-error-container flex-1">{{ error() }}</p>
          <button (click)="error.set('')" class="text-on-error-container/60 hover:text-on-error-container">
            <span class="material-symbols-outlined text-lg">close</span>
          </button>
        </div>
      }

      @if (loadingSchema()) {
        <div class="flex items-center justify-center py-20 text-on-surface-variant">
          <span class="material-symbols-outlined text-2xl animate-spin mr-3">progress_activity</span>
          Loading schema...
        </div>
      }

      @if (schema(); as s) {
        <!-- Step 1: the schema being bound -->
        <section class="bg-surface-container-lowest border border-outline-variant/10 rounded-xl p-6 mb-6 shadow-sm">
          <div class="flex items-center gap-3 mb-4">
            <span class="h-7 w-7 rounded-full bg-primary text-on-primary text-xs font-black flex items-center justify-center">1</span>
            <h2 class="text-sm font-bold uppercase tracking-widest text-on-surface-variant">Schema</h2>
          </div>
          <div class="flex items-start gap-4">
            <div class="h-12 w-12 rounded-lg bg-tertiary-fixed/20 text-tertiary flex items-center justify-center shrink-0">
              <span class="material-symbols-outlined text-2xl">schema</span>
            </div>
            <div class="min-w-0">
              <h3 class="text-lg font-semibold text-primary">{{ s.name }}</h3>
              <p class="text-[11px] font-mono text-on-surface-variant">{{ s.schemaClass }}</p>
              <div class="flex flex-wrap gap-1.5 mt-3">
                @for (col of s.columns || []; track col.propertyPath) {
                  <span class="px-2 py-1 rounded-md bg-surface-container text-[11px] font-medium text-on-surface">
                    @if (col.folder) {
                      <span class="text-on-surface-variant">{{ col.folder }}/</span>
                    }{{ col.nodeName }}
                  </span>
                }
              </div>
            </div>
          </div>
        </section>

        <!-- Step 2: devices -->
        <section class="bg-surface-container-lowest border border-outline-variant/10 rounded-xl p-6 mb-6 shadow-sm">
          <div class="flex items-center justify-between mb-4">
            <div class="flex items-center gap-3">
              <span class="h-7 w-7 rounded-full bg-primary text-on-primary text-xs font-black flex items-center justify-center">2</span>
              <h2 class="text-sm font-bold uppercase tracking-widest text-on-surface-variant">Devices</h2>
            </div>
            <span class="text-xs text-on-surface-variant">{{ deviceCount() }} device{{ deviceCount() === 1 ? '' : 's' }}</span>
          </div>

          <label class="block text-xs font-semibold text-on-surface-variant mb-2">
            OPC UA device roots — one per line
          </label>
          <textarea [(ngModel)]="deviceText"
                    (ngModelChange)="onDeviceTextChange()"
                    rows="6"
                    spellcheck="false"
                    placeholder="ns=2;s=Plant.AC1|AC1&#10;ns=2;s=Plant.AC2|AC2&#10;ns=0;i=85|Objects"
                    class="w-full rounded-lg border border-outline-variant/30 bg-surface-container-lowest px-3 py-2.5 font-mono text-sm text-on-surface focus:border-primary focus:ring-1 focus:ring-primary/30 resize-y"></textarea>

          <div class="mt-3 flex items-start gap-2 text-[11px] text-on-surface-variant">
            <span class="material-symbols-outlined text-sm shrink-0 mt-0.5">info</span>
            <div class="space-y-0.5">
              <p><code class="font-mono">ns=2;s=Plant.AC1</code> string NodeId &nbsp;·&nbsp;
                 <code class="font-mono">ns=2;i=1047</code> numeric &nbsp;·&nbsp;
                 <code class="font-mono">i=85</code> namespace 0</p>
              <p>Append <code class="font-mono">|Label</code> to set the NodePath column. Blank lines and
                 <code class="font-mono">#</code> comments are ignored.</p>
            </div>
          </div>

          <!-- Server + dry run -->
          <div class="mt-5 pt-5 border-t border-outline-variant/10 flex flex-wrap items-end gap-3">
            <div class="flex-1 min-w-[220px]">
              <label class="block text-xs font-semibold text-on-surface-variant mb-1.5">Server</label>
              <select [(ngModel)]="serverId"
                      class="w-full rounded-lg border border-outline-variant/30 bg-surface-container-lowest px-3 py-2 text-sm text-on-surface focus:border-primary focus:ring-1 focus:ring-primary/30">
                @for (srv of servers(); track srv.id) {
                  <option [value]="srv.id">{{ srv.name }} — {{ srv.url }}</option>
                }
              </select>
            </div>
            <button (click)="validate()"
                    [disabled]="validating() || deviceCount() === 0 || !serverId"
                    class="px-4 py-2 rounded-lg text-xs font-bold uppercase tracking-wider flex items-center gap-1.5 transition-all"
                    [class]="validating() || deviceCount() === 0 || !serverId
                      ? 'bg-surface-container-highest text-on-surface-variant/40 cursor-not-allowed'
                      : 'bg-tertiary-container text-on-primary hover:brightness-110 active:scale-95'">
              <span class="material-symbols-outlined text-lg" [class.animate-spin]="validating()">
                {{ validating() ? 'progress_activity' : 'fact_check' }}
              </span>
              {{ validating() ? 'Checking...' : 'Check Coverage' }}
            </button>
          </div>
        </section>

        <!-- Step 3: coverage -->
        @if (validation(); as v) {
          <section class="bg-surface-container-lowest border border-outline-variant/10 rounded-xl p-6 mb-6 shadow-sm">
            <div class="flex items-center justify-between mb-4">
              <div class="flex items-center gap-3">
                <span class="h-7 w-7 rounded-full text-xs font-black flex items-center justify-center"
                      [class]="v.allResolved ? 'bg-tertiary text-on-primary' : 'bg-amber-500 text-white'">
                  <span class="material-symbols-outlined text-base">{{ v.allResolved ? 'check' : 'warning' }}</span>
                </span>
                <h2 class="text-sm font-bold uppercase tracking-widest text-on-surface-variant">Coverage</h2>
              </div>
              <span class="text-xs font-bold uppercase tracking-wider"
                    [class]="v.allResolved ? 'text-tertiary' : 'text-amber-600'">
                {{ v.allResolved ? 'All columns resolved' : 'Some columns missing' }}
              </span>
            </div>

            @if (!v.allResolved) {
              <p class="text-xs text-on-surface-variant mb-4 flex items-start gap-2">
                <span class="material-symbols-outlined text-sm shrink-0 mt-0.5">info</span>
                Missing columns are stored as NULL and logged as warnings at runtime. Enable
                <span class="font-semibold">Strict schema match</span> below to refuse to start instead.
              </p>
            }

            <div class="space-y-2">
              @for (dev of v.devices; track dev.label) {
                <div class="border rounded-lg overflow-hidden"
                     [class]="dev.complete ? 'border-tertiary/20' : 'border-amber-400/30'">
                  <div class="flex items-center gap-3 px-4 py-2.5"
                       [class]="dev.complete ? 'bg-tertiary-fixed/10' : 'bg-amber-50'">
                    <span class="material-symbols-outlined text-lg"
                          [class]="dev.complete ? 'text-tertiary' : 'text-amber-600'">
                      {{ dev.complete ? 'check_circle' : 'error' }}
                    </span>
                    <span class="text-sm font-semibold text-on-surface flex-1 truncate">{{ dev.label }}</span>
                    <span class="text-xs font-mono text-on-surface-variant">ns={{ dev.nodeNs }};{{ dev.nodeId }}</span>
                    <span class="text-xs font-bold tabular-nums"
                          [class]="dev.complete ? 'text-tertiary' : 'text-amber-700'">
                      {{ dev.matchedCount }}/{{ v.columnCount }}
                    </span>
                  </div>
                  @if (dev.missing.length) {
                    <div class="px-4 py-2.5 bg-surface-container-lowest flex flex-wrap items-center gap-1.5">
                      <span class="text-[0.6rem] font-bold text-on-surface-variant uppercase tracking-widest mr-1">Missing</span>
                      @for (m of dev.missing; track m) {
                        <span class="px-2 py-0.5 rounded-md bg-amber-100 text-[11px] font-medium text-amber-800">{{ m }}</span>
                      }
                    </div>
                  }
                </div>
              }
            </div>
          </section>
        }

        <!-- Step 4: pipeline settings -->
        <section class="bg-surface-container-lowest border border-outline-variant/10 rounded-xl p-6 mb-6 shadow-sm">
          <div class="flex items-center gap-3 mb-5">
            <span class="h-7 w-7 rounded-full bg-primary text-on-primary text-xs font-black flex items-center justify-center">3</span>
            <h2 class="text-sm font-bold uppercase tracking-widest text-on-surface-variant">Pipeline</h2>
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-5">
            <div>
              <label class="block text-xs font-semibold text-on-surface-variant mb-1.5">Pipeline name</label>
              <input [(ngModel)]="pipelineName" spellcheck="false"
                     class="w-full rounded-lg border border-outline-variant/30 bg-surface-container-lowest px-3 py-2 text-sm text-on-surface focus:border-primary focus:ring-1 focus:ring-primary/30" />
              <p class="text-[11px] text-on-surface-variant mt-1">Shown as the production config item.</p>
            </div>

            <div>
              <label class="block text-xs font-semibold text-on-surface-variant mb-1.5">Mode</label>
              <div class="flex bg-surface-container p-1 rounded-lg">
                <button (click)="mode.set('polling')"
                        class="flex-1 px-3 py-1.5 rounded-md text-xs font-bold uppercase tracking-wider transition-all"
                        [class]="mode() === 'polling' ? 'bg-surface-container-lowest text-primary shadow-sm' : 'text-on-surface-variant hover:text-primary'">
                  Polling
                </button>
                <button (click)="mode.set('subscription')"
                        class="flex-1 px-3 py-1.5 rounded-md text-xs font-bold uppercase tracking-wider transition-all"
                        [class]="mode() === 'subscription' ? 'bg-surface-container-lowest text-primary shadow-sm' : 'text-on-surface-variant hover:text-primary'">
                  Subscription
                </button>
              </div>
            </div>

            @if (mode() === 'polling') {
              <div>
                <label class="block text-xs font-semibold text-on-surface-variant mb-1.5">Poll interval (seconds)</label>
                <input type="number" min="1" [(ngModel)]="callInterval"
                       class="w-full rounded-lg border border-outline-variant/30 bg-surface-container-lowest px-3 py-2 text-sm text-on-surface focus:border-primary focus:ring-1 focus:ring-primary/30" />
              </div>
            } @else {
              <div>
                <label class="block text-xs font-semibold text-on-surface-variant mb-1.5">Publishing interval (ms)</label>
                <input type="number" min="1" [(ngModel)]="publishingInterval"
                       class="w-full rounded-lg border border-outline-variant/30 bg-surface-container-lowest px-3 py-2 text-sm text-on-surface focus:border-primary focus:ring-1 focus:ring-primary/30" />
              </div>
            }

            <div class="sm:col-span-2 flex items-start gap-3 pt-2">
              <input type="checkbox" id="strict" [(ngModel)]="strictSchemaMatch"
                     class="mt-0.5 rounded border-outline-variant/40 text-primary focus:ring-primary/30" />
              <label for="strict" class="text-sm text-on-surface cursor-pointer">
                <span class="font-semibold">Strict schema match</span>
                <span class="block text-[11px] text-on-surface-variant">
                  Refuse to start if any column fails to resolve, instead of storing NULL.
                </span>
              </label>
            </div>
          </div>
        </section>

        <!-- Deploy -->
        <div class="flex items-center justify-between gap-4">
          <p class="text-xs text-on-surface-variant">
            @if (!validation()) {
              Tip: check coverage first to see what each device will actually report.
            }
          </p>
          <button (click)="deploy()"
                  [disabled]="!canDeploy()"
                  class="px-6 py-3 font-bold rounded-lg flex items-center gap-2 transition-all"
                  [class]="canDeploy()
                    ? 'bg-primary text-on-primary shadow-xl shadow-primary/30 hover:brightness-110 active:scale-95'
                    : 'bg-surface-container-highest text-on-surface-variant/40 cursor-not-allowed'">
            <span class="material-symbols-outlined" [class.animate-spin]="deploying()">
              {{ deploying() ? 'progress_activity' : 'rocket_launch' }}
            </span>
            {{ deploying() ? 'Deploying...' : 'Deploy Pipeline' }}
          </button>
        </div>
      }
    </div>
  `,
})
export class DeviceBindingComponent implements OnInit {
  private api = inject(ApiService);
  private router = inject(Router);
  private route = inject(ActivatedRoute);
  private config = inject(ConfigService);

  schema = signal<Schema | null>(null);
  loadingSchema = signal(false);
  error = signal('');

  servers = signal<ServerProfile[]>([]);
  serverId = '';

  deviceText = '';
  validation = signal<{ columnCount: number; devices: DeviceValidation[]; allResolved: boolean } | null>(null);
  validating = signal(false);

  pipelineName = '';
  mode = signal<'polling' | 'subscription'>('polling');
  callInterval = 5;
  publishingInterval = 1000;
  strictSchemaMatch = false;
  deploying = signal(false);

  /** Usable device lines: blank and #-commented lines don't count. */
  deviceCount = computed(() => this.parseLines(this.deviceText).length);

  canDeploy = computed(
    () =>
      !this.deploying() &&
      !!this.schema() &&
      this.deviceCount() > 0 &&
      !!this.pipelineName.trim() &&
      !!this.serverId
  );

  ngOnInit(): void {
    this.servers.set(this.config.getServers());
    const first = this.servers()[0];
    if (first) this.serverId = first.id;

    const schemaClass = this.route.snapshot.paramMap.get('schema') || '';
    if (!schemaClass) {
      this.error.set('No schema specified');
      return;
    }

    this.loadingSchema.set(true);
    this.api.getSchema(schemaClass).subscribe({
      next: (s) => {
        this.schema.set(s);
        // Default the pipeline name to the schema name, de-duplicated by the server if taken.
        this.pipelineName = s.name;
        this.loadingSchema.set(false);
      },
      error: (err) => {
        this.error.set(this.message(err));
        this.loadingSchema.set(false);
      },
    });
  }

  /** Editing the device list invalidates any previous coverage result. */
  onDeviceTextChange(): void {
    if (this.validation()) this.validation.set(null);
  }

  validate(): void {
    const s = this.schema();
    if (!s || !this.deviceCount()) return;

    this.validating.set(true);
    this.error.set('');
    this.api.validateSchema(s.schemaClass, this.deviceText, this.server()).subscribe({
      next: (v) => {
        this.validation.set(v);
        this.validating.set(false);
      },
      error: (err) => {
        this.error.set(this.message(err));
        this.validating.set(false);
      },
    });
  }

  deploy(): void {
    const s = this.schema();
    if (!s || !this.canDeploy()) return;

    this.deploying.set(true);
    this.error.set('');

    const params: Record<string, any> = {
      schemaClass: s.schemaClass,
      dataSourceName: this.pipelineName.trim(),
      devices: this.deviceText,
      mode: this.mode(),
      strictSchemaMatch: this.strictSchemaMatch ? 1 : 0,
    };
    if (this.mode() === 'polling') {
      params['callInterval'] = this.callInterval;
    } else {
      params['publishingInterval'] = this.publishingInterval;
    }

    this.api.deploy(params, this.server()).subscribe({
      next: () => {
        this.deploying.set(false);
        this.router.navigate(['/pipelines']);
      },
      error: (err) => {
        this.error.set(this.message(err));
        this.deploying.set(false);
      },
    });
  }

  back(): void {
    this.router.navigate(['/schemas']);
  }

  private server(): ServerProfile | undefined {
    return this.servers().find((s) => s.id === this.serverId);
  }

  private parseLines(text: string): string[] {
    return (text || '')
      .split(/\r?\n/)
      .map((l) => l.trim())
      .filter((l) => l !== '' && !l.startsWith('#'));
  }

  private message(err: any): string {
    return err?.error?.error || err?.message || 'Request failed';
  }
}

import { Component, inject, signal, computed, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router, ActivatedRoute } from '@angular/router';
import { ApiService } from '../../core/services/api.service';
import { ConfigService } from '../../core/services/config.service';
import { OpcuaTreeComponent } from '../../shared/opcua-tree/opcua-tree.component';
import { Schema, ServerProfile, DeviceBinding, DeviceValidation, TreeNode } from '../../core/models/opcua.models';

/** One line of the device list, decoded for display. */
interface ParsedDevice {
  /** The original trimmed line — the handle used to remove it again. */
  line: string;
  nodePath: string;
  label: string;
  /** False when the nodepath is malformed; the backend would reject the line. */
  valid: boolean;
  /** `ns:id`, matching the tree's key format. Empty when invalid. */
  key: string;
}

/**
 * Render a browsed node as a nodepath.
 *
 * nodeIdType follows OPCUA.Constants: 0 numeric, 3 string, 4 GUID, 5 ByteString.
 */
function nodePathOf(node: TreeNode): string {
  const kind = node.nodeIdType === 0 ? 'i=' : node.nodeIdType === 4 ? 'g=' : node.nodeIdType === 5 ? 'b=' : 's=';
  return `ns=${node.nodeNs};${kind}${node.nodeId}`;
}

/**
 * Parse a nodepath into its namespace and identifier.
 *
 * Deliberately mirrors <code>OPCUA.DataSource.Resolver.ParseNodePath</code>: if
 * this accepted something the backend rejects, the tree would tick a device the
 * deploy then refuses. Returns null for anything unparseable, including the
 * browse-path form the backend doesn't support yet.
 */
function parseNodeId(path: string): { ns: number; id: string } | null {
  let rest = path.trim();
  if (rest === '') return null;

  let ns = 0;
  if (rest.slice(0, 3).toLowerCase() === 'ns=') {
    const semi = rest.indexOf(';');
    if (semi < 0) return null;
    const nsVal = rest.slice(3, semi);
    if (!/^\d+$/.test(nsVal)) return null;
    ns = Number(nsVal);
    rest = rest.slice(semi + 1);
  }

  const kind = rest.slice(0, 2).toLowerCase();
  const val = rest.slice(2);
  if (val === '') return null;

  if (kind === 'i=') return /^\d+$/.test(val) ? { ns, id: String(Number(val)) } : null;
  if (kind === 's=' || kind === 'g=' || kind === 'b=') return { ns, id: val };
  return null;
}

/**
 * Bind devices to an existing schema and deploy a pipeline.
 *
 * This is the flow that used to require a full wizard re-run: pick a schema,
 * choose devices, dry-run them against the live server to see exactly which
 * columns resolve per device, then deploy. The dry run is the point — it moves
 * "does this device really have these nodes?" back to before deploy, which is
 * what makes name-based resolution safe to rely on.
 *
 * Devices can be picked off the live address space or typed as text, and the two
 * are the same list: the tree writes lines into <code>deviceText</code> and reads
 * its ticks back out of it. Keeping one source of truth means pasting a list
 * lights up the tree, and a tree click is always something the user could have
 * typed — no hidden state that survives an edit to the text.
 */
@Component({
  selector: 'app-device-binding',
  standalone: true,
  imports: [CommonModule, FormsModule, OpcuaTreeComponent],
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

          <div class="mb-4">
            <label class="block text-xs font-semibold text-on-surface-variant mb-1.5">Server</label>
            <select [ngModel]="serverId()" (ngModelChange)="serverId.set($event)"
                    class="w-full rounded-lg border border-outline-variant/30 bg-surface-container-lowest px-3 py-2 text-sm text-on-surface focus:border-primary focus:ring-1 focus:ring-primary/30">
              @for (srv of servers(); track srv.id) {
                <option [value]="srv.id">{{ srv.name }} — {{ srv.url }}</option>
              }
            </select>
          </div>

          <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <!-- Pick devices off the live address space -->
            <div>
              <p class="text-xs font-semibold text-on-surface-variant mb-2">
                Click a node to bind it as a device
              </p>
              <div class="border border-outline-variant/15 rounded-lg bg-surface-container-low/30 h-[19rem] overflow-y-auto custom-scrollbar p-1.5">
                <app-opcua-tree [server]="server()"
                                [selectedKeys]="selectedKeys()"
                                (nodeToggled)="toggleDevice($event)" />
              </div>
            </div>

            <!-- What's currently bound -->
            <div class="flex flex-col">
              <div class="flex items-center justify-between mb-2">
                <p class="text-xs font-semibold text-on-surface-variant">Bound devices</p>
                @if (deviceCount()) {
                  <button (click)="clearDevices()"
                          class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant hover:text-error transition-colors">
                    Clear
                  </button>
                }
              </div>

              <div class="border border-outline-variant/15 rounded-lg bg-surface-container-low/30 h-[19rem] overflow-y-auto custom-scrollbar p-1.5">
                @if (!parsedDevices().length) {
                  <div class="h-full flex flex-col items-center justify-center text-on-surface-variant px-4 text-center">
                    <span class="material-symbols-outlined text-5xl opacity-10 mb-2">lan</span>
                    <p class="text-xs opacity-70">No devices bound yet</p>
                    <p class="text-[11px] opacity-50 mt-1">Pick nodes from the tree, or paste a list below.</p>
                  </div>
                } @else {
                  <div class="space-y-1.5">
                    @for (dev of parsedDevices(); track dev.line) {
                      <div class="flex items-center gap-2 bg-surface-container-lowest border border-outline-variant/10 rounded-lg px-2.5 py-2 group">
                        <span class="material-symbols-outlined text-sm shrink-0"
                              [class]="dev.valid ? 'text-tertiary' : 'text-error'">
                          {{ dev.valid ? 'lan' : 'error' }}
                        </span>
                        <div class="min-w-0 flex-1">
                          <p class="text-xs font-semibold text-on-surface truncate">{{ dev.label }}</p>
                          <p class="text-[10px] font-mono text-on-surface-variant truncate">{{ dev.nodePath }}</p>
                        </div>
                        <button (click)="removeDeviceLine(dev.line)"
                                class="p-1 rounded text-on-surface-variant/40 hover:text-error hover:bg-error-container/20 opacity-0 group-hover:opacity-100 transition-all shrink-0">
                          <span class="material-symbols-outlined text-base">close</span>
                        </button>
                      </div>
                    }
                  </div>
                }
              </div>
            </div>
          </div>

          <!-- Advanced: the raw list stays fully editable and paste-friendly -->
          <details class="mt-4 group/adv" [open]="advancedOpen()">
            <summary (click)="toggleAdvanced($event)"
                     class="flex items-center gap-1.5 cursor-pointer text-xs font-bold uppercase tracking-wider text-on-surface-variant hover:text-primary transition-colors w-fit select-none">
              <span class="material-symbols-outlined text-base transition-transform"
                    [class.rotate-90]="advancedOpen()">chevron_right</span>
              Edit as text
            </summary>

            <div class="mt-3">
              <textarea [ngModel]="deviceText()"
                        (ngModelChange)="onDeviceTextChange($event)"
                        rows="6"
                        spellcheck="false"
                        placeholder="ns=2;s=Plant.AC1|AC1&#10;ns=2;s=Plant.AC2|AC2&#10;ns=0;i=85|Objects"
                        class="w-full rounded-lg border border-outline-variant/30 bg-surface-container-lowest px-3 py-2.5 font-mono text-sm text-on-surface focus:border-primary focus:ring-1 focus:ring-primary/30 resize-y"></textarea>

              <div class="mt-2 flex items-start gap-2 text-[11px] text-on-surface-variant">
                <span class="material-symbols-outlined text-sm shrink-0 mt-0.5">info</span>
                <div class="space-y-0.5">
                  <p><code class="font-mono">ns=2;s=Plant.AC1</code> string NodeId &nbsp;·&nbsp;
                     <code class="font-mono">ns=2;i=1047</code> numeric &nbsp;·&nbsp;
                     <code class="font-mono">i=85</code> namespace 0</p>
                  <p>Append <code class="font-mono">|Label</code> to set the NodePath column. Blank lines and
                     <code class="font-mono">#</code> comments are ignored.</p>
                </div>
              </div>
            </div>
          </details>

          <div class="mt-5 pt-5 border-t border-outline-variant/10 flex justify-end">
            <button (click)="validate()"
                    [disabled]="validating() || deviceCount() === 0 || !serverId()"
                    class="px-4 py-2 rounded-lg text-xs font-bold uppercase tracking-wider flex items-center gap-1.5 transition-all"
                    [class]="validating() || deviceCount() === 0 || !serverId()
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
              <input [ngModel]="pipelineName()" (ngModelChange)="pipelineName.set($event)" spellcheck="false"
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
                <input type="number" min="1" [ngModel]="callInterval()" (ngModelChange)="callInterval.set($event)"
                       class="w-full rounded-lg border border-outline-variant/30 bg-surface-container-lowest px-3 py-2 text-sm text-on-surface focus:border-primary focus:ring-1 focus:ring-primary/30" />
              </div>
            } @else {
              <div>
                <label class="block text-xs font-semibold text-on-surface-variant mb-1.5">Publishing interval (ms)</label>
                <input type="number" min="1" [ngModel]="publishingInterval()" (ngModelChange)="publishingInterval.set($event)"
                       class="w-full rounded-lg border border-outline-variant/30 bg-surface-container-lowest px-3 py-2 text-sm text-on-surface focus:border-primary focus:ring-1 focus:ring-primary/30" />
              </div>
            }

            <div class="sm:col-span-2 flex items-start gap-3 pt-2">
              <input type="checkbox" id="strict" [ngModel]="strictSchemaMatch()" (ngModelChange)="strictSchemaMatch.set($event)"
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
  serverId = signal('');

  deviceText = signal('');
  validation = signal<{ columnCount: number; devices: DeviceValidation[]; allResolved: boolean } | null>(null);
  validating = signal(false);

  pipelineName = signal('');
  mode = signal<'polling' | 'subscription'>('polling');
  callInterval = signal(5);
  publishingInterval = signal(1000);
  strictSchemaMatch = signal(false);
  deploying = signal(false);

  advancedOpen = signal(false);

  /** Usable device lines: blank and #-commented lines don't count. */
  deviceCount = computed(() => this.parseLines(this.deviceText()).length);

  /**
   * The device list decoded for display, and the bridge between the textarea and
   * the tree. Both views render from this, so a hand-typed line and a
   * tree-clicked line are indistinguishable downstream — there is only ever one
   * device list, held in `deviceText`.
   */
  parsedDevices = computed<ParsedDevice[]>(() =>
    this.parseLines(this.deviceText()).map((line) => {
      const bar = line.indexOf('|');
      const nodePath = (bar >= 0 ? line.slice(0, bar) : line).trim();
      const label = bar >= 0 ? line.slice(bar + 1).trim() : '';
      const id = parseNodeId(nodePath);
      return {
        line,
        nodePath,
        // An unlabelled device falls back to its NodeId, which is what the
        // backend uses for the NodePath column too.
        label: label || nodePath,
        valid: id !== null,
        key: id ? `${id.ns}:${id.id}` : '',
      };
    })
  );

  /** Which tree rows to tick. Derived, so pasted text lights the tree up too. */
  selectedKeys = computed(
    () => new Set(this.parsedDevices().filter((d) => d.key).map((d) => d.key))
  );

  canDeploy = computed(
    () =>
      !this.deploying() &&
      !!this.schema() &&
      this.deviceCount() > 0 &&
      !!this.pipelineName().trim() &&
      !!this.serverId()
  );

  ngOnInit(): void {
    this.servers.set(this.config.getServers());
    const first = this.servers()[0];
    if (first) this.serverId.set(first.id);

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
        this.pipelineName.set(s.name);
        this.loadingSchema.set(false);
      },
      error: (err) => {
        this.error.set(this.message(err));
        this.loadingSchema.set(false);
      },
    });
  }

  /** Editing the device list invalidates any previous coverage result. */
  onDeviceTextChange(value: string): void {
    this.deviceText.set(value);
    if (this.validation()) this.validation.set(null);
  }

  toggleAdvanced(event: Event): void {
    // Drive <details> from the signal rather than letting it manage itself, so
    // the chevron rotation and the open state can't disagree.
    event.preventDefault();
    this.advancedOpen.update((v) => !v);
  }

  /**
   * Bind or unbind the clicked node.
   *
   * Writes through to `deviceText`, which stays the single source of truth — so
   * everything the tree does is something the user could equally have typed, and
   * is reviewable in the text view.
   */
  toggleDevice(node: TreeNode): void {
    const key = `${node.nodeNs}:${node.nodeId}`;
    const existing = this.parsedDevices().find((d) => d.key === key);
    if (existing) {
      this.removeDeviceLine(existing.line);
      return;
    }
    this.appendLines([`${nodePathOf(node)}|${node.displayName}`]);
  }

  removeDeviceLine(line: string): void {
    // Match on the raw line so a comment or oddly-spaced duplicate elsewhere in
    // the text is left untouched.
    const kept = this.deviceText()
      .split(/\r?\n/)
      .filter((l) => l.trim() !== line);
    this.onDeviceTextChange(kept.join('\n'));
  }

  clearDevices(): void {
    this.onDeviceTextChange('');
  }

  private appendLines(lines: string[]): void {
    const current = this.deviceText().replace(/\s+$/, '');
    const next = current === '' ? lines.join('\n') : [current, ...lines].join('\n');
    this.onDeviceTextChange(next);
  }

  validate(): void {
    const s = this.schema();
    if (!s || !this.deviceCount()) return;

    this.validating.set(true);
    this.error.set('');
    this.api.validateSchema(s.schemaClass, this.deviceText(), this.server()).subscribe({
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
      dataSourceName: this.pipelineName().trim(),
      devices: this.deviceText(),
      mode: this.mode(),
      strictSchemaMatch: this.strictSchemaMatch() ? 1 : 0,
    };
    if (this.mode() === 'polling') {
      params['callInterval'] = this.callInterval();
    } else {
      params['publishingInterval'] = this.publishingInterval();
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

  server(): ServerProfile | undefined {
    return this.servers().find((s) => s.id === this.serverId());
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

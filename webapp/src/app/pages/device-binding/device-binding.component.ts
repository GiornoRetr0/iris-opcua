import { Component, inject, signal, computed, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router, ActivatedRoute } from '@angular/router';
import { ApiService } from '../../core/services/api.service';
import { ConfigService } from '../../core/services/config.service';
import { OpcuaTreeComponent } from '../../shared/opcua-tree/opcua-tree.component';
import { Schema, ServerProfile, DeviceValidation, TreeNode } from '../../core/models/opcua.models';

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
 * The suggested config-item name for a new pipeline over a schema.
 *
 * Takes the schema's short name, so `OPCUA.DS.AirConditioner` suggests
 * `from-OPCUA-AirConditioner`.
 */
function defaultPipelineName(schemaShortName: string): string {
  return `from-OPCUA-${schemaShortName}`;
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
          {{ editMode() ? 'Pipelines' : 'Schemas' }}
        </button>
        <h1 class="text-3xl font-semibold text-primary tracking-tight">
          {{ editMode() ? 'Edit Devices' : 'Bind Devices' }}
        </h1>
        <p class="text-on-surface-variant mt-1">
          @if (editMode()) {
            Change which devices <span class="font-semibold">{{ pipelineName() }}</span> reads.
            Takes effect without a recompile.
          } @else {
            One row per device, per poll cycle. Nodes are matched by name at connect time.
          }
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
            <select [ngModel]="serverId()" (ngModelChange)="onServerChange($event)"
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
                  <!-- Each device carries its own coverage: it is checked against
                       the schema the moment it is added, so the list is the answer
                       rather than a request for one. -->
                  <div class="space-y-1.5">
                    @for (dev of parsedDevices(); track dev.line) {
                      @let cov = coverageOf(dev.key);
                      @let busy = isChecking(dev.key);
                      @let bad = !dev.valid || (cov && !cov.usable);
                      <div class="rounded-lg border overflow-hidden group"
                           [class]="bad ? 'border-error/40 bg-error-container/20'
                                    : cov ? (cov.complete ? 'border-tertiary/25 bg-tertiary-fixed/10' : 'border-amber-400/30 bg-amber-50/60')
                                    : 'border-outline-variant/10 bg-surface-container-lowest'">
                        <div class="flex items-center gap-2 px-2.5 py-2">
                          @if (busy) {
                            <span class="material-symbols-outlined text-sm shrink-0 text-primary animate-spin">progress_activity</span>
                          } @else {
                            <span class="material-symbols-outlined text-sm shrink-0"
                                  [class]="bad ? 'text-error' : cov ? (cov.complete ? 'text-tertiary' : 'text-amber-600') : 'text-on-surface-variant/50'">
                              {{ bad ? 'block' : cov ? (cov.complete ? 'check_circle' : 'error') : 'lan' }}
                            </span>
                          }
                          <div class="min-w-0 flex-1">
                            <p class="text-xs font-semibold text-on-surface truncate">{{ dev.label }}</p>
                            <p class="text-[10px] font-mono text-on-surface-variant truncate">{{ dev.nodePath }}</p>
                          </div>
                          @if (cov && dev.valid) {
                            <span class="text-[11px] font-bold tabular-nums shrink-0"
                                  [class]="bad ? 'text-error' : cov.complete ? 'text-tertiary' : 'text-amber-700'">
                              {{ cov.matchedCount }}/{{ columnCount() }}
                            </span>
                          }
                          <button (click)="removeDeviceLine(dev.line)"
                                  class="p-1 rounded text-on-surface-variant/40 hover:text-error hover:bg-error-container/20 opacity-0 group-hover:opacity-100 focus:opacity-100 transition-all shrink-0">
                            <span class="material-symbols-outlined text-base">close</span>
                          </button>
                        </div>

                        @if (!dev.valid) {
                          <p class="px-2.5 pb-2 text-[10.5px] leading-snug text-on-surface">
                            <span class="font-bold text-error">Malformed —</span>
                            expected <code class="font-mono">ns=2;s=Name</code> or <code class="font-mono">i=85</code>.
                          </p>
                        } @else if (cov && !cov.usable) {
                          <p class="px-2.5 pb-2 text-[10.5px] leading-snug text-on-surface">
                            <span class="font-bold text-error">Can't be bound —</span> {{ cov.unusableReason }}
                          </p>
                        } @else if (cov && cov.missing.length) {
                          <div class="px-2.5 pb-2 flex flex-wrap items-center gap-1">
                            <span class="text-[9px] font-bold text-on-surface-variant uppercase tracking-widest mr-0.5">Missing</span>
                            @for (m of cov.missing; track m) {
                              <span class="px-1.5 py-px rounded bg-amber-100 text-[10px] font-medium text-amber-800">{{ m }}</span>
                            }
                            <span class="text-[10px] text-on-surface-variant">— stored as NULL</span>
                          </div>
                        }
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

          <!-- A one-line summary; the per-device detail lives in the rows above,
               so there is nothing to duplicate here. -->
          @if (deviceCount()) {
            <div class="mt-5 pt-4 border-t border-outline-variant/10 flex items-center gap-2 text-xs">
              @if (anyChecking()) {
                <span class="material-symbols-outlined text-sm text-primary animate-spin">progress_activity</span>
                <span class="text-on-surface-variant">Checking coverage against the schema...</span>
              } @else if (unusableDevices().length) {
                <span class="material-symbols-outlined text-sm text-error">block</span>
                <span class="text-on-surface">
                  <span class="font-bold text-error">{{ unusableDevices().length }}</span>
                  device{{ unusableDevices().length === 1 ? '' : 's' }} can't be bound — remove
                  {{ unusableDevices().length === 1 ? 'it' : 'them' }} to continue.
                </span>
              } @else if (uncheckedDevices().length) {
                <span class="material-symbols-outlined text-sm text-on-surface-variant">help</span>
                <span class="text-on-surface-variant">
                  Coverage unknown for {{ uncheckedDevices().length }} device(s) — is the server reachable?
                </span>
              } @else if (allComplete()) {
                <span class="material-symbols-outlined text-sm text-tertiary">check_circle</span>
                <span class="text-on-surface-variant">
                  Every device reports all {{ columnCount() }} column{{ columnCount() === 1 ? '' : 's' }}.
                </span>
              } @else {
                <span class="material-symbols-outlined text-sm text-amber-600">error</span>
                <span class="text-on-surface-variant">
                  Some columns are missing on some devices — they will be stored as NULL.
                </span>
              }
            </div>
          }
        </section>
        <!-- Step 4: pipeline settings -->
        <section class="bg-surface-container-lowest border border-outline-variant/10 rounded-xl p-6 mb-6 shadow-sm">
          <div class="flex items-center gap-3 mb-5">
            <span class="h-7 w-7 rounded-full bg-primary text-on-primary text-xs font-black flex items-center justify-center">3</span>
            <h2 class="text-sm font-bold uppercase tracking-widest text-on-surface-variant">Pipeline</h2>
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-5">
            @if (editMode()) {
              <!-- Name and transport are fixed once deployed: changing them would
                   mean a different config item, i.e. a different pipeline. -->
              <div class="sm:col-span-2 flex flex-wrap items-center gap-x-6 gap-y-2 text-sm">
                <div class="flex items-center gap-2">
                  <span class="text-xs font-semibold text-on-surface-variant">Name</span>
                  <span class="font-semibold text-primary">{{ pipelineName() }}</span>
                </div>
                <div class="flex items-center gap-2">
                  <span class="text-xs font-semibold text-on-surface-variant">Mode</span>
                  <span class="text-on-surface">{{ mode() }}</span>
                </div>
                <p class="text-[11px] text-on-surface-variant basis-full">
                  To change the name or mode, delete this pipeline and bind the schema again.
                </p>
              </div>
            } @else {
              <div>
                <label class="block text-xs font-semibold text-on-surface-variant mb-1.5">Pipeline name</label>
                <!-- The suggestion is a placeholder, not a value: it stays grey and
                     out of the way until the user types over it. Leaving the field
                     empty deploys under it. -->
                <input [ngModel]="pipelineName()" (ngModelChange)="pipelineName.set($event)" spellcheck="false"
                       [placeholder]="suggestedName()"
                       class="w-full rounded-lg border border-outline-variant/30 bg-surface-container-lowest px-3 py-2 text-sm text-on-surface placeholder:text-on-surface-variant/50 focus:border-primary focus:ring-1 focus:ring-primary/30" />
                <p class="text-[11px] text-on-surface-variant mt-1">
                  @if (pipelineName().trim()) {
                    Shown as the production config item.
                  } @else {
                    Leave empty to use <code class="font-mono text-primary">{{ suggestedName() }}</code>.
                  }
                </p>
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
            }

          </div>
        </section>

        <!-- Deploy -->
        <div class="flex items-center justify-between gap-4">
          <p class="text-xs">
            @if (unusableDevices().length) {
              <span class="text-error font-semibold flex items-center gap-1.5">
                <span class="material-symbols-outlined text-sm">block</span>
                Remove {{ unusableLabels() }} to continue
              </span>
            } @else if (anyChecking()) {
              <span class="text-on-surface-variant flex items-center gap-1.5">
                <span class="material-symbols-outlined text-sm animate-spin">progress_activity</span>
                Checking devices...
              </span>
            } @else if (deviceCount() === 0) {
              <span class="text-on-surface-variant">Pick at least one device above.</span>
            }
          </p>
          <button (click)="deploy()"
                  [disabled]="!canDeploy()"
                  class="px-6 py-3 font-bold rounded-lg flex items-center gap-2 transition-all"
                  [class]="canDeploy()
                    ? 'bg-primary text-on-primary shadow-xl shadow-primary/30 hover:brightness-110 active:scale-95'
                    : 'bg-surface-container-highest text-on-surface-variant/40 cursor-not-allowed'">
            <span class="material-symbols-outlined" [class.animate-spin]="deploying()">
              {{ deploying() ? 'progress_activity' : (editMode() ? 'sync' : 'rocket_launch') }}
            </span>
            @if (editMode()) {
              {{ deploying() ? 'Saving...' : 'Save Devices' }}
            } @else {
              {{ deploying() ? 'Deploying...' : 'Deploy Pipeline' }}
            }
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

  /**
   * Editing an existing pipeline rather than creating one.
   *
   * The same screen serves both because they are the same act: choosing which
   * devices a schema reads. In edit mode the schema and name are already fixed,
   * so only the device list and strictness can change — which is a settings
   * update, not a regeneration.
   */
  editMode = signal(false);

  servers = signal<ServerProfile[]>([]);
  serverId = signal('');

  deviceText = signal('');
  /**
   * Coverage per device, keyed by `ns:id`, filled in as devices are added.
   *
   * Keyed rather than a single result blob so each device is checked exactly once:
   * coverage is a property of a device, not of a submission, so adding a device
   * must not invalidate what is already known about the others.
   */
  coverage = signal<Map<string, DeviceValidation>>(new Map());

  /** Device keys with a check in flight. */
  checking = signal<Set<string>>(new Set());

  /** The schema's column count, learned from the first coverage response. */
  columnCount = signal(0);

  pipelineName = signal('');
  mode = signal<'polling' | 'subscription'>('polling');
  callInterval = signal(5);
  publishingInterval = signal(1000);
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

  /**
   * Devices the backend has confirmed it will refuse.
   *
   * Only known after a coverage check, so this is empty until one runs — the
   * button stays enabled and the backend remains the authority. This just avoids
   * a round trip that was always going to fail.
   */
  unusableDevices = computed(() =>
    this.parsedDevices()
      .map((d) => this.coverage().get(d.key))
      .filter((c): c is DeviceValidation => !!c && !c.usable)
  );

  /** True while any device in the current list is still being checked. */
  anyChecking = computed(() => this.parsedDevices().some((d) => this.checking().has(d.key)));

  /**
   * Devices whose coverage is not yet known — unchecked, or a check that failed.
   *
   * Deploy waits on these rather than assuming they're fine: an unchecked device
   * is exactly the case that used to slip through to a backend rejection.
   */
  uncheckedDevices = computed(() =>
    this.parsedDevices().filter((d) => d.valid && !this.coverage().has(d.key))
  );

  /** Every device resolves every column. */
  allComplete = computed(() =>
    this.parsedDevices().every((d) => this.coverage().get(d.key)?.complete)
  );

  /** The offending device labels, for the blocked-deploy hint. */
  unusableLabels = computed(() => {
    const labels = this.unusableDevices().map((d) => d.label);
    if (labels.length <= 3) return labels.join(', ');
    return `${labels.slice(0, 3).join(', ')} and ${labels.length - 3} more`;
  });

  /** Placeholder name, shown until the user types their own. */
  suggestedName = computed(() => {
    const s = this.schema();
    return s ? defaultPipelineName(s.name) : '';
  });

  /**
   * The name the pipeline will actually be deployed under.
   *
   * An untouched field means "use the suggestion" — it is a placeholder, so an
   * empty box is a valid choice rather than a missing answer.
   */
  effectiveName = computed(() => this.pipelineName().trim() || this.suggestedName());

  canDeploy = computed(
    () =>
      !this.deploying() &&
      !!this.schema() &&
      this.deviceCount() > 0 &&
      // effectiveName, not the raw field: an empty box means "use the suggestion".
      !!this.effectiveName() &&
      !!this.serverId() &&
      // Every device must be known good. Waiting on in-flight checks is what stops
      // a device slipping through unverified to a backend rejection.
      !this.anyChecking() &&
      this.unusableDevices().length === 0 &&
      this.uncheckedDevices().length === 0
  );

  ngOnInit(): void {
    this.servers.set(this.config.getServers());
    const first = this.servers()[0];
    if (first) this.serverId.set(first.id);

    const pipelineName = this.route.snapshot.paramMap.get('name') || '';
    if (pipelineName) {
      this.editMode.set(true);
      this.loadPipeline(pipelineName);
      return;
    }

    const schemaClass = this.route.snapshot.paramMap.get('schema') || '';
    if (!schemaClass) {
      this.error.set('No schema specified');
      return;
    }
    this.loadSchema(schemaClass);
  }

  /** Load an existing pipeline and pre-fill its current binding. */
  private loadPipeline(name: string): void {
    this.loadingSchema.set(true);
    this.api.listPipelines().subscribe({
      next: (pipelines) => {
        const p = pipelines.find((x) => x.name === name);
        if (!p) {
          this.error.set(`Pipeline '${name}' not found`);
          this.loadingSchema.set(false);
          return;
        }

        this.pipelineName.set(p.name);
        this.deviceText.set(p['deviceNodePaths'] || '');
        if (p.mode === 'subscription') this.mode.set('subscription');

        // Prefer the pipeline's own server so the tree browses what it reads.
        const url: string = p['serverUrl'] || '';
        const match = this.servers().find((s) => s.url === url);
        if (match) this.serverId.set(match.id);

        const cls: string = p['dataSourceClass'] || '';
        if (!cls) {
          this.error.set('This pipeline has no schema class');
          this.loadingSchema.set(false);
          return;
        }
        this.loadSchema(cls);
      },
      error: (err) => {
        this.error.set(this.message(err));
        this.loadingSchema.set(false);
      },
    });
  }

  private loadSchema(schemaClass: string, then?: (s: Schema) => void): void {
    this.loadingSchema.set(true);
    this.api.getSchema(schemaClass).subscribe({
      next: (s) => {
        this.schema.set(s);
        if (then) then(s);
        this.loadingSchema.set(false);
        // Edit mode arrives with devices already listed, and coverage needs the
        // schema, so this is the earliest point they can be checked.
        this.checkPending();
      },
      error: (err) => {
        this.error.set(this.message(err));
        this.loadingSchema.set(false);
      },
    });
  }

  /**
   * The device list changed — check whatever is newly in it.
   *
   * Cached results are kept: coverage belongs to a device, so editing the list
   * cannot change what was already learned about a device still in it. Only the
   * additions are checked.
   */
  onDeviceTextChange(value: string): void {
    this.deviceText.set(value);
    this.checkPending();
  }

  /**
   * Switching server invalidates every cached result.
   *
   * A NodeId means nothing without the server it came from — the same `ns=2;s=AC1`
   * can exist on one endpoint and not another. Keeping the old verdicts would show
   * coverage measured against a server the pipeline no longer reads.
   */
  onServerChange(id: string): void {
    if (id === this.serverId()) return;
    this.serverId.set(id);
    this.coverage.set(new Map());
    this.checking.set(new Set());
    this.checkPending();
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

  /**
   * Check coverage for any device that doesn't have it yet.
   *
   * Only unchecked devices are sent, so adding a fifth device doesn't re-browse
   * the first four — their rows stay put instead of flickering back to a spinner.
   * Results are cached by device key, which is also why removing and re-adding a
   * device is instant.
   *
   * A failed request is deliberately not surfaced as a page error: it usually
   * means the server is briefly unreachable, and the affected rows simply stay
   * unchecked, which already blocks deploy.
   */
  private checkPending(): void {
    const s = this.schema();
    if (!s) return;

    const pending = this.parsedDevices().filter(
      (d) => d.valid && !this.coverage().has(d.key) && !this.checking().has(d.key)
    );
    if (!pending.length) return;

    const keys = pending.map((d) => d.key);
    this.checking.update((set) => new Set([...set, ...keys]));

    const lines = pending.map((d) => d.line).join('\n');
    this.api.validateSchema(s.schemaClass, lines, this.server()).subscribe({
      next: (v) => {
        this.columnCount.set(v.columnCount);
        this.coverage.update((map) => {
          const next = new Map(map);
          // Match on the device's own key, not array position: the backend drops
          // unparseable lines, so index i in the response need not be pending[i].
          for (const dev of v.devices || []) {
            next.set(`${dev.nodeNs}:${dev.nodeId}`, dev);
          }
          return next;
        });
        this.clearChecking(keys);
      },
      error: () => this.clearChecking(keys),
    });
  }

  private clearChecking(keys: string[]): void {
    this.checking.update((set) => {
      const next = new Set(set);
      for (const k of keys) next.delete(k);
      return next;
    });
  }

  /** Coverage for one device row, once known. */
  coverageOf(key: string): DeviceValidation | undefined {
    return this.coverage().get(key);
  }

  isChecking(key: string): boolean {
    return this.checking().has(key);
  }

  deploy(): void {
    const s = this.schema();
    if (!s || !this.canDeploy()) return;

    this.deploying.set(true);
    this.error.set('');

    // Editing changes only the binding, so it never regenerates the schema.
    if (this.editMode()) {
      this.api
        .rebindPipeline(this.pipelineName(), this.deviceText())
        .subscribe({
          next: () => {
            this.deploying.set(false);
            this.router.navigate(['/pipelines']);
          },
          error: (err) => {
            this.error.set(this.message(err));
            this.deploying.set(false);
          },
        });
      return;
    }

    const params: Record<string, any> = {
      schemaClass: s.schemaClass,
      dataSourceName: this.effectiveName(),
      devices: this.deviceText(),
      mode: this.mode(),
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
    this.router.navigate([this.editMode() ? '/pipelines' : '/schemas']);
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

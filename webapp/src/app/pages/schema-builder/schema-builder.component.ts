import { Component, inject, signal, computed, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { forkJoin, of, Observable } from 'rxjs';
import { catchError, map, switchMap } from 'rxjs/operators';
import { ApiService } from '../../core/services/api.service';
import { ConfigService } from '../../core/services/config.service';
import { ServerProfile, TreeNode } from '../../core/models/opcua.models';
import { nodeIcon, nodeIconClass } from '../../shared/opcua-tree/node-icons';

/** A column being assembled for the new schema. */
interface DraftColumn {
  /** Leaf node name — this is what gets matched against each device at runtime */
  displayName: string;
  /**
   * Path relative to the template device root: `["Leaf"]`, or
   * `["Folder", "Leaf"]` for a sub-folder inside the device.
   *
   * Nothing above the device root ever appears here — that part of the address
   * space differs per device, and the whole point of a schema is to be
   * device-independent.
   */
  relativePath: string[];
  nodeNs: number;
  nodeId: string | number;
  nodeIdType: number;
  /**
   * `OPCUA.Types.*` name from reading the template node's value. The backend maps
   * it to a real property type; absent means it falls back to %String.
   */
  inferredType?: string;
  /** Set once a type probe has finished, successfully or not. */
  typeProbed?: boolean;
  key: string;
}

/** Short label for a column's storage type, for the draft list. */
function typeLabel(inferredType?: string): string {
  if (!inferredType) return 'text';
  if (inferredType.includes('ArrayDataValue')) return 'array → text';
  const m = /OPCUA\.Types\.(\w+?)DataValue/.exec(inferredType);
  if (!m) return 'text';
  switch (m[1]) {
    case 'Double': return 'number';
    case 'Integer': return 'integer';
    case 'Boolean': return 'boolean';
    case 'TimeStamp': return 'timestamp';
    case 'String': return 'text';
    default: return m[1].toLowerCase();
  }
}

/** How deep inside a device a column may sit — see `pathFromRoot`. */
const MAX_DEPTH = 2;

/**
 * Create a reusable device schema by picking nodes off one representative device.
 *
 * The device you browse here is only a *template* — none of its node IDs are
 * captured. What's saved is the column names, which are matched by name against
 * whichever devices get bound later. That's why this page ends at "Save Schema"
 * and never touches a production.
 *
 * Which node *is* the device has to be stated explicitly. It cannot be inferred
 * from tree depth: browse from `Objects` and a device sits two levels down, browse
 * from the device's parent folder and it sits one — the same schema would come out
 * differently. Marking the root is what makes a column's identity relative to the
 * device, and so device-independent.
 */
@Component({
  selector: 'app-schema-builder',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="p-8 max-w-6xl mx-auto">
      <!-- Header -->
      <div class="mb-8">
        <button (click)="back()"
                class="text-xs font-bold uppercase tracking-widest text-on-surface-variant hover:text-primary transition-colors flex items-center gap-1 mb-3">
          <span class="material-symbols-outlined text-base">arrow_back</span>
          Schemas
        </button>
        <h1 class="text-3xl font-semibold text-primary tracking-tight">New Schema</h1>
        <p class="text-on-surface-variant mt-1">
          Pick the nodes of one representative device. Its node IDs aren't stored — only the names,
          which are matched against every device you bind later.
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

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
        <!-- Browse a template device -->
        <section class="bg-surface-container-lowest border border-outline-variant/10 rounded-xl p-6 shadow-sm">
          <div class="flex items-center gap-3 mb-4">
            <span class="h-7 w-7 rounded-full bg-primary text-on-primary text-xs font-black flex items-center justify-center">1</span>
            <h2 class="text-sm font-bold uppercase tracking-widest text-on-surface-variant">Template Device</h2>
          </div>

          <div class="flex gap-2 mb-4">
            <select [ngModel]="serverId()" (ngModelChange)="serverId.set($event)"
                    class="flex-1 rounded-lg border border-outline-variant/30 bg-surface-container-lowest px-3 py-2 text-sm text-on-surface focus:border-primary focus:ring-1 focus:ring-primary/30">
              @for (srv of servers(); track srv.id) {
                <option [value]="srv.id">{{ srv.name }}</option>
              }
            </select>
            <button (click)="loadRoot()"
                    [disabled]="!serverId() || browsing()"
                    class="px-3 py-2 rounded-lg text-xs font-bold uppercase tracking-wider bg-surface-container text-primary hover:bg-primary-fixed/40 disabled:opacity-40 disabled:cursor-not-allowed transition-colors flex items-center gap-1.5">
              <span class="material-symbols-outlined text-lg" [class.animate-spin]="browsing()">
                {{ browsing() ? 'progress_activity' : 'travel_explore' }}
              </span>
              Browse
            </button>
          </div>

          <!-- A persistent slot for the template device, filled or empty.
               Which node is the device has to be said out loud; it can't be guessed
               from depth without baking the browse path into the column names.

               This replaces the callout that explained *where the button was*
               ("Hover a node and press Set device"). Needing to document the location
               of a control is the symptom; now that Set device is always visible
               (T3.3) and the current selection has a fixed home, that sentence is
               deletable — which was the stated test for this being fixed. -->
          @if (roots().length) {
            <div class="mb-3 flex items-center gap-2 rounded-lg px-3 py-2 text-[11px] leading-snug"
                 [class]="deviceRoot()
                   ? 'bg-primary/8 border border-primary/20 text-on-surface'
                   : 'bg-surface-container-low border border-outline-variant/20 text-on-surface-variant'">
              <span class="material-symbols-outlined text-sm shrink-0"
                    [class]="deviceRoot() ? 'text-primary' : 'text-on-surface-muted'">memory</span>
              @if (deviceRoot(); as root) {
                <span class="min-w-0 flex-1">
                  Template device: <strong class="font-bold">{{ root.displayName }}</strong>.
                  Columns are named relative to it — its own name never becomes part of a column.
                </span>
                <button (click)="clearDeviceRoot()"
                        title="Clear the template device"
                        class="shrink-0 text-[10px] font-bold uppercase tracking-wider text-primary hover:underline focus:outline-none focus-visible:ring-2 focus-visible:ring-primary/40 rounded px-1">
                  Change
                </button>
              } @else {
                <span class="min-w-0 flex-1">
                  <strong class="font-bold">No template device.</strong>
                  Pick the node representing one device — columns are named relative to it.
                </span>
              }
            </div>
          }

          <div class="border border-outline-variant/15 rounded-lg bg-surface-container-low/30 max-h-[26rem] overflow-y-auto custom-scrollbar p-2">
            @if (!roots().length && !browsing()) {
              <p class="text-xs text-on-surface-variant text-center py-8">
                Browse a server, mark one device, then tick the nodes that make up its type.
              </p>
            }
            @for (node of roots(); track nodeKey(node)) {
              <ng-container *ngTemplateOutlet="treeTpl; context: { $implicit: node, level: 0 }" />
            }
          </div>
        </section>

        <!-- Draft columns -->
        <section class="bg-surface-container-lowest border border-outline-variant/10 rounded-xl p-6 shadow-sm flex flex-col">
          <div class="flex items-center justify-between mb-4">
            <div class="flex items-center gap-3">
              <span class="h-7 w-7 rounded-full bg-primary text-on-primary text-xs font-black flex items-center justify-center">2</span>
              <h2 class="text-sm font-bold uppercase tracking-widest text-on-surface-variant">Columns</h2>
            </div>
            @if (columns().length) {
              <button (click)="columns.set([])"
                      class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant hover:text-error transition-colors">
                Clear
              </button>
            }
          </div>

          @if (!columns().length) {
            <div class="flex-1 flex flex-col items-center justify-center py-12 text-on-surface-variant">
              <span class="material-symbols-outlined text-6xl opacity-10 mb-3">view_column</span>
              <!-- No instruction here any more: the reason you can't save now sits
                   beside the Save button, which is where you look when the button is
                   disabled. This copy was the 2.78:1 text ~900px from the control it
                   was about. -->
              <p class="text-xs text-on-surface-muted">No columns yet</p>
            </div>
          } @else {
            <div class="space-y-1.5 flex-1 overflow-y-auto custom-scrollbar max-h-[24rem]">
              @for (col of columns(); track col.key) {
                <div class="flex items-center gap-2 bg-surface-container-low/40 border border-outline-variant/10 rounded-lg px-3 py-2 group">
                  <span class="material-symbols-outlined text-sm shrink-0"
                        [class]="col.relativePath.length > 1 ? 'text-amber-600' : 'text-tertiary'">
                    {{ col.relativePath.length > 1 ? 'folder_open' : 'label' }}
                  </span>
                  <div class="min-w-0 flex-1">
                    <p class="text-xs font-semibold text-on-surface truncate">
                      @if (col.relativePath.length > 1) {
                        <span class="text-on-surface-variant">{{ col.relativePath[0] }}/</span>
                      }{{ col.displayName }}
                    </p>
                    <p class="text-[10px] text-on-surface-variant flex items-center gap-1.5">
                      <span>ns={{ col.nodeNs }}</span>
                      @if (col.typeProbed) {
                        <span class="px-1.5 rounded bg-surface-container font-mono"
                              [class]="col.inferredType ? 'text-tertiary' : 'text-on-surface-muted'">
                          {{ typeLabel(col) }}
                        </span>
                      } @else {
                        <span class="material-symbols-outlined text-[11px] animate-spin">progress_activity</span>
                      }
                    </p>
                  </div>
                  <!-- Always visible. This was opacity-0 group-hover:opacity-100 with no
                       focus fallback of any kind, so on a touch device you could not
                       remove a draft column at all — the worst of the three
                       hover-gated controls. -->
                  <button (click)="removeColumn(col)"
                          [title]="'Remove ' + col.displayName"
                          class="p-1 rounded text-on-surface-variant hover:text-error hover:bg-error-container/20 focus:outline-none focus-visible:ring-2 focus-visible:ring-primary/40 transition-colors">
                    <span class="material-symbols-outlined text-base">close</span>
                  </button>
                </div>
              }
            </div>
            <p class="text-[11px] text-on-surface-variant mt-3 pt-3 border-t border-outline-variant/10">
              {{ columns().length }} column{{ columns().length === 1 ? '' : 's' }}
              @if (nestedCount()) {
                · {{ nestedCount() }} nested in folders
              }
            </p>
          }
        </section>
      </div>

      <!-- Naming + save -->
      <section class="bg-surface-container-lowest border border-outline-variant/10 rounded-xl p-6 shadow-sm">
        <div class="flex items-center gap-3 mb-5">
          <span class="h-7 w-7 rounded-full bg-primary text-on-primary text-xs font-black flex items-center justify-center">3</span>
          <h2 class="text-sm font-bold uppercase tracking-widest text-on-surface-variant">Identity</h2>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-5 mb-6">
          <div>
            <label class="block text-xs font-semibold text-on-surface-variant mb-1.5">Schema name</label>
            <input [ngModel]="schemaName()" (ngModelChange)="schemaName.set($event)" spellcheck="false" placeholder="AirConditioner"
                   class="w-full rounded-lg border border-outline-variant/30 bg-surface-container-lowest px-3 py-2 text-sm text-on-surface focus:border-primary focus:ring-1 focus:ring-primary/30" />
          </div>
          <div>
            <label class="block text-xs font-semibold text-on-surface-variant mb-1.5">Package</label>
            <input [ngModel]="packagePath()" (ngModelChange)="packagePath.set($event)" spellcheck="false"
                   class="w-full rounded-lg border border-outline-variant/30 bg-surface-container-lowest px-3 py-2 text-sm text-on-surface focus:border-primary focus:ring-1 focus:ring-primary/30" />
          </div>
        </div>

        <div class="flex items-center justify-between gap-4 pt-5 border-t border-outline-variant/10">
          <!-- The reason the button is disabled, beside the button. Bind Devices
               already does this — it put "Remove SA1 to continue" directly next to
               its disabled button — while this screen kept its reason in another
               panel ~900px away, at 2.78:1. Same team, same template, one screen
               apart; this is that treatment adopted. -->
          <p class="text-xs">
            @if (!columns().length) {
              <span class="text-on-surface-muted flex items-center gap-1.5">
                <span class="material-symbols-outlined text-sm">block</span>
                @if (!deviceRoot()) {
                  Mark a template device, then tick at least one node.
                } @else {
                  Tick at least one node inside {{ deviceRoot()!.displayName }}.
                }
              </span>
            } @else if (!schemaName().trim()) {
              <span class="text-on-surface-muted flex items-center gap-1.5">
                <span class="material-symbols-outlined text-sm">edit</span>
                Name the schema to continue.
              </span>
            } @else if (fullClassName()) {
              <span class="text-on-surface-variant">
                Will be created as <code class="font-mono text-primary">{{ fullClassName() }}</code>
              </span>
            }
          </p>
          <button (click)="save()"
                  [disabled]="!canSave()"
                  class="px-6 py-3 font-bold rounded-lg flex items-center gap-2 transition-all"
                  [class]="canSave()
                    ? 'bg-primary text-on-primary shadow-xl shadow-primary/30 hover:brightness-110 active:scale-95'
                    : 'bg-surface-container-highest text-on-surface-muted cursor-not-allowed'">
            <span class="material-symbols-outlined" [class.animate-spin]="saving()">
              {{ saving() ? 'progress_activity' : 'save' }}
            </span>
            {{ saving() ? 'Saving...' : 'Save Schema' }}
          </button>
        </div>
      </section>
    </div>

    <!-- Recursive node tree -->
    <ng-template #treeTpl let-node let-level="level">
      <div [style.padding-left.rem]="level * 1.1">
        <div class="flex items-center gap-1.5 p-1 rounded cursor-pointer hover:bg-white/60 transition-colors group/node"
             [class]="isDeviceRoot(node) ? 'bg-primary/8 ring-1 ring-primary/30' : ''"
             (click)="onNodeClick(node)">
          @if (isVariable(node)) {
            <input type="checkbox" [checked]="isSelected(node)"
                   [disabled]="!isSelectable(node)"
                   [title]="isSelectable(node) ? '' : depthHint(node)"
                   (click)="$event.stopPropagation()"
                   (change)="toggleColumn(node)"
                   class="w-3.5 h-3.5 rounded border-slate-300 text-primary focus:ring-primary mr-0.5 disabled:opacity-30 disabled:cursor-not-allowed" />
          }
          @if (node.hasChildren) {
            <span class="material-symbols-outlined text-lg text-slate-400">
              {{ node.expanded ? 'arrow_drop_down' : 'arrow_right' }}
            </span>
          }
          <span class="material-symbols-outlined text-lg"
                [class.filled]="node.nodeCategory === 'folder'"
                [class]="iconClass(node)">{{ icon(node) }}</span>
          <span class="text-sm" [class]="isSelected(node) ? 'font-bold text-primary' : 'text-on-surface'">
            {{ node.displayName }}
          </span>
          @if (node.loading) {
            <span class="material-symbols-outlined text-xs text-primary animate-spin ml-1">progress_activity</span>
          }

          <!-- Marking the device root is what makes column names device-independent -->
          @if (canBeDeviceRoot(node)) {
            @if (isDeviceRoot(node)) {
              <button (click)="setDeviceRoot(node, $event)" title="Unmark this template device"
                      class="ml-1.5 shrink-0 px-1.5 py-px rounded text-[9px] font-black uppercase tracking-wider bg-primary text-on-primary flex items-center gap-0.5">
                <span class="material-symbols-outlined text-[11px]">memory</span>
                Device
              </button>
            } @else {
              <!-- Always visible too. It was focusable and revealed itself on focus, so
                   WCAG 2.1.1 was met (C1) — the failures were discoverability (tab
                   blindly through every row to find it) and touch. -->
              <button (click)="setDeviceRoot(node, $event)" title="Use this node as the template device"
                      class="ml-1.5 shrink-0 px-1.5 py-px rounded text-[9px] font-bold uppercase tracking-wider border border-outline-variant/40 text-on-surface-variant hover:border-primary hover:text-primary focus:outline-none focus-visible:ring-2 focus-visible:ring-primary/40 transition-colors">
                Set device
              </button>
            }
          }
        </div>
        @if (node.expanded && node.children) {
          @for (child of node.children; track nodeKey(child)) {
            <ng-container *ngTemplateOutlet="treeTpl; context: { $implicit: child, level: level + 1 }" />
          }
        }
      </div>
    </ng-template>
  `,
})
export class SchemaBuilderComponent implements OnInit {
  private api = inject(ApiService);
  private router = inject(Router);
  private config = inject(ConfigService);

  servers = signal<ServerProfile[]>([]);
  serverId = signal('');

  roots = signal<TreeNode[]>([]);
  browsing = signal(false);

  /**
   * The node marked as the template device. Columns are paths relative to it, so
   * until one is marked nothing can be ticked.
   */
  deviceRoot = signal<TreeNode | undefined>(undefined);

  columns = signal<DraftColumn[]>([]);
  schemaName = signal('');
  packagePath = signal('OPCUA.DS');
  saving = signal(false);
  error = signal('');

  nestedCount = computed(() => this.columns().filter((c) => c.relativePath.length > 1).length);

  fullClassName = computed(() => {
    const n = this.schemaName().trim();
    if (!n) return '';
    if (n.includes('.')) return n;
    const p = this.packagePath().trim() || 'OPCUA.DS';
    return `${p}.${n}`;
  });

  canSave = computed(
    () => !this.saving() && this.columns().length > 0 && !!this.schemaName().trim()
  );

  ngOnInit(): void {
    this.servers.set(this.config.getServers());
    const first = this.servers()[0];
    if (first) {
      this.serverId.set(first.id);
      this.loadRoot();
    }
  }

  private server(): ServerProfile | undefined {
    return this.servers().find((s) => s.id === this.serverId());
  }

  loadRoot(): void {
    const srv = this.server();
    if (!srv) return;
    this.browsing.set(true);
    this.error.set('');
    this.roots.set([]);
    // The old root's node objects are about to be discarded, and columns are
    // paths measured against it — neither survives a re-browse.
    this.deviceRoot.set(undefined);
    this.columns.set([]);
    this.api.browse(srv.rootNodeNs ?? 0, srv.rootNodeId || 85, undefined, srv).subscribe({
      next: (nodes) => {
        this.roots.set(nodes.map((n) => ({ ...n, level: 0 }) as TreeNode));
        this.browsing.set(false);
      },
      error: (err) => {
        this.error.set(this.message(err));
        this.browsing.set(false);
      },
    });
  }

  onNodeClick(node: TreeNode): void {
    if (!node.hasChildren) return;
    if (node.expanded) {
      node.expanded = false;
      this.roots.update((r) => [...r]);
      return;
    }
    node.expanded = true;
    if (node.children) {
      this.roots.update((r) => [...r]);
      return;
    }
    node.loading = true;
    this.roots.update((r) => [...r]);
    const srv = this.server();
    this.api.browse(node.nodeNs, node.nodeId, node.nodeIdType, srv).subscribe({
      next: (children) => {
        node.children = children.map((c) => ({ ...c, level: node.level + 1, parentRef: node }) as TreeNode);
        node.loading = false;
        this.roots.update((r) => [...r]);
      },
      error: (err) => {
        node.loading = false;
        this.error.set(this.message(err));
        this.roots.update((r) => [...r]);
      },
    });
  }

  /** Only value-bearing nodes can ever be columns. */
  isVariable(node: TreeNode): boolean {
    return node.nodeCategory === 'variable' || node.nodeCategory === 'property';
  }

  /**
   * A variable is pickable only once it has a path relative to the device root.
   * Shown disabled rather than hidden, so it's clear *why* it can't be ticked.
   */
  isSelectable(node: TreeNode): boolean {
    return this.isVariable(node) && this.pathFromRoot(node) !== null;
  }

  /** Is this node the marked template device? */
  isDeviceRoot(node: TreeNode): boolean {
    const root = this.deviceRoot();
    return !!root && this.nodeKey(root) === this.nodeKey(node);
  }

  /** Can this node serve as a device root? Anything with children can. */
  canBeDeviceRoot(node: TreeNode): boolean {
    return !!node.hasChildren && node.nodeCategory !== 'method';
  }

  /**
   * Mark (or unmark) a node as the template device.
   *
   * Changing the root invalidates every column, because a column's identity is
   * its path relative to that root. Clearing them is honest; silently keeping
   * paths measured against a different root would be the original bug.
   */
  /**
   * Unset the template device. Columns are named relative to it, so they cannot
   * outlive it — clearing both is the honest move rather than leaving columns whose
   * paths no longer mean anything.
   */
  clearDeviceRoot(): void {
    this.deviceRoot.set(undefined);
    this.columns.set([]);
  }

  setDeviceRoot(node: TreeNode, event?: Event): void {
    event?.stopPropagation();
    const wasRoot = this.isDeviceRoot(node);
    if (this.columns().length) this.columns.set([]);
    this.deviceRoot.set(wasRoot ? undefined : node);
    if (!wasRoot && !node.expanded) this.onNodeClick(node);
  }

  /**
   * The column's path relative to the marked device root, or null if the node
   * isn't inside the device (or is too deep to model).
   *
   * `["Temperature"]` for a direct child; `["StateCondition", "LastSeverity"]`
   * for one inside a sub-folder, which the backend models as a %SerialObject.
   * Everything above the root is discarded — that part of the address space is
   * the *device's* path, not the column's.
   */
  private pathFromRoot(node: TreeNode): string[] | null {
    const root = this.deviceRoot();
    if (!root) return null;
    const rootKey = this.nodeKey(root);

    const segments: string[] = [];
    for (let n: TreeNode | undefined = node; n; n = n.parentRef) {
      if (this.nodeKey(n) === rootKey) return segments.reverse();
      segments.push(n.displayName);
      // Deeper than the generator can model as a single %SerialObject level.
      if (segments.length > MAX_DEPTH) return null;
    }
    return null; // Not a descendant of the root at all.
  }

  /** Why a variable under the device can't be picked, for the tooltip. */
  depthHint(node: TreeNode): string {
    if (!this.deviceRoot()) return 'Mark a template device first';
    return `Too deeply nested — columns may be at most ${MAX_DEPTH} levels inside the device`;
  }

  nodeKey(node: TreeNode): string {
    return `${node.nodeNs}:${node.nodeId}`;
  }

  private columnKey(node: TreeNode): string | null {
    const path = this.pathFromRoot(node);
    return path ? path.join('/') : null;
  }

  isSelected(node: TreeNode): boolean {
    const key = this.columnKey(node);
    return !!key && this.columns().some((c) => c.key === key);
  }

  toggleColumn(node: TreeNode): void {
    const key = this.columnKey(node);
    if (!key) return;
    const existing = this.columns().find((c) => c.key === key);
    if (existing) {
      this.columns.update((cols) => cols.filter((c) => c.key !== key));
      return;
    }
    const path = this.pathFromRoot(node)!;
    this.columns.update((cols) => [
      ...cols,
      {
        displayName: node.displayName,
        relativePath: path,
        nodeNs: node.nodeNs,
        nodeId: node.nodeId,
        nodeIdType: node.nodeIdType,
        key,
      },
    ]);

    // Probe the type now rather than only at save, so the column list shows what
    // each column will actually be stored as while there is still time to react.
    this.probeType(key);
  }

  /**
   * Read the template node's value to learn its type.
   *
   * Browse returns only structure — no value, so no type — which is why this
   * needs a separate read. Failure is not an error: the column keeps its %String
   * fallback, which is what happens for an unreadable node at runtime anyway.
   */
  private probeType(key: string): void {
    const col = this.columns().find((c) => c.key === key);
    if (!col) return;
    this.api.read(col.nodeNs, col.nodeId, col.nodeIdType, this.server()).subscribe({
      next: (r) => this.applyType(key, r.inferredType),
      error: () => this.applyType(key, undefined),
    });
  }

  private applyType(key: string, inferredType?: string): void {
    this.columns.update((cols) =>
      cols.map((c) => (c.key === key ? { ...c, inferredType, typeProbed: true } : c))
    );
  }

  typeLabel(col: DraftColumn): string {
    return typeLabel(col.inferredType);
  }

  removeColumn(col: DraftColumn): void {
    this.columns.update((cols) => cols.filter((c) => c.key !== col.key));
  }

  save(): void {
    if (!this.canSave()) return;
    this.saving.set(true);
    this.error.set('');

    // Any column whose probe hasn't finished (or was never started) is read now.
    // Without this, saving quickly after ticking a node would silently store it
    // as %String — the bug this replaces.
    this.ensureTypes()
      .pipe(
        switchMap((cols) => {
          // Most common namespace becomes the schema default; outliers get an override.
          const tally = new Map<number, number>();
          for (const c of cols) tally.set(c.nodeNs, (tally.get(c.nodeNs) || 0) + 1);
          let defaultNs = 0;
          let best = -1;
          for (const [ns, count] of tally) {
            if (count > best) {
              best = count;
              defaultNs = ns;
            }
          }

          return this.api.createSchema({
            name: this.schemaName().trim(),
            packagePath: this.packagePath().trim() || 'OPCUA.DS',
            defaultNamespace: defaultNs,
            columns: cols.map((c) => ({
              displayName: c.displayName,
              relativePath: c.relativePath,
              nodeNs: c.nodeNs,
              inferredType: c.inferredType,
            })),
          });
        })
      )
      .subscribe({
        next: () => {
          this.saving.set(false);
          this.router.navigate(['/schemas']);
        },
        error: (err) => {
          this.error.set(this.message(err));
          this.saving.set(false);
        },
      });
  }

  /**
   * Resolve types for every column that doesn't have one yet, then return the
   * completed list.
   *
   * A failed read leaves inferredType undefined, which the backend maps to
   * %String — the same outcome as before, so a partially unreadable device still
   * produces a usable schema rather than blocking the save.
   */
  private ensureTypes(): Observable<DraftColumn[]> {
    const pending = this.columns().filter((c) => !c.typeProbed);
    if (!pending.length) return of(this.columns());

    const srv = this.server();
    return forkJoin(
      pending.map((c) =>
        this.api.read(c.nodeNs, c.nodeId, c.nodeIdType, srv).pipe(
          map((r) => ({ key: c.key, inferredType: r.inferredType })),
          catchError(() => of({ key: c.key, inferredType: undefined as string | undefined }))
        )
      )
    ).pipe(
      map((results) => {
        for (const r of results) this.applyType(r.key, r.inferredType);
        return this.columns();
      })
    );
  }

  back(): void {
    this.router.navigate(['/schemas']);
  }

  /**
   * The shared icon set (T3.2, item 4). This screen was the real outlier of the
   * three trees: variables were `label` here and `settings_input_component`
   * elsewhere, properties `tag` versus `tune`, objects `category` versus
   * `inventory_2` — so the same address space looked like a different one depending
   * on which screen you were on. The checkbox selection stays, because ticking
   * columns genuinely is a different gesture from picking a device.
   */
  icon = nodeIcon;
  iconClass = (node: TreeNode) => nodeIconClass(node);

  private message(err: any): string {
    return err?.error?.error || err?.message || 'Request failed';
  }
}

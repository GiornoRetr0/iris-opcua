import { Component, inject, signal, computed, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { forkJoin, of, Observable } from 'rxjs';
import { catchError, map, switchMap } from 'rxjs/operators';
import { ApiService } from '../../core/services/api.service';
import { ConfigService } from '../../core/services/config.service';
import { ServerProfile, TreeNode } from '../../core/models/opcua.models';

/** A column being assembled for the new schema. */
interface DraftColumn {
  /** Leaf node name — this is what gets matched against each device at runtime */
  displayName: string;
  /** ["Leaf"] or ["Folder", "Leaf"] */
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

/**
 * Create a reusable device schema by picking nodes off one representative device.
 *
 * The device you browse here is only a *template* — none of its node IDs are
 * captured. What's saved is the column names, which are matched by name against
 * whichever devices get bound later. That's why this page ends at "Save Schema"
 * and never touches a production.
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

          <div class="border border-outline-variant/15 rounded-lg bg-surface-container-low/30 max-h-[26rem] overflow-y-auto custom-scrollbar p-2">
            @if (!roots().length && !browsing()) {
              <p class="text-xs text-on-surface-variant text-center py-8">
                Browse a server, then tick the nodes that make up this device type.
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
              <p class="text-xs opacity-70">No columns yet</p>
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
                              [class]="col.inferredType ? 'text-tertiary' : 'text-on-surface-variant/60'">
                          {{ typeLabel(col) }}
                        </span>
                      } @else {
                        <span class="material-symbols-outlined text-[11px] animate-spin">progress_activity</span>
                      }
                    </p>
                  </div>
                  <button (click)="removeColumn(col)"
                          class="p-1 rounded text-on-surface-variant/40 hover:text-error hover:bg-error-container/20 opacity-0 group-hover:opacity-100 transition-all">
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
          <p class="text-xs text-on-surface-variant">
            @if (fullClassName()) {
              Will be created as <code class="font-mono text-primary">{{ fullClassName() }}</code>
            }
          </p>
          <button (click)="save()"
                  [disabled]="!canSave()"
                  class="px-6 py-3 font-bold rounded-lg flex items-center gap-2 transition-all"
                  [class]="canSave()
                    ? 'bg-primary text-on-primary shadow-xl shadow-primary/30 hover:brightness-110 active:scale-95'
                    : 'bg-surface-container-highest text-on-surface-variant/40 cursor-not-allowed'">
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
        <div class="flex items-center gap-1.5 p-1 rounded cursor-pointer hover:bg-white/60 transition-colors"
             (click)="onNodeClick(node)">
          @if (isSelectable(node)) {
            <input type="checkbox" [checked]="isSelected(node)"
                   (click)="$event.stopPropagation()"
                   (change)="toggleColumn(node)"
                   class="w-3.5 h-3.5 rounded border-slate-300 text-primary focus:ring-primary mr-0.5" />
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

  /** Only value-bearing nodes make sense as columns. */
  isSelectable(node: TreeNode): boolean {
    return node.nodeCategory === 'variable' || node.nodeCategory === 'property';
  }

  /**
   * Build the column's path relative to its device root.
   *
   * A node one level under the browsed root is a flat column; one level deeper
   * becomes a folder-qualified column, which the backend models as a
   * %SerialObject. Deeper nesting is flattened to the nearest folder, matching
   * what the generator supports.
   */
  private relativePath(node: TreeNode): string[] {
    const parent = node.parentRef;
    if (parent && parent.parentRef) {
      return [parent.displayName, node.displayName];
    }
    return [node.displayName];
  }

  nodeKey(node: TreeNode): string {
    return `${node.nodeNs}:${node.nodeId}`;
  }

  private columnKey(node: TreeNode): string {
    return this.relativePath(node).join('/');
  }

  isSelected(node: TreeNode): boolean {
    const key = this.columnKey(node);
    return this.columns().some((c) => c.key === key);
  }

  toggleColumn(node: TreeNode): void {
    const key = this.columnKey(node);
    const existing = this.columns().find((c) => c.key === key);
    if (existing) {
      this.columns.update((cols) => cols.filter((c) => c.key !== key));
      return;
    }
    const path = this.relativePath(node);
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

  icon(node: TreeNode): string {
    switch (node.nodeCategory) {
      case 'folder':
        return 'folder';
      case 'variable':
        return 'label';
      case 'property':
        return 'tag';
      case 'method':
        return 'function';
      default:
        return 'category';
    }
  }

  iconClass(node: TreeNode): string {
    switch (node.nodeCategory) {
      case 'folder':
        return 'text-amber-500';
      case 'variable':
        return 'text-tertiary';
      case 'property':
        return 'text-slate-400';
      default:
        return 'text-slate-500';
    }
  }

  private message(err: any): string {
    return err?.error?.error || err?.message || 'Request failed';
  }
}

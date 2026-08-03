import { Component, inject, signal, input, output, effect, computed, untracked } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ApiService } from '../../core/services/api.service';
import { ConfigService } from '../../core/services/config.service';
import { TreeNode, ServerProfile } from '../../core/models/opcua.models';
import { nodeIcon, nodeIconClass, nodeCategoryLabel } from './node-icons';

/**
 * The OPC UA address-space browser. One tree, used everywhere.
 *
 * There were three implementations across four placements, with divergent icon
 * sets, three selection models and inconsistent `ns=` annotation. This one is the
 * consolidation target because it was already the most careful of the three: it
 * separates the expander from the select target, and marks a container empty once
 * browsed rather than leaving a permanent arrow.
 *
 * Two modes:
 *
 *   `multi`  (default) — a picker inside a form. Selection state is an **input**,
 *            not internal state: the parent owns the chosen set and this component
 *            only reports clicks. That keeps the checkmarks honest when the
 *            parent's list is edited by other means (pasting into a textarea),
 *            rather than letting two copies of the truth drift apart.
 *   `single` — the explorer sidebar. One current node, tracked internally, with a
 *             server-root row per configured server.
 *
 * Set `servers` for the multi-server form (explorer); set `server` for the
 * single-server form (a picker pointed at one endpoint).
 */
@Component({
  selector: 'app-opcua-tree',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="text-sm">
      <!-- Search + bulk expand. Justified without field research: the default root
           is 84, so a fresh install lands beside the full OPC UA Types hierarchy —
           thousands of nodes before any vendor content. -->
      @if (showSearch() && hasAnyNodes()) {
        <div class="flex items-center gap-1.5 mb-2 px-1">
          <div class="relative flex-1 min-w-0">
            <span class="material-symbols-outlined absolute left-2 top-1/2 -translate-y-1/2 text-base text-on-surface-muted pointer-events-none">search</span>
            <input type="text" [ngModel]="query()" (ngModelChange)="query.set($event)"
                   placeholder="Filter loaded nodes"
                   spellcheck="false"
                   class="w-full rounded-md border border-outline-variant/30 bg-surface-container-lowest pl-8 pr-7 py-1.5 text-xs text-on-surface placeholder:text-on-surface-muted focus:border-primary focus:ring-1 focus:ring-primary/30" />
            @if (query()) {
              <button (click)="query.set('')" title="Clear filter"
                      class="absolute right-1.5 top-1/2 -translate-y-1/2 text-on-surface-variant hover:text-primary">
                <span class="material-symbols-outlined text-base">close</span>
              </button>
            }
          </div>
          <button (click)="collapseAll()" title="Collapse all"
                  class="shrink-0 p-1.5 rounded-md text-on-surface-variant hover:text-primary hover:bg-surface-variant/50 transition-colors">
            <span class="material-symbols-outlined text-lg">unfold_less</span>
          </button>
        </div>

        @if (query()) {
          <!-- The address space is browsed lazily, so a filter can only see what has
               been expanded. Saying so beats implying a whole-tree search. -->
          <p class="px-1 mb-2 text-[11px] text-on-surface-muted">
            {{ matchCount() }} of {{ loadedCount() }} loaded
            node{{ loadedCount() === 1 ? '' : 's' }} match. Expand a folder to search deeper.
          </p>
        }
      }

      @if (!server() && !servers().length) {
        <p class="text-xs text-on-surface-variant text-center py-8">Select a server to browse.</p>
      } @else if (loading() && !roots().length && !serverRoots().length) {
        <div class="flex items-center justify-center gap-2 py-8 text-on-surface-variant">
          <span class="material-symbols-outlined text-lg animate-spin">progress_activity</span>
          <span class="text-xs">Browsing {{ server()?.name }}...</span>
        </div>
      } @else if (error()) {
        <div class="flex flex-col items-center gap-2 py-8 px-4 text-center">
          <span class="material-symbols-outlined text-2xl text-error/60">cloud_off</span>
          <p class="text-xs text-on-surface-variant">{{ error() }}</p>
          <button (click)="reload()"
                  class="text-[11px] font-bold uppercase tracking-wider text-primary hover:underline">
            Retry
          </button>
        </div>
      } @else if (serverRoots().length) {
        <!-- Multi-server form: one collapsible root per configured server. -->
        @for (sr of serverRoots(); track sr.server.id) {
          <div class="flex items-center gap-1.5 rounded-md transition-colors hover:bg-surface-variant/40">
            <button (click)="toggleServerRoot(sr)"
                    class="flex items-center gap-1.5 min-w-0 flex-1 text-left px-2 py-1.5">
              <span class="material-symbols-outlined text-sm text-on-surface-muted shrink-0">
                {{ sr.loading ? 'progress_activity' : (sr.expanded ? 'arrow_drop_down' : 'arrow_right') }}
              </span>
              <span class="material-symbols-outlined text-lg text-primary shrink-0">dns</span>
              <span class="font-medium text-on-surface truncate flex-1" [title]="sr.server.url">{{ sr.server.name }}</span>
              <span class="inline-flex items-center gap-0.5 px-1.5 py-0.5 rounded text-[9px] font-semibold shrink-0"
                    [class]="sr.server.securityMode === 3
                      ? 'bg-emerald-50 text-emerald-700'
                      : 'bg-amber-50 text-amber-700'"
                    [title]="sr.server.securityMode === 3
                      ? 'Sign and Encrypt (Basic256Sha256)'
                      : 'No message security — traffic is unencrypted and unsigned'">
                <span class="material-symbols-outlined text-[10px]">{{ sr.server.securityMode === 3 ? 'lock' : 'lock_open' }}</span>
                {{ sr.server.securityMode === 3 ? 'Sign & Encrypt' : 'Unsecured' }}
              </span>
            </button>
          </div>

          @if (sr.expanded) {
            @if (sr.error) {
              <p [style.padding-left.rem]="1.1" class="px-2 py-1 text-[11px] text-error">{{ sr.error }}</p>
            }
            @for (node of visible(sr.roots); track nodeKey(node)) {
              <ng-container *ngTemplateOutlet="tpl; context: { $implicit: node, level: 1 }" />
            }
            @if (sr.roots.length && !visible(sr.roots).length) {
              <p [style.padding-left.rem]="1.1" class="px-2 py-1 text-[11px] text-on-surface-muted italic">
                No loaded node matches.
              </p>
            }
          }
        }
      } @else if (!roots().length) {
        <p class="text-xs text-on-surface-variant text-center py-8">No nodes found at the server root.</p>
      } @else {
        @for (node of visible(roots()); track nodeKey(node)) {
          <ng-container *ngTemplateOutlet="tpl; context: { $implicit: node, level: 0 }" />
        }
        @if (!visible(roots()).length) {
          <p class="px-2 py-4 text-[11px] text-on-surface-muted italic text-center">No loaded node matches.</p>
        }
      }
    </div>

    <ng-template #tpl let-node let-level="level">
      <div [style.padding-left.rem]="level * 1.1">
        <div class="flex items-center gap-1.5 px-2 py-1.5 rounded-md transition-colors group"
             [class]="isSelected(node) ? 'bg-primary/10' : 'hover:bg-surface-variant/40'">
          <!-- Expander, kept separate from the row: drilling into a container isn't
               the same gesture as choosing it. A real button, so arrow keys and
               Enter reach it — this was a bare <span> with a (click) in the
               explorer's tree, which was a genuine keyboard gap. -->
          @if (node.hasChildren) {
            <button (click)="toggleExpand(node, $event)"
                    [attr.aria-expanded]="!!node.expanded"
                    [title]="node.expanded ? 'Collapse' : 'Expand'"
                    class="shrink-0 flex items-center text-on-surface-variant hover:text-primary focus:outline-none focus-visible:ring-2 focus-visible:ring-primary/40 rounded">
              <span class="material-symbols-outlined text-lg"
                    [class.animate-spin]="node.loading">
                {{ node.loading ? 'progress_activity' : (node.expanded ? 'arrow_drop_down' : 'arrow_right') }}
              </span>
            </button>
          } @else {
            <span class="w-[18px] shrink-0"></span>
          }

          <button (click)="onRowClick(node)"
                  (keydown)="onRowKeydown(node, $event)"
                  [title]="rowTitle(node)"
                  class="flex items-center gap-1.5 min-w-0 flex-1 text-left cursor-pointer focus:outline-none focus-visible:ring-2 focus-visible:ring-primary/40 rounded">
            <span class="material-symbols-outlined text-lg shrink-0"
                  [class]="iconClass(node)"
                  [class.filled]="node.nodeCategory === 'folder'">{{ icon(node) }}</span>
            <span class="truncate"
                  [class]="isSelected(node) ? 'font-semibold text-primary' : 'text-on-surface'">
              {{ node.displayName }}
            </span>
            <span class="text-[10px] font-mono text-on-surface-muted shrink-0 hidden sm:inline">
              ns={{ node.nodeNs }}
            </span>
            @if (childCount(node) !== null) {
              <span class="text-[10px] font-mono text-on-surface-muted shrink-0"
                    [title]="childCount(node) + ' children'">({{ childCount(node) }})</span>
            }

            @if (mode() === 'multi') {
              @if (isSelected(node)) {
                <span class="material-symbols-outlined text-base text-primary ml-auto shrink-0">check_circle</span>
              } @else {
                <!-- Always visible, not hover-gated. Touch fires neither hover nor
                     focus, and a keyboard user had to tab blindly to find it. -->
                <span class="material-symbols-outlined text-base text-on-surface-variant/40 ml-auto shrink-0 group-hover:text-primary transition-colors">add_circle</span>
              }
            } @else if (isSelected(node)) {
              <span class="material-symbols-outlined text-base text-primary ml-auto shrink-0">check_circle</span>
            }
          </button>
        </div>

        @if (node.expanded && node.children) {
          @if (!node.children.length && !node.loading) {
            <p [style.padding-left.rem]="(level + 1) * 1.1"
               class="px-2 py-1 text-[11px] text-on-surface-muted italic">empty</p>
          }
          @for (child of visible(node.children); track nodeKey(child)) {
            <ng-container *ngTemplateOutlet="tpl; context: { $implicit: child, level: level + 1 }" />
          }
        }
      </div>
    </ng-template>
  `,
})
export class OpcuaTreeComponent {
  private api = inject(ApiService);
  private config = inject(ConfigService);

  /** Single-server form: browse exactly this endpoint. */
  server = input<ServerProfile | undefined>(undefined);
  /** Multi-server form: one collapsible root row per server. */
  servers = input<ServerProfile[]>([]);
  mode = input<'single' | 'multi'>('multi');
  showSearch = input(true);

  /**
   * Keys of nodes to show as chosen, as produced by `nodeKey()`. Owned by the
   * parent in `multi` mode so it can be derived from whatever the real model is.
   */
  selectedKeys = input<ReadonlySet<string>>(new Set<string>());

  /** A node's row was clicked. The parent decides whether that adds or removes. */
  nodeToggled = output<TreeNode>();
  /** `single` mode: the current node changed. */
  nodeSelected = output<TreeNode>();

  roots = signal<TreeNode[]>([]);
  serverRoots = signal<ServerRootEntry[]>([]);
  loading = signal(false);
  error = signal('');
  query = signal('');
  /** `single` mode's current node. */
  currentNode = signal<TreeNode | null>(null);

  constructor() {
    // Re-browse whenever the caller points us at a different server. Switching
    // servers must clear the old address space rather than leave stale nodes that
    // would resolve against the wrong endpoint.
    //
    // The whole body is wrapped in untracked(): it *writes* the same signals a
    // naive read would subscribe to, and `toggleServerRoot` writes `serverRoots`
    // too. Tracking those writes made the effect re-trigger itself without end,
    // and because each pass rebuilt the entries with `roots: []` the re-entered
    // `toggleServerRoot` cleared its own already-browsed guard and fired a fresh
    // browse request every iteration — an unbounded request loop that stalled the
    // tab. It reproduced only with exactly one configured server, which is the
    // ordinary case. The dependency this effect *should* have is the two inputs,
    // so they are read outside the untracked block and nothing else is.
    effect(() => {
      const srv = this.server();
      const list = this.servers();

      untracked(() => {
        this.error.set('');

        if (list.length) {
          this.roots.set([]);
          const entries = list.map((s) => ({
            server: s, roots: [] as TreeNode[], expanded: false, loading: false, error: '',
          }));
          this.serverRoots.set(entries);
          // Auto-expand a lone server: there is no choice to present.
          if (entries.length === 1) this.toggleServerRoot(entries[0]);
          return;
        }

        this.serverRoots.set([]);
        this.roots.set([]);
        if (srv) this.load(srv);
      });
    });
  }

  /** Stable identity for a node, and the key format `selectedKeys` expects. */
  static keyOf(nodeNs: number, nodeId: string | number): string {
    return `${nodeNs}:${nodeId}`;
  }

  nodeKey(node: TreeNode): string {
    return OpcuaTreeComponent.keyOf(node.nodeNs, node.nodeId);
  }

  isSelected(node: TreeNode): boolean {
    if (this.mode() === 'single') return this.currentNode() === node;
    return this.selectedKeys().has(this.nodeKey(node));
  }

  icon = nodeIcon;
  iconClass = (node: TreeNode) => nodeIconClass(node, this.isSelected(node));

  rowTitle(node: TreeNode): string {
    return `${nodeCategoryLabel(node)} — ns=${node.nodeNs};${node.nodeId}`;
  }

  /**
   * How many children a node has, once known. Null before it is browsed, so the
   * count never guesses — an unexpanded folder shows nothing rather than "(0)".
   */
  childCount(node: TreeNode): number | null {
    return node.children ? node.children.length : null;
  }

  // ── Search ────────────────────────────────────────────────────────────────
  // Client-side over loaded nodes only. The address space is browsed lazily, so
  // that is all there is to filter; the caption says so rather than implying the
  // whole tree was searched.

  /** A node survives the filter if it matches, or if any loaded descendant does. */
  private matches(node: TreeNode, q: string): boolean {
    if (String(node.displayName ?? '').toLowerCase().includes(q)) return true;
    return (node.children ?? []).some((c) => this.matches(c, q));
  }

  visible(nodes: TreeNode[] | undefined): TreeNode[] {
    const list = nodes ?? [];
    const q = this.query().trim().toLowerCase();
    if (!q) return list;
    return list.filter((n) => this.matches(n, q));
  }

  private countLoaded(nodes: TreeNode[]): number {
    return nodes.reduce((n, node) => n + 1 + this.countLoaded(node.children ?? []), 0);
  }

  private countMatches(nodes: TreeNode[], q: string): number {
    return nodes.reduce(
      (n, node) =>
        n +
        (String(node.displayName ?? '').toLowerCase().includes(q) ? 1 : 0) +
        this.countMatches(node.children ?? [], q),
      0
    );
  }

  private allTopLevel(): TreeNode[] {
    const fromServers = this.serverRoots().flatMap((sr) => sr.roots);
    return fromServers.length ? fromServers : this.roots();
  }

  hasAnyNodes = computed(() => this.allTopLevel().length > 0);
  loadedCount = computed(() => this.countLoaded(this.allTopLevel()));
  matchCount = computed(() => {
    const q = this.query().trim().toLowerCase();
    return q ? this.countMatches(this.allTopLevel(), q) : this.loadedCount();
  });

  collapseAll(): void {
    const walk = (nodes: TreeNode[]) => {
      for (const n of nodes) {
        n.expanded = false;
        if (n.children) walk(n.children);
      }
    };
    walk(this.allTopLevel());
    this.serverRoots.update((list) => list.map((sr) => ({ ...sr, expanded: false })));
    this.roots.update((r) => [...r]);
  }

  // ── Loading ───────────────────────────────────────────────────────────────

  reload(): void {
    const srv = this.server();
    if (srv) this.load(srv);
  }

  private load(srv: ServerProfile): void {
    this.loading.set(true);
    this.error.set('');
    this.api.browse(srv.rootNodeNs ?? 0, srv.rootNodeId || 85, undefined, srv).subscribe({
      next: (nodes) => {
        this.roots.set(nodes.map((n) => ({ ...n, level: 0 }) as TreeNode));
        this.loading.set(false);
      },
      error: (err) => {
        this.error.set(err?.error?.error || err?.message || 'Could not browse this server');
        this.loading.set(false);
      },
    });
  }

  toggleServerRoot(sr: ServerRootEntry): void {
    sr.expanded = !sr.expanded;
    this.serverRoots.update((r) => [...r]);
    if (!sr.expanded || sr.roots.length) return;

    sr.loading = true;
    sr.error = '';
    this.serverRoots.update((r) => [...r]);

    this.api.browse(sr.server.rootNodeNs ?? 0, sr.server.rootNodeId || 85, undefined, sr.server).subscribe({
      next: (nodes) => {
        sr.roots = nodes.map((n) => ({ ...n, level: 1, serverId: sr.server.id }) as TreeNode);
        sr.loading = false;
        this.serverRoots.update((r) => [...r]);
      },
      error: (err) => {
        sr.loading = false;
        sr.error = err?.error?.error || err?.message || 'Could not browse this server';
        this.serverRoots.update((r) => [...r]);
      },
    });
  }

  private refresh(): void {
    this.roots.update((r) => [...r]);
    this.serverRoots.update((r) => [...r]);
  }

  onRowClick(node: TreeNode): void {
    if (this.mode() === 'single') {
      this.currentNode.set(node);
      this.nodeSelected.emit(node);
      // Selecting a container also opens it: in a browser, choosing a folder and
      // looking inside it are the same intent.
      if (node.hasChildren && !node.expanded) this.toggleExpand(node);
      return;
    }
    this.nodeToggled.emit(node);
  }

  /**
   * Arrow-key navigation over the rendered rows. Right expands (or steps in), left
   * collapses (or steps out), up/down move, Enter selects — the conventions a tree
   * is expected to follow, and none of which existed in any of the three trees.
   */
  onRowKeydown(node: TreeNode, event: KeyboardEvent): void {
    const key = event.key;
    if (key === 'ArrowRight') {
      event.preventDefault();
      if (node.hasChildren && !node.expanded) this.toggleExpand(node);
      else this.focusRow(1, event);
      return;
    }
    if (key === 'ArrowLeft') {
      event.preventDefault();
      if (node.expanded) this.toggleExpand(node);
      else this.focusRow(-1, event);
      return;
    }
    if (key === 'ArrowDown') { event.preventDefault(); this.focusRow(1, event); return; }
    if (key === 'ArrowUp') { event.preventDefault(); this.focusRow(-1, event); return; }
  }

  /**
   * Move focus by DOM order rather than by walking the model — the rendered rows
   * are exactly the navigable ones, including across server roots, so the DOM is
   * the more faithful source here.
   */
  private focusRow(delta: number, event: KeyboardEvent): void {
    const current = event.target as HTMLElement;
    const container = current.closest('app-opcua-tree') ?? document;
    const rows = [...container.querySelectorAll<HTMLElement>('button.flex-1')];
    const i = rows.indexOf(current);
    if (i === -1) return;
    rows[Math.max(0, Math.min(rows.length - 1, i + delta))]?.focus();
  }

  toggleExpand(node: TreeNode, event?: MouseEvent): void {
    if (event) event.stopPropagation();
    if (!node.hasChildren) return;

    if (node.expanded) {
      node.expanded = false;
      this.refresh();
      return;
    }

    node.expanded = true;
    if (node.children) {
      this.refresh();
      return;
    }

    node.loading = true;
    this.refresh();

    this.api.browse(node.nodeNs, node.nodeId, node.nodeIdType, this.serverFor(node)).subscribe({
      next: (children) => {
        node.children = children.map(
          (c) =>
            ({
              ...c,
              level: (node.level ?? 0) + 1,
              serverId: node.serverId,
              // Threaded so the detail pane can render a real path.
              parentRef: node,
            }) as TreeNode
        );
        // A container that turns out to be empty shouldn't keep offering an arrow.
        if (!children.length) node.hasChildren = false;
        node.loading = false;
        this.refresh();
      },
      error: () => {
        node.loading = false;
        node.children = [];
        this.refresh();
      },
    });
  }

  /** Which endpoint a node belongs to — matters once several are in one tree. */
  private serverFor(node: TreeNode): ServerProfile | undefined {
    if (node.serverId) return this.config.getServer(node.serverId);
    return this.server();
  }
}

/** A server's row in the multi-server form. */
interface ServerRootEntry {
  server: ServerProfile;
  roots: TreeNode[];
  expanded: boolean;
  loading: boolean;
  error: string;
}

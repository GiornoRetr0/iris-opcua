import { Component, inject, signal, input, output, effect } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ApiService } from '../../core/services/api.service';
import { TreeNode, ServerProfile } from '../../core/models/opcua.models';

/**
 * An embeddable OPC UA address-space browser for a single server.
 *
 * Distinct from <code>app-node-tree</code>, which is the explorer's sidebar: that
 * one owns its own server list and spans every configured server. This one browses
 * exactly the server it is handed, which is what a picker inside a form needs.
 *
 * Selection state is an <em>input</em>, not internal state — the parent owns the
 * set of chosen nodes and this component only reports clicks. That keeps the
 * checkmarks honest when the parent's list is edited by other means (pasting into
 * a textarea, say) rather than letting two copies of the truth drift apart.
 */
@Component({
  selector: 'app-opcua-tree',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="text-sm">
      @if (!server()) {
        <p class="text-xs text-on-surface-variant text-center py-8">Select a server to browse.</p>
      } @else if (loading() && !roots().length) {
        <div class="flex items-center justify-center gap-2 py-8 text-on-surface-variant">
          <span class="material-symbols-outlined text-lg animate-spin">progress_activity</span>
          <span class="text-xs">Browsing {{ server()!.name }}...</span>
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
      } @else if (!roots().length) {
        <p class="text-xs text-on-surface-variant text-center py-8">No nodes found at the server root.</p>
      } @else {
        @for (node of roots(); track nodeKey(node)) {
          <ng-container *ngTemplateOutlet="tpl; context: { $implicit: node, level: 0 }" />
        }
      }
    </div>

    <ng-template #tpl let-node let-level="level">
      <div [style.padding-left.rem]="level * 1.1">
        <div class="flex items-center gap-1.5 px-2 py-1.5 rounded-md transition-colors group"
             [class]="isSelected(node) ? 'bg-primary/10' : 'hover:bg-surface-variant/40'">
          <!-- Expander. Kept separate from the row so drilling into a container
               isn't the same gesture as choosing it. -->
          @if (node.hasChildren) {
            <button (click)="toggleExpand(node, $event)"
                    class="shrink-0 flex items-center text-on-surface-variant hover:text-primary">
              <span class="material-symbols-outlined text-lg">
                {{ node.loading ? 'progress_activity' : (node.expanded ? 'arrow_drop_down' : 'arrow_right') }}
              </span>
            </button>
          } @else {
            <span class="w-[18px] shrink-0"></span>
          }

          <button (click)="nodeToggled.emit(node)"
                  class="flex items-center gap-1.5 min-w-0 flex-1 text-left cursor-pointer">
            <span class="material-symbols-outlined text-lg shrink-0"
                  [class]="iconClass(node)"
                  [class.filled]="node.nodeCategory === 'folder'">{{ icon(node) }}</span>
            <span class="truncate"
                  [class]="isSelected(node) ? 'font-semibold text-primary' : 'text-on-surface'">
              {{ node.displayName }}
            </span>
            <span class="text-[10px] font-mono text-on-surface-variant/70 shrink-0 hidden sm:inline">
              ns={{ node.nodeNs }}
            </span>

            @if (isSelected(node)) {
              <span class="material-symbols-outlined text-base text-primary ml-auto shrink-0">check_circle</span>
            } @else {
              <span class="material-symbols-outlined text-base text-on-surface-variant/30 ml-auto shrink-0 opacity-0 group-hover:opacity-100 transition-opacity">add_circle</span>
            }
          </button>
        </div>

        @if (node.expanded && node.children) {
          @if (!node.children.length && !node.loading) {
            <p [style.padding-left.rem]="(level + 1) * 1.1"
               class="px-2 py-1 text-[11px] text-on-surface-variant/70 italic">empty</p>
          }
          @for (child of node.children; track nodeKey(child)) {
            <ng-container *ngTemplateOutlet="tpl; context: { $implicit: child, level: level + 1 }" />
          }
        }
      </div>
    </ng-template>
  `,
})
export class OpcuaTreeComponent {
  private api = inject(ApiService);

  server = input<ServerProfile | undefined>(undefined);

  /**
   * Keys of nodes to show as chosen, as produced by <code>nodeKey()</code>.
   * Owned by the parent so it can be derived from whatever the real model is.
   */
  selectedKeys = input<ReadonlySet<string>>(new Set<string>());

  /** A node's row was clicked. The parent decides whether that adds or removes. */
  nodeToggled = output<TreeNode>();

  roots = signal<TreeNode[]>([]);
  loading = signal(false);
  error = signal('');

  constructor() {
    // Re-browse whenever the caller points us at a different server. Switching
    // servers must clear the old address space rather than leave stale nodes
    // that would resolve against the wrong endpoint.
    effect(() => {
      const srv = this.server();
      this.roots.set([]);
      this.error.set('');
      if (srv) this.load(srv);
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
    return this.selectedKeys().has(this.nodeKey(node));
  }

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

  toggleExpand(node: TreeNode, event: MouseEvent): void {
    event.stopPropagation();
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

    this.api.browse(node.nodeNs, node.nodeId, node.nodeIdType, this.server()).subscribe({
      next: (children) => {
        node.children = children.map(
          (c) => ({ ...c, level: (node.level ?? 0) + 1, parentRef: node }) as TreeNode
        );
        // A container that turns out to be empty shouldn't keep offering an arrow.
        if (!children.length) node.hasChildren = false;
        node.loading = false;
        this.roots.update((r) => [...r]);
      },
      error: () => {
        node.loading = false;
        node.children = [];
        this.roots.update((r) => [...r]);
      },
    });
  }

  icon(node: TreeNode): string {
    switch (node.nodeCategory) {
      case 'folder': return 'folder';
      case 'object': return 'inventory_2';
      case 'variable': return 'settings_input_component';
      case 'property': return 'tune';
      case 'method': return 'function';
      default: return 'circle';
    }
  }

  iconClass(node: TreeNode): string {
    if (this.isSelected(node)) return 'text-primary';
    switch (node.nodeCategory) {
      case 'folder': return 'text-amber-500';
      case 'object': return 'text-amber-600';
      case 'variable': return 'text-tertiary';
      case 'property': return 'text-slate-400';
      default: return 'text-slate-500';
    }
  }
}

import { Component, inject, signal, output, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ApiService } from '../../../core/services/api.service';
import { ConfigService } from '../../../core/services/config.service';
import { TreeNode, ServerProfile } from '../../../core/models/opcua.models';

/** Virtual server root node shown at the top level of the tree */
interface ServerRoot {
  server: ServerProfile;
  roots: TreeNode[];
  expanded: boolean;
  loading: boolean;
}

@Component({
  selector: 'app-node-tree',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="pt-4 border-t border-slate-200/50">
      <p class="px-3 mb-2 text-[10px] font-bold uppercase tracking-widest text-on-surface-variant opacity-70">
        Address Space
      </p>
      <div class="text-sm space-y-0.5">
        @if (serverRoots().length === 0) {
          <div class="flex items-center gap-2 px-3 py-2 text-on-surface-variant">
            <span class="material-symbols-outlined text-sm">info</span>
            <span class="text-xs">No servers configured</span>
          </div>
        }
        @for (sr of serverRoots(); track sr.server.id) {
          <!-- Server root -->
          <div class="flex items-center gap-1.5 px-3 py-1.5 rounded-md cursor-pointer transition-all hover:bg-slate-200/50"
               (click)="toggleServerRoot(sr)">
            <span class="material-symbols-outlined text-sm text-slate-400">
              {{ sr.expanded ? 'arrow_drop_down' : 'arrow_right' }}
            </span>
            <span class="material-symbols-outlined text-lg text-primary">dns</span>
            <span class="font-medium text-slate-700 truncate flex-1" [title]="sr.server.url">{{ sr.server.name }}</span>
            <span class="inline-flex items-center gap-0.5 px-1 py-0.5 rounded text-[9px] font-semibold shrink-0"
                  [class]="sr.server.securityMode === 3
                    ? 'bg-emerald-50 text-emerald-700'
                    : 'bg-amber-50 text-amber-700'">
              <span class="material-symbols-outlined text-[10px]">{{ sr.server.securityMode === 3 ? 'lock' : 'lock_open' }}</span>
            </span>
          </div>

          @if (sr.expanded) {
            @if (sr.loading) {
              <div class="flex items-center gap-2 px-3 py-1 text-on-surface-variant" style="padding-left: 2.5rem">
                <span class="material-symbols-outlined text-xs animate-spin">progress_activity</span>
                <span class="text-[11px]">Loading...</span>
              </div>
            }
            @for (node of sr.roots; track nodeKey(node)) {
              <ng-container *ngTemplateOutlet="treeNodeTpl; context: { $implicit: node, level: 1 }" />
            }
          }
        }
      </div>
    </div>

    <!-- Recursive tree node template -->
    <ng-template #treeNodeTpl let-node let-level="level">
      <div [style.padding-left.rem]="level * 1.25">
        <div class="flex items-center gap-1.5 px-3 py-1.5 rounded-md cursor-pointer transition-all"
             [class]="node === selectedNode()
               ? 'bg-blue-100/70 border-l-4 border-primary'
               : 'hover:bg-slate-200/50'"
             (click)="onNodeClick(node)">
          <!-- Expand/collapse arrow -->
          @if (node.hasChildren) {
            <span class="material-symbols-outlined text-sm"
                  [class]="node === selectedNode() ? 'text-primary' : 'text-slate-400'"
                  (click)="toggleExpand(node, $event)">
              {{ node.expanded ? 'arrow_drop_down' : 'arrow_right' }}
            </span>
          } @else {
            <span class="w-[18px]"></span>
          }

          <!-- Icon -->
          <span class="material-symbols-outlined text-lg"
                [class]="getNodeIconClass(node)"
                [class.filled]="node.nodeCategory === 'folder'">
            {{ getNodeIcon(node) }}
          </span>

          <!-- Label -->
          <span [class]="node === selectedNode() ? 'font-semibold text-primary' : getNodeTextClass(node)">
            {{ node.displayName }}
          </span>

          <!-- Selected check -->
          @if (node === selectedNode()) {
            <span class="material-symbols-outlined text-sm text-primary ml-auto">check_circle</span>
          }
        </div>

        <!-- Children -->
        @if (node.expanded && node.children) {
          @if (node.loading) {
            <div [style.padding-left.rem]="(level + 1) * 1.25"
                 class="flex items-center gap-2 px-3 py-1 text-on-surface-variant">
              <span class="material-symbols-outlined text-xs animate-spin">progress_activity</span>
              <span class="text-[11px]">Loading...</span>
            </div>
          }
          @for (child of node.children; track nodeKey(child)) {
            <ng-container *ngTemplateOutlet="treeNodeTpl; context: { $implicit: child, level: level + 1 }" />
          }
        }
      </div>
    </ng-template>
  `,
})
export class NodeTreeComponent implements OnInit {
  private api = inject(ApiService);
  private config = inject(ConfigService);

  serverRoots = signal<ServerRoot[]>([]);
  selectedNode = signal<TreeNode | null>(null);

  nodeSelected = output<TreeNode>();

  ngOnInit(): void {
    this.loadServerRoots();
  }

  nodeKey(node: TreeNode): string {
    return `${node.serverId || ''}:${node.nodeNs}:${node.nodeId}:${node.nodeIdType}`;
  }

  private loadServerRoots(): void {
    const servers = this.config.getServers();
    const cfg = this.config.get();
    if (!cfg.apiBaseUrl) return;

    // Create a server root entry for each server
    const roots: ServerRoot[] = servers.map(server => ({
      server,
      roots: [],
      expanded: false,
      loading: false,
    }));
    this.serverRoots.set(roots);

    // Auto-expand if only one server
    if (roots.length === 1) {
      this.toggleServerRoot(roots[0]);
    }
  }

  toggleServerRoot(sr: ServerRoot): void {
    sr.expanded = !sr.expanded;
    this.serverRoots.update(r => [...r]);

    if (sr.expanded && sr.roots.length === 0) {
      sr.loading = true;
      this.serverRoots.update(r => [...r]);

      this.api.browse(sr.server.rootNodeNs, sr.server.rootNodeId, undefined, sr.server).subscribe({
        next: (nodes) => {
          sr.roots = nodes.map(n => ({ ...n, level: 1, serverId: sr.server.id }));
          sr.loading = false;
          this.serverRoots.update(r => [...r]);
        },
        error: () => {
          sr.loading = false;
          this.serverRoots.update(r => [...r]);
        },
      });
    }
  }

  onNodeClick(node: TreeNode): void {
    this.selectedNode.set(node);
    this.nodeSelected.emit(node);
    if (node.hasChildren && !node.expanded) {
      this.toggleExpand(node);
    }
  }

  toggleExpand(node: TreeNode, event?: MouseEvent): void {
    if (event) event.stopPropagation();
    if (!node.hasChildren) return;

    if (node.expanded) {
      node.expanded = false;
      this.serverRoots.update(r => [...r]);
      return;
    }

    node.expanded = true;
    if (node.children && node.children.length > 0) {
      this.serverRoots.update(r => [...r]);
      return;
    }

    node.loading = true;
    this.serverRoots.update(r => [...r]);

    // Find the server profile for this node
    const server = this.findServerForNode(node);

    this.api.browse(node.nodeNs, node.nodeId, node.nodeIdType, server).subscribe({
      next: (children) => {
        node.children = children.map(c => ({
          ...c,
          level: (node.level ?? 0) + 1,
          serverId: node.serverId,
        }));
        if (children.length === 0) {
          node.hasChildren = false;
          node.expanded = false;
        }
        node.loading = false;
        this.serverRoots.update(r => [...r]);
      },
      error: () => {
        node.loading = false;
        node.children = [];
        this.serverRoots.update(r => [...r]);
      },
    });
  }

  private findServerForNode(node: TreeNode): ServerProfile | undefined {
    if (!node.serverId) return undefined;
    return this.config.getServer(node.serverId);
  }

  getNodeIcon(node: TreeNode): string {
    switch (node.nodeCategory) {
      case 'folder': return 'folder';
      case 'object': return 'inventory_2';
      case 'variable': return 'settings_input_component';
      case 'property': return 'tune';
      case 'method': return 'function';
      default: return 'circle';
    }
  }

  getNodeIconClass(node: TreeNode): string {
    if (node === this.selectedNode()) return 'text-primary';
    switch (node.nodeCategory) {
      case 'folder': return 'text-primary';
      case 'object': return 'text-amber-600';
      case 'variable': return 'text-slate-400';
      case 'property': return 'text-slate-400';
      default: return 'text-slate-500';
    }
  }

  getNodeTextClass(node: TreeNode): string {
    switch (node.nodeCategory) {
      case 'folder': return 'font-medium text-slate-700';
      case 'property': return 'text-xs italic text-slate-500';
      default: return 'text-slate-600';
    }
  }
}

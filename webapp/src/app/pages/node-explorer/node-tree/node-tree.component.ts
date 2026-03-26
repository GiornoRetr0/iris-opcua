import { Component, inject, signal, output, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ApiService } from '../../../core/services/api.service';
import { ConfigService } from '../../../core/services/config.service';
import { TreeNode, OpcuaNode } from '../../../core/models/opcua.models';

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
        @if (loading()) {
          <div class="flex items-center gap-2 px-3 py-2 text-on-surface-variant">
            <span class="material-symbols-outlined text-sm animate-spin">progress_activity</span>
            <span class="text-xs">Loading...</span>
          </div>
        }
        @for (node of roots(); track nodeKey(node)) {
          <ng-container *ngTemplateOutlet="treeNodeTpl; context: { $implicit: node, level: 0 }" />
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

  roots = signal<TreeNode[]>([]);
  loading = signal(false);
  selectedNode = signal<TreeNode | null>(null);

  nodeSelected = output<TreeNode>();

  ngOnInit(): void {
    this.loadRoots();
  }

  nodeKey(node: TreeNode): string {
    return `${node.nodeNs}:${node.nodeId}:${node.nodeIdType}`;
  }

  loadRoots(): void {
    const cfg = this.config.get();
    if (!cfg.apiBaseUrl || !cfg.serverUrl) return;
    this.loading.set(true);
    this.api.browse(cfg.rootNodeNs, cfg.rootNodeId, undefined).subscribe({
      next: (nodes) => {
        this.roots.set(nodes.map((n) => ({ ...n, level: 0 })));
        this.loading.set(false);
      },
      error: () => this.loading.set(false),
    });
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
      this.roots.update((r) => [...r]); // trigger signal
      return;
    }

    node.expanded = true;
    if (node.children && node.children.length > 0) {
      this.roots.update((r) => [...r]);
      return;
    }

    node.loading = true;
    this.roots.update((r) => [...r]);

    this.api.browse(node.nodeNs, node.nodeId, node.nodeIdType).subscribe({
      next: (children) => {
        node.children = children.map((c) => ({ ...c, level: (node.level ?? 0) + 1 }));
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

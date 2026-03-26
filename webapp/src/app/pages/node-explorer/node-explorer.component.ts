import { Component, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { NodeTreeComponent } from './node-tree/node-tree.component';
import { NodeDetailComponent } from './node-detail/node-detail.component';
import { TreeNode } from '../../core/models/opcua.models';

@Component({
  selector: 'app-node-explorer',
  standalone: true,
  imports: [CommonModule, NodeTreeComponent, NodeDetailComponent],
  template: `
    <div class="flex min-h-screen">
      <!-- Left sidebar: tree inside the side nav area -->
      <div class="w-0 md:w-0">
        <!-- Tree is rendered in the side nav area via the aside below -->
      </div>

      <!-- Tree panel (overlaps with side nav conceptually - rendered as a nested sidebar panel) -->
      <aside class="fixed left-64 top-16 bottom-0 w-64 bg-slate-50 border-r border-slate-200/20 overflow-y-auto custom-scrollbar p-4 z-30">
        <app-node-tree (nodeSelected)="onNodeSelected($event)" />
      </aside>

      <!-- Main content -->
      <main class="ml-64 flex-grow p-8">
        <app-node-detail [node]="selectedNode()" />
      </main>
    </div>
  `,
})
export class NodeExplorerComponent {
  selectedNode = signal<TreeNode | null>(null);

  onNodeSelected(node: TreeNode): void {
    this.selectedNode.set(node);
  }
}

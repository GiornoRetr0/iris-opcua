import { Component, signal, inject, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { NodeTreeComponent } from './node-tree/node-tree.component';
import { NodeDetailComponent } from './node-detail/node-detail.component';
import { ConfigService } from '../../core/services/config.service';
import { TreeNode } from '../../core/models/opcua.models';

@Component({
  selector: 'app-node-explorer',
  standalone: true,
  imports: [CommonModule, NodeTreeComponent, NodeDetailComponent],
  template: `
    @if (!isConfigured()) {
      <!-- Not configured state -->
      <div class="flex items-center justify-center min-h-[calc(100vh-64px)]">
        <div class="text-center max-w-md px-8">
          <div class="w-24 h-24 mx-auto mb-8 rounded-2xl bg-surface-container-low flex items-center justify-center">
            <span class="material-symbols-outlined text-5xl text-on-surface-variant/30">lan</span>
          </div>
          <h2 class="text-2xl font-semibold text-on-surface mb-3 tracking-tight">Connect to an OPC UA Server</h2>
          <p class="text-sm text-on-surface-variant leading-relaxed mb-8">
            Configure your OPC UA server connection to start browsing the address space and reading node values.
          </p>
          <button (click)="openSettings()"
                  class="px-6 py-3 bg-primary text-on-primary font-bold rounded-lg shadow-xl shadow-primary/30 flex items-center gap-2 mx-auto hover:brightness-110 active:scale-95 transition-all">
            <span class="material-symbols-outlined text-sm">settings</span>
            Open Settings
          </button>
          <div class="mt-10 grid grid-cols-3 gap-4 text-center">
            <div class="p-4 bg-surface-container-lowest rounded-xl border border-outline-variant/10">
              <span class="material-symbols-outlined text-primary text-2xl mb-2">hub</span>
              <p class="text-[10px] font-bold text-on-surface-variant uppercase tracking-widest">1. Connect</p>
              <p class="text-[11px] text-on-surface-variant/70 mt-1">Enter server URL</p>
            </div>
            <div class="p-4 bg-surface-container-lowest rounded-xl border border-outline-variant/10">
              <span class="material-symbols-outlined text-primary text-2xl mb-2">account_tree</span>
              <p class="text-[10px] font-bold text-on-surface-variant uppercase tracking-widest">2. Browse</p>
              <p class="text-[11px] text-on-surface-variant/70 mt-1">Explore nodes</p>
            </div>
            <div class="p-4 bg-surface-container-lowest rounded-xl border border-outline-variant/10">
              <span class="material-symbols-outlined text-primary text-2xl mb-2">bar_chart</span>
              <p class="text-[10px] font-bold text-on-surface-variant uppercase tracking-widest">3. Read</p>
              <p class="text-[11px] text-on-surface-variant/70 mt-1">View live data</p>
            </div>
          </div>
        </div>
      </div>
    } @else {
      <!-- Normal explorer -->
      <div class="flex min-h-screen">
        <div class="w-0 md:w-0"></div>
        <aside class="fixed left-64 top-16 bottom-0 w-64 bg-slate-50 border-r border-slate-200/20 overflow-y-auto custom-scrollbar p-4 z-30">
          <app-node-tree (nodeSelected)="onNodeSelected($event)" />
        </aside>
        <main class="ml-64 flex-grow p-8">
          <app-node-detail [node]="selectedNode()" />
        </main>
      </div>
    }
  `,
})
export class NodeExplorerComponent {
  private config = inject(ConfigService);
  selectedNode = signal<TreeNode | null>(null);

  isConfigured = computed(() => {
    const cfg = this.config.get();
    return !!(cfg.apiBaseUrl && cfg.serverUrl);
  });

  onNodeSelected(node: TreeNode): void {
    this.selectedNode.set(node);
  }

  openSettings(): void {
    document.dispatchEvent(new CustomEvent('open-settings'));
  }
}

import { Component, signal, inject, computed, NgZone } from '@angular/core';
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
          <!-- These were three <div>s in bordered, rounded, shadowed containers
               identical to the interactive cards elsewhere, and none of them did
               anything (F14). Steps 2 and 3 describe actions that cannot be
               performed until a server exists, so there is no honest destination
               for a click — the fix is to stop promising one. Step 1 is a real
               button, because it does have somewhere to go. -->
          <ol class="mt-10 text-left space-y-3">
            <li>
              <button (click)="openSettings()" type="button"
                      class="w-full flex items-center gap-3 p-4 bg-surface-container-lowest rounded-xl
                             border border-outline-variant/10 hover:border-primary/40 hover:shadow
                             focus:outline-none focus:ring-2 focus:ring-primary/40 transition-all cursor-pointer">
                <span class="material-symbols-outlined text-primary text-2xl shrink-0">hub</span>
                <span class="flex-1">
                  <span class="block text-xs font-bold text-on-surface">1. Connect a server</span>
                  <span class="block text-[11px] text-on-surface-muted">Enter its URL and security mode</span>
                </span>
                <span class="material-symbols-outlined text-on-surface-muted text-lg shrink-0">chevron_right</span>
              </button>
            </li>
            <li class="flex items-center gap-3 px-4">
              <span class="material-symbols-outlined text-on-surface-muted text-2xl shrink-0">account_tree</span>
              <span>
                <span class="block text-xs font-bold text-on-surface-muted">2. Browse the address space</span>
                <span class="block text-[11px] text-on-surface-muted">Explore the server's nodes</span>
              </span>
            </li>
            <li class="flex items-center gap-3 px-4">
              <span class="material-symbols-outlined text-on-surface-muted text-2xl shrink-0">bar_chart</span>
              <span>
                <span class="block text-xs font-bold text-on-surface-muted">3. Read a node's value</span>
                <span class="block text-[11px] text-on-surface-muted">See live data and its status</span>
              </span>
            </li>
          </ol>
        </div>
      </div>
    } @else {
      <!-- Normal explorer -->
      <div class="flex min-h-screen">
        <aside class="fixed left-64 top-16 bottom-0 bg-slate-50 border-r border-slate-200/20 overflow-y-auto custom-scrollbar p-4 z-30"
               [style.width.px]="sidebarWidth()">
          <app-node-tree (nodeSelected)="onNodeSelected($event)" />
        </aside>
        <!-- Drag handle -->
        <div class="fixed top-16 bottom-0 w-1.5 z-40 cursor-col-resize group hover:bg-primary/20 active:bg-primary/30 transition-colors"
             [style.left.px]="sidebarWidth() + 256"
             (mousedown)="onResizeStart($event)">
          <div class="absolute inset-y-0 -left-1 -right-1"></div>
        </div>
        <main class="flex-grow p-8" [style.margin-left.px]="sidebarWidth()">
          <app-node-detail [node]="selectedNode()" />
        </main>
      </div>
    }
  `,
})
export class NodeExplorerComponent {
  private config = inject(ConfigService);
  private zone = inject(NgZone);
  selectedNode = signal<TreeNode | null>(null);
  sidebarWidth = signal(256);
  private resizing = false;

  isConfigured = computed(() => {
    const cfg = this.config.get();
    return !!(cfg.apiBaseUrl && (cfg.servers?.length > 0 || cfg.serverUrl));
  });

  onNodeSelected(node: TreeNode): void {
    this.selectedNode.set(node);
  }

  openSettings(): void {
    document.dispatchEvent(new CustomEvent('open-settings'));
  }

  onResizeStart(event: MouseEvent): void {
    event.preventDefault();
    this.resizing = true;
    const startX = event.clientX;
    const startWidth = this.sidebarWidth();

    const onMove = (e: MouseEvent) => {
      if (!this.resizing) return;
      const newWidth = Math.max(200, Math.min(600, startWidth + e.clientX - startX));
      this.zone.run(() => this.sidebarWidth.set(newWidth));
    };

    const onUp = () => {
      this.resizing = false;
      document.removeEventListener('mousemove', onMove);
      document.removeEventListener('mouseup', onUp);
      document.body.style.cursor = '';
      document.body.style.userSelect = '';
    };

    document.body.style.cursor = 'col-resize';
    document.body.style.userSelect = 'none';
    document.addEventListener('mousemove', onMove);
    document.addEventListener('mouseup', onUp);
  }
}

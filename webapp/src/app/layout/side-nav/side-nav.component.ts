import { Component, inject, signal, OnInit, OnDestroy } from '@angular/core';
import { RouterLink, RouterLinkActive } from '@angular/router';
import { CommonModule } from '@angular/common';
import { ConfigService } from '../../core/services/config.service';
import { ApiService } from '../../core/services/api.service';
import { ServerProfile } from '../../core/models/opcua.models';

@Component({
  selector: 'app-side-nav',
  standalone: true,
  imports: [CommonModule, RouterLink, RouterLinkActive],
  template: `
    <aside class="bg-slate-50 backdrop-blur-xl h-screen w-64 fixed left-0 top-0 pt-16 flex flex-col border-r border-slate-200/20 z-40">
      <!-- Branding -->
      <div class="px-6 pt-6 pb-2">
        <h2 class="text-lg font-bold text-[#131c79]">InterSystems</h2>
        <p class="text-[10px] uppercase tracking-widest text-on-surface-variant font-bold opacity-70">OPC UA Console</p>
      </div>

      <!-- Server connections -->
      @if (servers().length > 0) {
        <div class="mx-4 mb-3 space-y-1.5">
          @for (server of servers(); track server.id) {
            <div class="px-3 py-2 bg-white rounded-lg border border-slate-200/60 shadow-sm">
              <div class="flex items-center gap-2">
                <span class="relative flex h-2 w-2 shrink-0">
                  <span class="absolute inline-flex h-full w-full rounded-full opacity-75"
                        [class]="serverOnline()[server.id] ? 'bg-emerald-400 animate-ping' : 'bg-red-400'"></span>
                  <span class="relative inline-flex rounded-full h-2 w-2"
                        [class]="serverOnline()[server.id] ? 'bg-emerald-500' : 'bg-red-500'"></span>
                </span>
                <span class="text-[11px] font-semibold text-slate-700 truncate flex-1" [title]="server.name">{{ server.name }}</span>
                <span class="inline-flex items-center gap-0.5 px-1 py-0.5 rounded text-[9px] font-semibold"
                      [class]="server.securityMode === 3
                        ? 'bg-emerald-50 text-emerald-700'
                        : 'bg-amber-50 text-amber-700'">
                  <span class="material-symbols-outlined text-[10px]">{{ server.securityMode === 3 ? 'lock' : 'lock_open' }}</span>
                </span>
              </div>
              <p class="text-[10px] font-mono text-slate-500 truncate mt-0.5" [title]="server.url">{{ server.url }}</p>
            </div>
          }
        </div>
      }

      <!-- Navigation -->
      <nav class="space-y-1 px-2 flex-grow overflow-y-auto custom-scrollbar">
        <a routerLink="/explorer"
           routerLinkActive="bg-blue-100/50 text-[#131c79]"
           [routerLinkActiveOptions]="{exact: false}"
           #explorerLink="routerLinkActive"
           class="rounded-lg flex items-center gap-3 px-3 py-2 cursor-pointer transition-all"
           [class]="explorerLink.isActive
             ? 'bg-blue-100/50 text-[#131c79]'
             : 'text-slate-600 hover:bg-slate-200/50'">
          <span class="material-symbols-outlined text-xl"
                [class.filled]="explorerLink.isActive">search</span>
          <span class="text-sm font-medium">Node Explorer</span>
        </a>

        <a routerLink="/pipelines"
           routerLinkActive="bg-blue-100/50 text-[#131c79]"
           [routerLinkActiveOptions]="{exact: false}"
           #pipelinesLink="routerLinkActive"
           class="rounded-lg flex items-center gap-3 px-3 py-2 cursor-pointer transition-all"
           [class]="pipelinesLink.isActive
             ? 'bg-blue-100/50 text-[#131c79]'
             : 'text-slate-600 hover:bg-slate-200/50'">
          <span class="material-symbols-outlined text-xl"
                [class.filled]="pipelinesLink.isActive">sync_alt</span>
          <span class="text-sm font-medium">Pipelines</span>
        </a>
      </nav>

      <!-- Footer -->
      <div class="p-4">
        <a routerLink="/pipelines/new"
           class="flex items-center gap-3 bg-primary text-on-primary px-4 py-2.5 rounded-full shadow-[0_20px_40px_rgba(19,28,121,0.25)] hover:shadow-[0_25px_50px_rgba(19,28,121,0.35)] transition-all transform active:scale-95 relative z-10">
          <span class="material-symbols-outlined bg-on-primary text-primary h-7 w-7 rounded-full text-center text-lg" style="line-height: 28px; vertical-align: unset">add</span>
          <span class="font-bold text-sm tracking-wide">Create New Pipeline</span>
        </a>
      </div>
    </aside>
  `,
})
export class SideNavComponent implements OnInit, OnDestroy {
  private config = inject(ConfigService);
  private api = inject(ApiService);

  servers = signal<ServerProfile[]>([]);
  serverOnline = signal<Record<string, boolean>>({});
  private pingInterval: any;

  ngOnInit(): void {
    this.refreshServers();
    this.checkAllServers();
    this.pingInterval = setInterval(() => {
      this.refreshServers();
      this.checkAllServers();
    }, 15000);
  }

  ngOnDestroy(): void {
    if (this.pingInterval) clearInterval(this.pingInterval);
  }

  private refreshServers(): void {
    this.servers.set(this.config.getServers());
  }

  private checkAllServers(): void {
    const cfg = this.config.get();
    if (!cfg.apiBaseUrl) return;

    // First check API is reachable
    this.api.ping().subscribe({
      next: () => {
        // API is up, test each server
        for (const server of this.servers()) {
          this.api.test(server).subscribe({
            next: (result) => {
              this.serverOnline.update(s => ({ ...s, [server.id]: result.connected }));
            },
            error: () => {
              this.serverOnline.update(s => ({ ...s, [server.id]: false }));
            },
          });
        }
      },
      error: () => {
        // API is down, mark all offline
        const statuses: Record<string, boolean> = {};
        for (const server of this.servers()) {
          statuses[server.id] = false;
        }
        this.serverOnline.set(statuses);
      },
    });
  }

  openSettings(): void {
    document.dispatchEvent(new CustomEvent('open-settings'));
  }
}

import { Component, inject, signal, output } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ConfigService } from '../../core/services/config.service';
import { ApiService } from '../../core/services/api.service';
import { AppConfig, ServerProfile } from '../../core/models/opcua.models';

@Component({
  selector: 'app-settings-modal',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <!-- Modal Overlay -->
    <div class="fixed inset-0 z-[100] flex items-center justify-center bg-[#2e3132]/40 backdrop-blur-sm p-4"
         (click)="onOverlayClick($event)">
      <!-- Main Settings Modal -->
      <div class="bg-surface-container-lowest w-full max-w-4xl rounded-xl shadow-[0_20px_40px_rgba(25,28,29,0.06)] overflow-hidden flex flex-col md:flex-row max-h-[90vh]">
        <!-- Left Sidebar -->
        <div class="hidden md:flex flex-col w-72 bg-surface-container-low p-6 border-r border-outline-variant/10">
          <div class="mb-6">
            <h2 class="text-lg font-bold text-primary tracking-tight">InterSystems</h2>
            <p class="text-[10px] uppercase font-bold text-on-surface-variant tracking-widest">OPC UA Console</p>
          </div>

          <!-- Section tabs -->
          <nav class="space-y-1 mb-6">
            <div (click)="activeTab.set('servers')"
                 class="flex items-center gap-3 px-3 py-2 rounded-lg cursor-pointer transition-colors"
                 [class]="activeTab() === 'servers' ? 'bg-primary/10 text-primary font-semibold' : 'text-on-surface-variant hover:bg-surface-variant/50'">
              <span class="material-symbols-outlined text-xl">dns</span>
              <span class="text-sm">OPC UA Servers</span>
            </div>
            <div (click)="activeTab.set('gateway')"
                 class="flex items-center gap-3 px-3 py-2 rounded-lg cursor-pointer transition-colors"
                 [class]="activeTab() === 'gateway' ? 'bg-primary/10 text-primary font-semibold' : 'text-on-surface-variant hover:bg-surface-variant/50'">
              <span class="material-symbols-outlined text-xl">settings</span>
              <span class="text-sm">IRIS API Gateway</span>
            </div>
          </nav>

          <!-- Server list (when servers tab active) -->
          @if (activeTab() === 'servers') {
            <div class="flex-1 overflow-y-auto custom-scrollbar space-y-1">
              <p class="text-[10px] font-bold uppercase tracking-widest text-on-surface-variant mb-2 px-1">Connections</p>
              @for (server of servers(); track server.id) {
                <div (click)="selectServer(server)"
                     class="flex items-center gap-2.5 px-3 py-2 rounded-lg cursor-pointer transition-colors group"
                     [class]="selectedServerId() === server.id ? 'bg-primary/10 text-primary' : 'text-on-surface-variant hover:bg-surface-variant/50'">
                  <span class="relative flex h-2 w-2 shrink-0">
                    <span class="relative inline-flex rounded-full h-2 w-2"
                          [class]="serverStatuses()[server.id] === 'online' ? 'bg-emerald-500' : serverStatuses()[server.id] === 'testing' ? 'bg-amber-400 animate-pulse' : 'bg-slate-300'"></span>
                  </span>
                  <div class="flex-1 min-w-0">
                    <p class="text-xs font-semibold truncate">{{ server.name }}</p>
                    <p class="text-[10px] font-mono text-on-surface-variant/60 truncate">{{ server.url }}</p>
                  </div>
                  <button (click)="removeServer(server.id, $event)"
                          class="opacity-0 group-hover:opacity-100 text-on-surface-variant hover:text-error transition-all p-0.5 rounded">
                    <span class="material-symbols-outlined text-sm">close</span>
                  </button>
                </div>
              }
              <button (click)="addNewServer()"
                      class="flex items-center gap-2 px-3 py-2 w-full rounded-lg text-primary hover:bg-primary/5 transition-colors mt-1">
                <span class="material-symbols-outlined text-lg">add_circle</span>
                <span class="text-xs font-semibold">Add Server</span>
              </button>
            </div>
          }

          <div class="mt-auto pt-6">
            <div class="bg-tertiary-fixed text-on-tertiary-fixed p-4 rounded-xl flex items-center gap-3">
              <span class="material-symbols-outlined">sensors</span>
              <div>
                <p class="text-[10px] font-bold uppercase">System Status</p>
                <p class="text-xs font-semibold">{{ testStatus() || 'Ready' }}</p>
              </div>
            </div>
          </div>
        </div>

        <!-- Content Area -->
        <div class="flex-1 flex flex-col overflow-hidden">
          <!-- Modal Header -->
          <div class="px-8 py-6 border-b border-outline-variant/10 flex justify-between items-center bg-surface-container-lowest sticky top-0 z-10">
            <div>
              <h1 class="text-xl font-semibold text-on-surface">
                {{ activeTab() === 'servers' ? (editingServer() ? editingServer()!.name || 'New Server' : 'OPC UA Servers') : 'IRIS API Gateway' }}
              </h1>
              <p class="text-sm text-on-surface-variant">
                {{ activeTab() === 'servers' ? 'Configure OPC UA server connections' : 'Configure IRIS API endpoint' }}
              </p>
            </div>
            <button class="text-on-surface-variant hover:bg-surface-variant p-2 rounded-full transition-colors"
                    (click)="closed.emit()">
              <span class="material-symbols-outlined">close</span>
            </button>
          </div>

          <!-- Form Scrollable Area -->
          <div class="flex-1 overflow-y-auto p-8 space-y-10 custom-scrollbar">
            <!-- Server edit form -->
            @if (activeTab() === 'servers' && editingServer()) {
              <section>
                <header class="mb-4 flex items-center gap-2">
                  <span class="w-1 h-5 bg-primary rounded-full"></span>
                  <h3 class="text-xs font-bold uppercase tracking-widest text-on-surface-variant">Server Connection</h3>
                </header>
                <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <div>
                    <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">Display Name</label>
                    <input type="text" [(ngModel)]="editingServer()!.name"
                           class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all"
                           placeholder="Factory Floor PLC">
                  </div>
                  <div>
                    <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">Security Mode</label>
                    <select [(ngModel)]="editingServer()!.securityMode"
                            class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all appearance-none cursor-pointer">
                      <option [ngValue]="1">None</option>
                      <option [ngValue]="3">Sign & Encrypt (Basic256Sha256)</option>
                    </select>
                  </div>
                  <div class="md:col-span-2">
                    <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">OPC UA Server URL</label>
                    <input type="text" [(ngModel)]="editingServer()!.url"
                           class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all"
                           placeholder="opc.tcp://localhost:4840">
                  </div>
                  <div>
                    <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">Username</label>
                    <input type="text" [(ngModel)]="editingServer()!.username" autocomplete="off"
                           class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all">
                  </div>
                  <div>
                    <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">Password</label>
                    <input type="password" [(ngModel)]="editingServer()!.password" autocomplete="off" placeholder="••••••••"
                           class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all">
                  </div>
                </div>
              </section>

              <!-- Address Space -->
              <section>
                <header class="mb-4 flex items-center gap-2">
                  <span class="w-1 h-5 bg-on-secondary-container rounded-full"></span>
                  <h3 class="text-xs font-bold uppercase tracking-widest text-on-surface-variant">Address Space Hierarchy</h3>
                </header>
                <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <div>
                    <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">Root Node ID</label>
                    <input type="text" [(ngModel)]="editingServer()!.rootNodeId"
                           class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all">
                  </div>
                  <div>
                    <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">Root Namespace</label>
                    <input type="number" [(ngModel)]="editingServer()!.rootNodeNs" min="0"
                           class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all">
                  </div>
                </div>
              </section>

              <!-- Certificates (if Sign & Encrypt) -->
              @if (editingServer()!.securityMode === 3) {
                <section>
                  <header class="mb-4 flex items-center gap-2">
                    <span class="w-1 h-5 bg-tertiary rounded-full"></span>
                    <h3 class="text-xs font-bold uppercase tracking-widest text-on-surface-variant">Certificate Configuration</h3>
                  </header>
                  <div class="grid grid-cols-1 gap-6">
                    <div>
                      <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">Client URI (must match certificate)</label>
                      <input type="text" [(ngModel)]="editingServer()!.clientURI" placeholder="urn:secuac"
                             class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all">
                    </div>
                    <div>
                      <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">Client Certificate (DER path on IRIS server)</label>
                      <input type="text" [(ngModel)]="editingServer()!.certPath" placeholder="/usr/irissys/uac/certs/secuac.crt.der"
                             class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all">
                    </div>
                    <div>
                      <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">Private Key (DER path on IRIS server)</label>
                      <input type="text" [(ngModel)]="editingServer()!.keyPath" placeholder="/usr/irissys/uac/certs/secuac.key.der"
                             class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all">
                    </div>
                    <div>
                      <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">Trust List Directory</label>
                      <input type="text" [(ngModel)]="editingServer()!.trustDir" placeholder="/usr/irissys/uac/certs/trustdir/"
                             class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all">
                    </div>
                    <div>
                      <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">Revocation List Directory</label>
                      <input type="text" [(ngModel)]="editingServer()!.crlDir" placeholder="/usr/irissys/uac/certs/crldir/"
                             class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all">
                    </div>
                  </div>
                </section>
              }

              @if (activeTab() === 'servers' && !editingServer()) {
                <div class="flex items-center justify-center h-48 text-on-surface-variant">
                  <div class="text-center">
                    <span class="material-symbols-outlined text-4xl opacity-30 mb-2">dns</span>
                    <p class="text-sm">Select a server or add a new one</p>
                  </div>
                </div>
              }
            }

            <!-- No server selected placeholder -->
            @if (activeTab() === 'servers' && !editingServer()) {
              <div class="flex items-center justify-center h-48 text-on-surface-variant">
                <div class="text-center">
                  <span class="material-symbols-outlined text-4xl opacity-30 mb-2">dns</span>
                  <p class="text-sm">Select a server or add a new one</p>
                </div>
              </div>
            }

            <!-- Gateway tab -->
            @if (activeTab() === 'gateway') {
              <section>
                <header class="mb-4 flex items-center gap-2">
                  <span class="w-1 h-5 bg-tertiary rounded-full"></span>
                  <h3 class="text-xs font-bold uppercase tracking-widest text-on-surface-variant">IRIS API Gateway</h3>
                </header>
                <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <div class="md:col-span-2">
                    <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">API Base URL</label>
                    <input type="text" [(ngModel)]="gatewayForm.apiBaseUrl"
                           class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all"
                           placeholder="http://localhost:52773/csp/opcua/api">
                  </div>
                  <div>
                    <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">IRIS API Username</label>
                    <input type="text" [(ngModel)]="gatewayForm.apiUsername" autocomplete="off"
                           class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all">
                  </div>
                  <div>
                    <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">IRIS API Password</label>
                    <input type="password" [(ngModel)]="gatewayForm.apiPassword" autocomplete="off" placeholder="••••••••"
                           class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all">
                  </div>
                  <div>
                    <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">Auto-Refresh Interval (s)</label>
                    <input type="number" [(ngModel)]="gatewayForm.autoRefreshInterval" min="1" max="60"
                           class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all">
                  </div>
                </div>
              </section>
            }
          </div>

          <!-- Footer Actions -->
          <div class="px-8 py-6 border-t border-outline-variant/10 bg-surface-container-low/50 flex flex-col sm:flex-row items-center justify-between gap-4">
            @if (activeTab() === 'servers' && editingServer()) {
              <button (click)="testServerConnection()"
                      [disabled]="testing()"
                      class="flex items-center gap-2 px-5 py-2.5 text-primary text-sm font-semibold rounded-lg hover:bg-primary/5 transition-all border border-outline-variant/30 w-full sm:w-auto disabled:opacity-50">
                <span class="material-symbols-outlined text-xl">network_check</span>
                {{ testing() ? 'Testing...' : 'Test Connection' }}
              </button>
            } @else {
              <div></div>
            }
            <div class="flex items-center gap-3 w-full sm:w-auto">
              <button (click)="closed.emit()"
                      class="flex-1 sm:flex-none px-6 py-2.5 text-on-surface-variant text-sm font-semibold rounded-lg hover:bg-surface-variant transition-all">
                Cancel
              </button>
              <button (click)="saveAll()"
                      class="flex-1 sm:flex-none px-8 py-2.5 bg-gradient-to-br from-primary to-primary-container text-on-primary text-sm font-semibold rounded-lg shadow-lg shadow-primary/20 hover:scale-[1.02] active:scale-[0.98] transition-all">
                Save Changes
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  `,
})
export class SettingsModalComponent {
  private configService = inject(ConfigService);
  private api = inject(ApiService);

  closed = output<void>();

  activeTab = signal<'servers' | 'gateway'>('servers');
  testing = signal(false);
  testStatus = signal('');

  // Server list (mutable copies for editing)
  servers = signal<ServerProfile[]>([]);
  selectedServerId = signal<string | null>(null);
  editingServer = signal<ServerProfile | null>(null);
  serverStatuses = signal<Record<string, 'online' | 'offline' | 'testing'>>({});

  // Gateway form (shared settings)
  gatewayForm: { apiBaseUrl: string; apiUsername: string; apiPassword: string; autoRefreshInterval: number };

  constructor() {
    const cfg = this.configService.get();
    // Deep-copy servers for editing
    this.servers.set((cfg.servers || []).map(s => ({ ...s })));
    this.gatewayForm = {
      apiBaseUrl: cfg.apiBaseUrl,
      apiUsername: cfg.apiUsername,
      apiPassword: cfg.apiPassword,
      autoRefreshInterval: cfg.autoRefreshInterval,
    };

    // Auto-select first server if any
    const svrs = this.servers();
    if (svrs.length > 0) {
      this.selectServer(svrs[0]);
    }
  }

  selectServer(server: ServerProfile): void {
    this.selectedServerId.set(server.id);
    // Find mutable reference from our servers list
    const found = this.servers().find(s => s.id === server.id);
    this.editingServer.set(found || null);
  }

  addNewServer(): void {
    const newServer: ServerProfile = {
      id: 'new_' + Date.now().toString(36),
      name: '',
      url: '',
      securityMode: 1,
      username: '',
      password: '',
      certPath: '',
      keyPath: '',
      trustDir: '',
      crlDir: '',
      clientURI: '',
      rootNodeId: '84',
      rootNodeNs: 0,
    };
    this.servers.update(list => [...list, newServer]);
    this.selectServer(newServer);
  }

  removeServer(id: string, event: MouseEvent): void {
    event.stopPropagation();
    this.servers.update(list => list.filter(s => s.id !== id));
    if (this.selectedServerId() === id) {
      const remaining = this.servers();
      if (remaining.length > 0) {
        this.selectServer(remaining[0]);
      } else {
        this.selectedServerId.set(null);
        this.editingServer.set(null);
      }
    }
  }

  testServerConnection(): void {
    const server = this.editingServer();
    if (!server || !server.url) return;

    this.testing.set(true);
    this.testStatus.set('Testing...');
    this.serverStatuses.update(s => ({ ...s, [server.id]: 'testing' }));

    // Temporarily save gateway settings so API base URL is current
    this.configService.save(this.gatewayForm);

    this.api.test(server).subscribe({
      next: (result) => {
        this.testing.set(false);
        if (result.connected) {
          this.testStatus.set(`Connected (${result.responseTimeMs}ms)`);
          this.serverStatuses.update(s => ({ ...s, [server.id]: 'online' }));
        } else {
          this.testStatus.set(result.error || 'Connection failed');
          this.serverStatuses.update(s => ({ ...s, [server.id]: 'offline' }));
        }
      },
      error: (err) => {
        this.testing.set(false);
        this.testStatus.set(err.message || 'Error');
        this.serverStatuses.update(s => ({ ...s, [server.id]: 'offline' }));
      },
    });
  }

  saveAll(): void {
    // Filter out empty servers (no URL)
    const validServers = this.servers().filter(s => s.url);
    // Auto-name untitled servers
    for (const s of validServers) {
      if (!s.name) {
        const match = s.url.match(/:\/\/([^:/]+)/);
        s.name = match ? match[1] : 'Server';
      }
    }

    this.configService.save({
      ...this.gatewayForm,
      servers: validServers,
      // Keep legacy fields synced with first server for backward compat
      serverUrl: validServers[0]?.url || '',
      securityMode: validServers[0]?.securityMode || 1,
      username: validServers[0]?.username || '',
      password: validServers[0]?.password || '',
      certPath: validServers[0]?.certPath || '',
      keyPath: validServers[0]?.keyPath || '',
      trustDir: validServers[0]?.trustDir || '',
      crlDir: validServers[0]?.crlDir || '',
      clientURI: validServers[0]?.clientURI || '',
      rootNodeId: validServers[0]?.rootNodeId || '84',
      rootNodeNs: validServers[0]?.rootNodeNs || 0,
    });

    this.testStatus.set('Saved');
    setTimeout(() => this.closed.emit(), 500);
  }

  onOverlayClick(event: MouseEvent): void {
    if ((event.target as HTMLElement).classList.contains('fixed')) {
      this.closed.emit();
    }
  }
}

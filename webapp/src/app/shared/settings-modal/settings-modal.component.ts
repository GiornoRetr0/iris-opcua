import { Component, inject, signal, output } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ConfigService } from '../../core/services/config.service';
import { ApiService } from '../../core/services/api.service';
import { AppConfig } from '../../core/models/opcua.models';

@Component({
  selector: 'app-settings-modal',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <!-- Modal Overlay -->
    <div class="fixed inset-0 z-[100] flex items-center justify-center bg-[#2e3132]/40 backdrop-blur-sm p-4"
         (click)="onOverlayClick($event)">
      <!-- Main Settings Modal -->
      <div class="bg-surface-container-lowest w-full max-w-3xl rounded-xl shadow-[0_20px_40px_rgba(25,28,29,0.06)] overflow-hidden flex flex-col md:flex-row max-h-[90vh]">
        <!-- Left Sidebar -->
        <div class="hidden md:flex flex-col w-64 bg-surface-container-low p-6 border-r border-outline-variant/10">
          <div class="mb-8">
            <h2 class="text-lg font-bold text-primary tracking-tight">InterSystems</h2>
            <p class="text-[10px] uppercase font-bold text-on-surface-variant tracking-widest">OPC UA Console</p>
          </div>
          <nav class="space-y-2">
            <div (click)="activeTab.set('connection')"
                 class="flex items-center gap-3 px-3 py-2 rounded-lg cursor-pointer transition-colors"
                 [class]="activeTab() === 'connection' ? 'bg-primary/10 text-primary font-semibold' : 'text-on-surface-variant hover:bg-surface-variant/50'">
              <span class="material-symbols-outlined text-xl">settings</span>
              <span class="text-sm">Connection</span>
            </div>
            <div (click)="activeTab.set('certificates')"
                 class="flex items-center gap-3 px-3 py-2 rounded-lg cursor-pointer transition-colors"
                 [class]="activeTab() === 'certificates' ? 'bg-primary/10 text-primary font-semibold' : 'text-on-surface-variant hover:bg-surface-variant/50'">
              <span class="material-symbols-outlined text-xl">security</span>
              <span class="text-sm">Certificates</span>
            </div>
          </nav>
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
              <h1 class="text-xl font-semibold text-on-surface">Precision Architect Settings</h1>
              <p class="text-sm text-on-surface-variant">Configure environment variables and gateway endpoints</p>
            </div>
            <button class="text-on-surface-variant hover:bg-surface-variant p-2 rounded-full transition-colors"
                    (click)="closed.emit()">
              <span class="material-symbols-outlined">close</span>
            </button>
          </div>

          <!-- Form Scrollable Area -->
          <div class="flex-1 overflow-y-auto p-8 space-y-10 custom-scrollbar">
            <!-- Connection tab -->
            @if (activeTab() === 'connection') {
              <!-- OPC UA Server -->
              <section>
                <header class="mb-4 flex items-center gap-2">
                  <span class="w-1 h-5 bg-primary rounded-full"></span>
                  <h3 class="text-xs font-bold uppercase tracking-widest text-on-surface-variant">OPC UA Server Configuration</h3>
                </header>
                <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <div class="md:col-span-2">
                    <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">OPC UA Server URL</label>
                    <input type="text" [(ngModel)]="form.serverUrl"
                           class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all"
                           placeholder="opc.tcp://localhost:4840">
                  </div>
                  <div>
                    <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">Security Mode</label>
                    <select [(ngModel)]="form.securityMode"
                            class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all appearance-none cursor-pointer">
                      <option [ngValue]="1">None</option>
                      <option [ngValue]="3">Sign & Encrypt (Basic256Sha256)</option>
                    </select>
                  </div>
                  <div>
                    <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">Auto-Refresh Interval (s)</label>
                    <input type="number" [(ngModel)]="form.autoRefreshInterval" min="1" max="60"
                           class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all">
                  </div>
                  <div>
                    <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">Username</label>
                    <input type="text" [(ngModel)]="form.username" autocomplete="off"
                           class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all">
                  </div>
                  <div>
                    <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">Password</label>
                    <input type="password" [(ngModel)]="form.password" autocomplete="off" placeholder="••••••••"
                           class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all">
                  </div>
                </div>
              </section>

              <!-- IRIS API Gateway -->
              <section>
                <header class="mb-4 flex items-center gap-2">
                  <span class="w-1 h-5 bg-tertiary rounded-full"></span>
                  <h3 class="text-xs font-bold uppercase tracking-widest text-on-surface-variant">IRIS API Gateway</h3>
                </header>
                <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <div class="md:col-span-2">
                    <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">API Base URL</label>
                    <input type="text" [(ngModel)]="form.apiBaseUrl"
                           class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all"
                           placeholder="http://localhost:52773/csp/opcua/api">
                  </div>
                  <div>
                    <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">IRIS API Username</label>
                    <input type="text" [(ngModel)]="form.apiUsername" autocomplete="off"
                           class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all">
                  </div>
                  <div>
                    <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">IRIS API Password</label>
                    <input type="password" [(ngModel)]="form.apiPassword" autocomplete="off" placeholder="••••••••"
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
                    <input type="text" [(ngModel)]="form.rootNodeId"
                           class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all">
                  </div>
                  <div>
                    <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">Root Namespace</label>
                    <input type="number" [(ngModel)]="form.rootNodeNs" min="0"
                           class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all">
                  </div>
                </div>
              </section>
            }

            <!-- Certificates tab -->
            @if (activeTab() === 'certificates') {
              <section>
                <header class="mb-4 flex items-center gap-2">
                  <span class="w-1 h-5 bg-primary rounded-full"></span>
                  <h3 class="text-xs font-bold uppercase tracking-widest text-on-surface-variant">Certificate Configuration</h3>
                </header>
                <p class="text-sm text-on-surface-variant mb-6">Required when Security Mode is set to "Sign & Encrypt".</p>
                <div class="grid grid-cols-1 gap-6">
                  <div>
                    <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">Client URI (must match certificate)</label>
                    <input type="text" [(ngModel)]="form.clientURI" placeholder="urn:secuac"
                           class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all">
                  </div>
                  <div>
                    <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">Client Certificate (DER path on IRIS server)</label>
                    <input type="text" [(ngModel)]="form.certPath" placeholder="/usr/irissys/uac/certs/secuac.crt.der"
                           class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all">
                  </div>
                  <div>
                    <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">Private Key (DER path on IRIS server)</label>
                    <input type="text" [(ngModel)]="form.keyPath" placeholder="/usr/irissys/uac/certs/secuac.key.der"
                           class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all">
                  </div>
                  <div>
                    <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">Trust List Directory</label>
                    <input type="text" [(ngModel)]="form.trustDir" placeholder="/usr/irissys/uac/certs/trustdir/"
                           class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all">
                  </div>
                  <div>
                    <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">Revocation List Directory</label>
                    <input type="text" [(ngModel)]="form.crlDir" placeholder="/usr/irissys/uac/certs/crldir/"
                           class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all">
                  </div>
                </div>
              </section>
            }
          </div>

          <!-- Footer Actions -->
          <div class="px-8 py-6 border-t border-outline-variant/10 bg-surface-container-low/50 flex flex-col sm:flex-row items-center justify-between gap-4">
            <button (click)="testConnection()"
                    [disabled]="testing()"
                    class="flex items-center gap-2 px-5 py-2.5 text-primary text-sm font-semibold rounded-lg hover:bg-primary/5 transition-all border border-outline-variant/30 w-full sm:w-auto disabled:opacity-50">
              <span class="material-symbols-outlined text-xl">network_check</span>
              {{ testing() ? 'Testing...' : 'Test Connection' }}
            </button>
            <div class="flex items-center gap-3 w-full sm:w-auto">
              <button (click)="closed.emit()"
                      class="flex-1 sm:flex-none px-6 py-2.5 text-on-surface-variant text-sm font-semibold rounded-lg hover:bg-surface-variant transition-all">
                Cancel
              </button>
              <button (click)="saveConfig()"
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

  activeTab = signal<'connection' | 'certificates'>('connection');
  testing = signal(false);
  testStatus = signal('');

  form: AppConfig;

  constructor() {
    this.form = { ...this.configService.get() };
  }

  onOverlayClick(event: MouseEvent): void {
    if ((event.target as HTMLElement).classList.contains('fixed')) {
      this.closed.emit();
    }
  }

  testConnection(): void {
    this.testing.set(true);
    this.testStatus.set('Testing...');
    // Temporarily save to make API use current form values
    this.configService.save(this.form);
    this.api.test().subscribe({
      next: (result) => {
        this.testing.set(false);
        if (result.connected) {
          this.testStatus.set(`Connected (${result.responseTimeMs}ms)`);
        } else {
          this.testStatus.set(result.error || 'Connection failed');
        }
      },
      error: (err) => {
        this.testing.set(false);
        this.testStatus.set(err.message || 'Error');
      },
    });
  }

  saveConfig(): void {
    this.configService.save(this.form);
    this.testStatus.set('Saved');
    setTimeout(() => this.closed.emit(), 500);
  }
}

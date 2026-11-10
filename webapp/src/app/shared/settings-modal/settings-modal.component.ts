import { Component, computed, inject, signal, output, input, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ConfigService } from '../../core/services/config.service';
import { firstValueFrom } from 'rxjs';
import { ApiService, apiErrorMessage, InlineLogin, NOT_SIGNED_IN } from '../../core/services/api.service';
import { AuthService } from '../../core/services/auth.service';
import { SecurityTabComponent } from './security-tab/security-tab.component';
import { ServerSecurityComponent } from './server-security/server-security.component';
import { ConnectionTestResult, CredentialsEntry, isManaged, ServerProfile } from '../../core/models/opcua.models';

/**
 * A credentials entry being created or changed for one server, saved to IRIS when
 * the user saves. `edit` changes the server's current entry; an empty password then
 * keeps the stored one.
 */
interface CredentialsDraft {
  mode: 'new' | 'edit';
  id: string;
  username: string;
  password: string;
}

/** The select's value for "New credentials…": not a valid credentials ID. */
const NEW_CREDENTIALS = ' new';

@Component({
  selector: 'app-settings-modal',
  standalone: true,
  imports: [CommonModule, FormsModule, SecurityTabComponent, ServerSecurityComponent],
  template: `
    <!-- Modal Overlay -->
    <div class="fixed inset-0 z-[100] flex items-center justify-center bg-[#2e3132]/40 backdrop-blur-sm p-4"
         (click)="onOverlayClick($event)">
      <!-- Main Settings Modal -->
      <!-- Fixed height, not content height. The two tabs hold different amounts, so
           a content-sized dialog resized as you switched — the sidebar you are aiming
           at moves under the cursor, and the whole thing reflows for a change that was
           meant to be a navigation. Pinned to the taller of the two, the servers form,
           so nothing has to shrink to fit.
           47rem is that form's measured height. The body already scrolls, so anything
           taller than the box (Sign & Encrypt reveals four more fields) scrolls inside
           it rather than growing it — which is the same resize by another route.
           max-h-[90vh] still wins on a short viewport. -->
      <div class="bg-surface-container-lowest w-full max-w-4xl rounded-xl shadow-[0_20px_40px_rgba(25,28,29,0.06)] overflow-hidden flex flex-col md:flex-row h-[47rem] max-h-[90vh]">
        <!-- Left Sidebar -->
        <div class="hidden md:flex flex-col w-72 bg-surface-container-low p-6 border-r border-outline-variant/10">
          <!-- Says what this dialog is, rather than repeating the brand lockup that
               is already in the nav rail two inches to the left (T3.6). A modal
               header should orient you inside the modal. -->
          <div class="mb-6">
            <h2 class="text-lg font-bold text-primary tracking-tight">Settings</h2>
            <p class="text-[10px] uppercase font-bold text-on-surface-variant tracking-widest">Servers and connection</p>
          </div>

          <!-- Section tabs -->
          <nav class="space-y-1 mb-6">
            <div (click)="activeTab.set('servers')"
                 class="flex items-center gap-3 px-3 py-2 rounded-lg cursor-pointer transition-colors"
                 [class]="activeTab() === 'servers' ? 'bg-primary/10 text-primary font-semibold' : 'text-on-surface-variant hover:bg-surface-variant/50'">
              <span class="material-symbols-outlined text-xl">dns</span>
              <span class="text-sm">OPC UA Servers</span>
            </div>
            <div (click)="activeTab.set('security')" (keydown.enter)="activeTab.set('security')" role="button" tabindex="0"
                 class="flex items-center gap-3 px-3 py-2 rounded-lg cursor-pointer transition-colors"
                 [class]="activeTab() === 'security' ? 'bg-primary/10 text-primary font-semibold' : 'text-on-surface-variant hover:bg-surface-variant/50'">
              <span class="material-symbols-outlined text-xl">verified_user</span>
              <span class="text-sm">OPC UA Security</span>
            </div>
            <div (click)="activeTab.set('gateway')"
                 class="flex items-center gap-3 px-3 py-2 rounded-lg cursor-pointer transition-colors"
                 [class]="activeTab() === 'gateway' ? 'bg-primary/10 text-primary font-semibold' : 'text-on-surface-variant hover:bg-surface-variant/50'">
              <span class="material-symbols-outlined text-xl">settings</span>
              <span class="text-sm">IRIS API Gateway</span>
            </div>
          </nav>

          <!-- Always shown, on both tabs. The list is the sidebar's contents, not the
               servers tab's: hiding it made the pane look like the connections had
               gone, and left no way to reach one without first going back. Clicking a
               row switches to the servers tab, so it works as a jump from either. -->
          <div class="flex-1 overflow-y-auto custom-scrollbar space-y-1">
            <p class="text-[10px] font-bold uppercase tracking-widest text-on-surface-variant mb-2 px-1">Connections</p>
            @for (server of servers(); track server.id) {
              <!-- Highlighted only while the servers tab is showing it: on the
                   gateway tab the selection is not what the right pane is editing,
                   and saying otherwise would be a lie about where you are. -->
              <div (click)="selectServer(server)"
                   class="flex items-center gap-2.5 px-3 py-2 rounded-lg cursor-pointer transition-colors group"
                   [class]="activeTab() === 'servers' && selectedServerId() === server.id ? 'bg-primary/10 text-primary' : 'text-on-surface-variant hover:bg-surface-variant/50'">
                <span class="relative flex h-2 w-2 shrink-0">
                  <span class="relative inline-flex rounded-full h-2 w-2"
                        [class]="serverStatuses()[server.id] === 'online' ? 'bg-emerald-500' : serverStatuses()[server.id] === 'testing' ? 'bg-amber-400 animate-pulse' : 'bg-slate-300'"></span>
                </span>
                <div class="flex-1 min-w-0">
                  <p class="text-xs font-semibold truncate">{{ server.name }}</p>
                  <p class="text-[10px] font-mono text-on-surface-muted truncate">{{ server.url }}</p>
                  <!-- The mode in words under the URL, so the list itself says which
                       connections are unsecured without opening each one. -->
                  <p class="flex items-center gap-1 text-[10px] font-semibold"
                     [class]="server.securityMode === 3 ? 'text-emerald-700' : 'text-amber-700'">
                    <span class="material-symbols-outlined text-[11px]">
                      {{ server.securityMode === 3 ? 'lock' : 'lock_open' }}
                    </span>
                    {{ server.securityMode === 3 ? 'Sign & Encrypt' : 'Unsecured' }}
                  </p>
                </div>
                <!-- Always visible. Not one of the audit's three, but the same defect:
                     a remove control that touch can never reveal. -->
                <button (click)="removeServer(server.id, $event)"
                        [title]="'Remove ' + (server.name || 'this server')"
                        class="text-on-surface-variant hover:text-error focus:outline-none focus-visible:ring-2 focus-visible:ring-primary/40 transition-colors p-0.5 rounded shrink-0">
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

          <!-- Only rendered once a test has actually run. Its resting state used to be
               a hardcoded 'Ready' — the most saturated colour in the palette, in the
               one pane a user visits to find out whether their connection works,
               asserting health while measuring nothing. An unpressed test has no
               result, so it shows nothing. -->
          @if (testStatus()) {
            <div class="mt-auto pt-6">
              <div class="p-4 rounded-xl flex items-center gap-3"
                   [class]="testFailed() ? 'bg-error-container text-on-error-container' : 'bg-tertiary-fixed text-on-tertiary-fixed'">
                <span class="material-symbols-outlined">{{ testFailed() ? 'error' : 'sensors' }}</span>
                <div class="min-w-0">
                  <p class="text-[10px] font-bold uppercase">Last test</p>
                  <p class="text-xs font-semibold break-words">{{ testStatus() }}</p>
                </div>
              </div>
            </div>
          }
        </div>

        <!-- Content Area -->
        <div class="flex-1 flex flex-col overflow-hidden">
          <!-- Modal Header -->
          <div class="px-8 py-6 border-b border-outline-variant/10 flex justify-between items-center bg-surface-container-lowest sticky top-0 z-10">
            <div>
              <h1 class="text-xl font-semibold text-on-surface">
                {{ activeTab() === 'servers' ? (editingServer() ? editingServer()!.name || 'New Server' : 'OPC UA Servers') : activeTab() === 'security' ? 'OPC UA Security' : 'IRIS API Gateway' }}
              </h1>
              <p class="text-sm text-on-surface-variant">
                {{ activeTab() === 'servers' ? 'Configure OPC UA server connections' : activeTab() === 'security' ? 'The certificate IRIS presents to OPC UA servers' : 'Configure IRIS API endpoint' }}
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
                           (ngModelChange)="clearSaveError()"
                           class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all"
                           placeholder="Factory Floor PLC">
                  </div>
                  <div>
                    <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">Security Mode</label>
                    <!-- min-w so it cannot truncate mid-identifier: Basic256Sha256 and
                         Basic128Rsa15 are different things, and "Sign & Encrypt
                         (Basic256Sha2" told you nothing about which. The policy moves
                         to a second line below rather than into the option text. -->
                    <select [(ngModel)]="editingServer()!.securityMode"
                            (ngModelChange)="onSecurityModeChange($event)"
                            class="w-full min-w-[16rem] bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all appearance-none cursor-pointer">
                      <option [ngValue]="1">None</option>
                      <option [ngValue]="3">Sign &amp; Encrypt</option>
                    </select>
                    <p class="text-[11px] text-on-surface-muted mt-1">
                      @if (editingServer()!.securityMode === 3) {
                        Policy <code class="font-mono">Basic256Sha256</code>. Sign &amp; Encrypt uses this
                        IRIS instance's client identity.
                      } @else {
                        No message security — traffic is unencrypted and unsigned.
                      }
                    </p>
                  </div>
                  <div class="md:col-span-2">
                    <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">OPC UA Server URL</label>
                    <input type="text" [(ngModel)]="editingServer()!.url"
                           (ngModelChange)="clearSaveError()"
                           class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all"
                           placeholder="opc.tcp://localhost:4840">
                  </div>
                  <!-- The username and password live in an IRIS credentials entry,
                       never in this browser. The server stores only the entry's ID;
                       deploy puts the same ID in the pipeline, so changing the entry
                       here changes it for every pipeline that uses it. -->
                  <div class="md:col-span-2">
                    <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">Credentials</label>
                    <select [ngModel]="credentialsChoice()" (ngModelChange)="chooseCredentials($event)"
                            class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all appearance-none cursor-pointer">
                      <option value="">Anonymous (no username)</option>
                      @for (c of credentialOptions(); track c.id) {
                        <option [value]="c.id">{{ c.id }}{{ c.username ? ' — ' + c.username : '' }}</option>
                      }
                      <option [value]="NEW">New credentials…</option>
                    </select>
                    @if (credentialsError()) {
                      <p class="flex items-start gap-1.5 text-[11px] text-error mt-1" role="alert">
                        <span class="material-symbols-outlined text-sm shrink-0">error</span>
                        <span>Could not list credentials: {{ credentialsError() }}</span>
                      </p>
                    }
                    @if (!draft() && selectedEntry(); as entry) {
                      <div class="flex items-center gap-2 mt-2 text-[11px] text-on-surface-muted">
                        <span class="material-symbols-outlined text-sm text-tertiary">key</span>
                        <span class="flex-1">
                          Stored in IRIS as user <strong class="font-semibold text-on-surface">{{ entry.username }}</strong>.
                          {{ usageText(entry) }}
                        </span>
                        <button type="button" (click)="editCredentials(entry)"
                                class="text-xs font-semibold text-primary hover:underline shrink-0">Change</button>
                      </div>
                    }
                  </div>
                  @if (draft(); as d) {
                    @if (d.mode === 'new') {
                      <div class="md:col-span-2">
                        <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">Credentials ID</label>
                        <input type="text" [(ngModel)]="d.id" (ngModelChange)="clearSaveError()" autocomplete="off"
                               class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm font-mono focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all">
                        <p class="text-[11px] text-on-surface-muted mt-1">
                          The entry's name in IRIS (Interoperability &gt; Configure &gt; Credentials). Letters, digits, '.', '-' and '_'.
                        </p>
                      </div>
                    }
                    <div>
                      <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">Username</label>
                      <input type="text" [(ngModel)]="d.username" (ngModelChange)="clearSaveError()" autocomplete="off"
                             class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all">
                    </div>
                    <div>
                      <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">Password</label>
                      <input type="password" [(ngModel)]="d.password" (ngModelChange)="clearSaveError()" autocomplete="new-password"
                             [placeholder]="d.mode === 'edit' ? 'Leave empty to keep the current one' : 'No password'"
                             class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all">
                    </div>
                    <p class="md:col-span-2 -mt-3 flex items-start gap-1.5 text-[11px] text-on-surface-muted">
                      <span class="material-symbols-outlined text-sm shrink-0">info</span>
                      <span class="flex-1">
                        Saved in IRIS when you save, not in this browser.
                        @if (d.mode === 'edit' && draftEntry(); as entry) { {{ usageText(entry) }} }
                      </span>
                      <button type="button" (click)="discardDraft()"
                              class="text-xs font-semibold text-primary hover:underline shrink-0">
                        {{ d.mode === 'edit' ? 'Keep as is' : 'Cancel' }}
                      </button>
                    </p>
                  }
                </div>
              </section>

              <!-- Sign & Encrypt readiness (managed), or the manual certificate files -->
              @if (editingServer()!.securityMode === 3) {
                <app-server-security [server]="editingServer()!" [testResult]="lastTest()"
                                     (setupIdentity)="openSecurity(editingServer()!.id)" />
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

            <!-- Security tab -->
            @if (activeTab() === 'security') {
              <app-security-tab [returnTo]="returnToName()" (returned)="returnToServer()" />
            }

            <!-- Gateway tab -->
            @if (activeTab() === 'gateway') {
              <section>
                @if (notice() && !auth.user()) {
                  <p class="mb-4 flex items-start gap-1.5 text-sm text-error font-medium" role="alert">
                    <span class="material-symbols-outlined text-base shrink-0">error</span>
                    <span>{{ noticeText() }}</span>
                  </p>
                }
                <header class="mb-4 flex items-center gap-2">
                  <span class="w-1 h-5 bg-tertiary rounded-full"></span>
                  <h3 class="text-xs font-bold uppercase tracking-widest text-on-surface-variant">IRIS API Gateway</h3>
                </header>
                <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <div class="md:col-span-2">
                    <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">API Base URL</label>
                    <input type="text" [(ngModel)]="gatewayForm.apiBaseUrl" [readonly]="hosted"
                           class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all"
                           [class.opacity-60]="hosted"
                           placeholder="http://localhost:52773/csp/opcua/api">
                    @if (hosted) {
                      <p class="text-xs text-on-surface-variant mt-1.5 ml-1">
                        Set by the installer: IRIS serves this console next to its API. Sign in with your IRIS account below.
                      </p>
                    }
                  </div>
                  <!-- The password is used once, to sign in, and never stored. The
                       session is a token for this tab (AuthService). -->
                  @if (auth.user(); as user) {
                    <div class="md:col-span-2 flex items-center gap-3 bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-3">
                      <span class="material-symbols-outlined text-xl text-tertiary">verified_user</span>
                      <p class="text-sm text-on-surface flex-1">Signed in to IRIS as <strong class="font-semibold">{{ user }}</strong></p>
                      <button type="button" (click)="signOut()"
                              class="text-xs font-semibold text-primary hover:underline">Sign out</button>
                    </div>
                  } @else {
                    <div>
                      <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">IRIS Username</label>
                      <input type="text" [(ngModel)]="signInForm.username" (ngModelChange)="signInError.set('')" autocomplete="username"
                             class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all">
                    </div>
                    <div>
                      <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">IRIS Password</label>
                      <input type="password" [(ngModel)]="signInForm.password" (ngModelChange)="signInError.set('')" (keydown.enter)="signIn()" autocomplete="current-password"
                             class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all">
                    </div>
                    <div class="md:col-span-2 flex flex-col sm:flex-row sm:items-center gap-3 -mt-2">
                      <button type="button" (click)="signIn()" [disabled]="signingIn() || !signInForm.username"
                              class="flex items-center justify-center gap-2 px-5 py-2.5 text-primary text-sm font-semibold rounded-lg hover:bg-primary/5 transition-all border border-outline-variant/30 disabled:opacity-50 shrink-0">
                        <span class="material-symbols-outlined text-xl" [class.animate-spin]="signingIn()">{{ signingIn() ? 'progress_activity' : 'login' }}</span>
                        {{ signingIn() ? 'Signing in…' : 'Sign in' }}
                      </button>
                      @if (signInError()) {
                        <p class="flex items-start gap-1.5 text-xs text-error font-medium" role="alert">
                          <span class="material-symbols-outlined text-sm shrink-0">error</span>
                          <span>{{ signInError() }}</span>
                        </p>
                      } @else {
                        <p class="text-[11px] text-on-surface-muted">
                          The password is not stored. You stay signed in in this tab until you sign out, close it, or are idle for a while.
                        </p>
                      }
                    </div>
                  }
                  <div>
                    <label class="block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1">Auto-refresh interval (seconds)</label>
                    <input type="number" [(ngModel)]="gatewayForm.autoRefreshInterval" min="1" max="60"
                           class="w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all">
                    <!-- The min/max already existed (C4); it just was not communicated.
                         Naming the two screens it governs also separates it from the
                         per-service poll interval, which is a different concept with an
                         overlapping name. -->
                    <p class="text-[11px] text-on-surface-muted mt-1">
                      Between 1 and 60. Applies to the node explorer and the business
                      services list — not to how often a service polls its server.
                    </p>
                  </div>
                </div>
              </section>
            }
          </div>

          <!-- Where this configuration lives. Per-browser, not per-user: two operators
               at one workstation share it and the same operator elsewhere has none of
               it. Between the scrolling form and the footer, not pulled up into the
               form's padding, where the form scrolled underneath it. -->
          <p class="px-8 py-3 border-t border-outline-variant/10 flex items-start gap-1.5 text-[11px] text-on-surface-muted">
            <span class="material-symbols-outlined text-sm shrink-0">info</span>
            <span>
              Servers and settings are stored in this browser only and do not follow you to
              another machine. No passwords are stored here: OPC UA credentials are kept in
              IRIS, and the IRIS sign-in lasts for this tab.
            </span>
          </p>

          <!-- Footer Actions -->
          <div class="px-8 py-6 border-t border-outline-variant/10 bg-surface-container-low/50 flex flex-col sm:flex-row items-center justify-between gap-4">
            @if (activeTab() === 'servers' && editingServer()) {
              <!-- The result belongs next to the control that produced it. It used to
                   appear only in the sidebar widget, in the opposite corner. -->
              <div class="flex flex-col sm:flex-row sm:items-center gap-2 w-full sm:w-auto min-w-0">
                <button (click)="testServerConnection()"
                        [disabled]="testing()"
                        class="flex items-center gap-2 px-5 py-2.5 text-primary text-sm font-semibold rounded-lg hover:bg-primary/5 transition-all border border-outline-variant/30 w-full sm:w-auto disabled:opacity-50 shrink-0">
                  <span class="material-symbols-outlined text-xl"
                        [class.animate-spin]="testing()">{{ testing() ? 'progress_activity' : 'network_check' }}</span>
                  {{ testing() ? 'Testing…' : 'Test Connection' }}
                </button>
                @if (testStatus() && !testing()) {
                  <p class="flex items-start gap-1.5 text-xs font-medium max-w-xs min-w-0"
                     [class]="testFailed() ? 'text-error' : 'text-tertiary'">
                    <span class="material-symbols-outlined text-sm shrink-0">
                      {{ testFailed() ? 'error' : 'check_circle' }}
                    </span>
                    <span class="break-words">{{ testStatus() }}</span>
                  </p>
                }
              </div>
            } @else {
              <div></div>
            }
            <div class="flex items-center gap-3 w-full sm:w-auto">
              <!-- The error belongs at the control that was pressed. Putting it in
                   the sidebar widget instead is the mistake F5 is about. -->
              @if (saveError()) {
                <p class="flex items-start gap-1.5 text-xs text-error font-medium max-w-xs order-first sm:order-none">
                  <span class="material-symbols-outlined text-sm shrink-0">error</span>
                  <span>{{ saveError() }}</span>
                </p>
              }
              <button (click)="closed.emit()"
                      class="flex-1 sm:flex-none px-6 py-2.5 text-on-surface-variant text-sm font-semibold rounded-lg hover:bg-surface-variant transition-all">
                Cancel
              </button>
              <button (click)="saveAll()" [disabled]="saving()"
                      class="flex-1 sm:flex-none px-8 py-2.5 bg-gradient-to-br from-primary to-primary-container text-on-primary text-sm font-semibold rounded-lg shadow-lg shadow-primary/20 hover:scale-[1.02] active:scale-[0.98] transition-all disabled:opacity-50">
                {{ saving() ? 'Saving…' : 'Save Changes' }}
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  `,
})
export class SettingsModalComponent implements OnInit {
  private configService = inject(ConfigService);
  private api = inject(ApiService);

  closed = output<void>();
  initialTab = input<'servers' | 'security' | 'gateway'>('servers');
  /** Why Settings opened by itself, e.g. "Sign-in failed" after a 401. */
  notice = input('');

  readonly hosted = this.configService.hosted;

  activeTab = signal<'servers' | 'security' | 'gateway'>('servers');
  /** Server whose form sent the user to the Security tab, for the "Return to" link. */
  returnTo = signal<string | null>(null);
  returnToName = computed(() => this.servers().find((x) => x.id === this.returnTo())?.name ?? '');

  /** Opens the Security tab on behalf of a server form. */
  openSecurity(serverId: string): void {
    this.returnTo.set(serverId);
    this.activeTab.set('security');
  }

  returnToServer(): void {
    const server = this.servers().find((x) => x.id === this.returnTo());
    this.returnTo.set(null);
    if (server) this.selectServer(server);
    else this.activeTab.set('servers');
  }
  testing = signal(false);
  /** The last test result for the server being edited; cleared when another is selected. */
  lastTest = signal<ConnectionTestResult | null>(null);
  testStatus = signal('');
  /** Rendered at the Save button — the control the user just pressed. */
  saveError = signal('');
  /**
   * Whether the last test failed. Kept separate from the message so the styling
   * never has to infer an outcome by matching on the text.
   */
  testFailed = signal(false);

  readonly auth = inject(AuthService);
  signInForm = { username: '', password: '' };
  signingIn = signal(false);
  signInError = signal('');

  readonly NEW = NEW_CREDENTIALS;
  /** IRIS credentials entries, from GET /credentials. */
  credentialsList = signal<CredentialsEntry[]>([]);
  credentialsError = signal('');
  /** Unsaved credentials per server ID. */
  drafts = signal<Record<string, CredentialsDraft>>({});

  // Server list (mutable copies for editing)
  servers = signal<ServerProfile[]>([]);
  selectedServerId = signal<string | null>(null);
  editingServer = signal<ServerProfile | null>(null);
  serverStatuses = signal<Record<string, 'online' | 'offline' | 'testing'>>({});

  // Gateway form (shared settings)
  gatewayForm: { apiBaseUrl: string; autoRefreshInterval: number };

  constructor() {
    const cfg = this.configService.get();
    // Deep-copy servers for editing
    this.servers.set((cfg.servers || []).map(s => ({ ...s })));
    this.gatewayForm = {
      apiBaseUrl: cfg.apiBaseUrl,
      autoRefreshInterval: cfg.autoRefreshInterval,
    };
    this.signInForm.username = cfg.apiUsername;

    // Auto-select first server if any
    const svrs = this.servers();
    if (svrs.length > 0) {
      this.selectServer(svrs[0]);
    }
    this.loadCredentials();
  }

  loadCredentials(): void {
    this.api.listCredentials().subscribe({
      next: (list) => {
        this.credentialsList.set(list);
        this.credentialsError.set('');
      },
      error: (err) => this.credentialsError.set(apiErrorMessage(err, 'Request failed')),
    });
  }

  // --- Credentials of the server being edited ---

  draft(): CredentialsDraft | null {
    const server = this.editingServer();
    return (server && this.drafts()[server.id]) || null;
  }

  /** What the select shows: the draft's choice while one is open. */
  credentialsChoice(): string {
    const d = this.draft();
    if (d) return d.mode === 'new' ? NEW_CREDENTIALS : d.id;
    return this.editingServer()?.credentials || '';
  }

  /**
   * The list, plus the server's own ID if the list lacks it (it failed to load, or
   * the entry was deleted in the Portal), so the select never silently shows another.
   */
  credentialOptions(): CredentialsEntry[] {
    const list = this.credentialsList();
    const id = this.editingServer()?.credentials;
    if (id && !this.findEntry(id)) return [...list, { id, username: '', usedBy: [], pipeline: '' }];
    return list;
  }

  selectedEntry(): CredentialsEntry | undefined {
    const id = this.editingServer()?.credentials;
    return id ? this.findEntry(id) : undefined;
  }

  draftEntry(): CredentialsEntry | undefined {
    const d = this.draft();
    return d ? this.findEntry(d.id) : undefined;
  }

  private findEntry(id: string): CredentialsEntry | undefined {
    const lower = id.toLowerCase();
    return this.credentialsList().find((c) => c.id.toLowerCase() === lower);
  }

  usageText(entry: CredentialsEntry): string {
    const n = entry.usedBy.length;
    let text = n === 0 ? 'No pipeline uses it.' : `Used by ${n === 1 ? 'pipeline' : n + ' pipelines'}: ${entry.usedBy.join(', ')}. Changes apply to ${n === 1 ? 'it' : 'all of them'} on their next connect.`;
    if (entry.pipeline) text += ` Made for pipeline ${entry.pipeline}, and deleted with it.`;
    return text;
  }

  chooseCredentials(value: string): void {
    const server = this.editingServer();
    if (!server) return;
    this.lastTest.set(null);
    this.clearSaveError();
    if (value === NEW_CREDENTIALS) {
      this.setDraft(server.id, { mode: 'new', id: this.suggestId(server), username: '', password: '' });
      return;
    }
    this.setDraft(server.id, null);
    server.credentials = value;
  }

  editCredentials(entry: CredentialsEntry): void {
    const server = this.editingServer();
    if (server) this.setDraft(server.id, { mode: 'edit', id: entry.id, username: entry.username, password: '' });
  }

  discardDraft(): void {
    const server = this.editingServer();
    if (server) this.setDraft(server.id, null);
    this.clearSaveError();
  }

  private setDraft(serverId: string, d: CredentialsDraft | null): void {
    this.drafts.update((all) => {
      const next = { ...all };
      if (d) next[serverId] = d;
      else delete next[serverId];
      return next;
    });
  }

  /** "OPCUA-" plus the server's name or host, as the Portal would read it cleanly. */
  private suggestId(server: ServerProfile): string {
    const host = server.url.match(/:\/\/([^:/]+)/)?.[1] || '';
    const base = ('OPCUA-' + (server.name || host || 'Server')).replace(/[^A-Za-z0-9._-]/g, '_').slice(0, 50);
    let id = base;
    for (let n = 2; this.findEntry(id); n++) id = `${base.slice(0, 47)}-${n}`;
    return id;
  }

  ngOnInit(): void {
    this.activeTab.set(this.initialTab());
  }

  /**
   * @param switchTab true for a user clicking a row — the servers form is what they
   * are asking for, and on the gateway tab selecting one invisibly would look like
   * the click did nothing. False when the selection is a consequence rather than a
   * request, e.g. falling back to another server after a removal, where yanking the
   * tab out from under someone editing the gateway would be the surprise.
   */
  selectServer(server: ServerProfile, switchTab = true): void {
    if (this.selectedServerId() !== server.id) this.lastTest.set(null);
    this.selectedServerId.set(server.id);
    // Find mutable reference from our servers list
    const found = this.servers().find(s => s.id === server.id);
    this.editingServer.set(found || null);
    if (switchTab) this.activeTab.set('servers');
  }

  addNewServer(): void {
    const newServer: ServerProfile = {
      id: 'new_' + Date.now().toString(36),
      name: '',
      url: '',
      securityMode: 1,
      credentials: '',
      certPath: '',
      keyPath: '',
      trustDir: '',
      crlDir: '',
      clientURI: '',
    };
    this.servers.update(list => [...list, newServer]);
    this.selectServer(newServer);
  }

  removeServer(id: string, event: MouseEvent): void {
    event.stopPropagation();
    this.servers.update(list => list.filter(s => s.id !== id));
    // Removing the row is the other way to resolve a "no server URL" error.
    this.clearSaveError();
    if (this.selectedServerId() === id) {
      const remaining = this.servers();
      if (remaining.length > 0) {
        this.selectServer(remaining[0], false);
      } else {
        this.selectedServerId.set(null);
        this.editingServer.set(null);
      }
    }
  }

  async testServerConnection(): Promise<void> {
    const server = this.editingServer();
    if (!server || !server.url) return;

    this.testing.set(true);
    this.serverStatuses.update(s => ({ ...s, [server.id]: 'testing' }));

    // Temporarily save gateway settings so API base URL is current
    await this.applyApiAddress();

    // An unsaved username and password are tested as typed, for this request only.
    // A change that keeps the stored password tests with the stored entry.
    const d = this.drafts()[server.id];
    let login: InlineLogin | undefined;
    if (d && (d.mode === 'new' || d.password)) login = { username: d.username, password: d.password };
    const target = d?.mode === 'edit' && !login ? { ...server, credentials: d.id } : server;

    this.api.test(target, login).subscribe({
      next: (result) => {
        this.testing.set(false);
        this.lastTest.set(isManaged(target) ? result : null);
        if (result.connected) {
          this.testFailed.set(false);
          this.testStatus.set(isManaged(target) ? 'Connected · Sign & Encrypt' : `Connected (${result.responseTimeMs}ms)`);
          this.serverStatuses.update(s => ({ ...s, [server.id]: 'online' }));
        } else {
          this.testFailed.set(true);
          this.testStatus.set(result.security?.diagnosis?.message || result.error || 'Connection failed');
          this.serverStatuses.update(s => ({ ...s, [server.id]: 'offline' }));
        }
      },
      error: (err) => {
        this.testing.set(false);
        this.testFailed.set(true);
        this.testStatus.set(apiErrorMessage(err, 'Connection test failed'));
        this.serverStatuses.update(s => ({ ...s, [server.id]: 'offline' }));
      },
    });
  }

  /**
   * Clear the save error. Called on any field edit: leaving a stale complaint
   * beside the button while the user fixes the thing it complains about reads as
   * the app not noticing.
   */
  noticeText(): string {
    return this.notice() === NOT_SIGNED_IN
      ? 'Sign in with your IRIS account to use the console.'
      : 'IRIS refused the current sign-in. Sign in again.';
  }

  async signIn(): Promise<void> {
    if (this.signingIn() || !this.signInForm.username) return;
    // Sign in to the API address in the form, which may not be saved yet.
    await this.applyApiAddress();
    this.signingIn.set(true);
    this.signInError.set('');
    try {
      await this.auth.signIn(this.signInForm.username, this.signInForm.password);
      this.signInForm.password = '';
      this.loadCredentials();
    } catch (err: any) {
      this.signInError.set(err?.message || 'Sign-in failed');
    } finally {
      this.signingIn.set(false);
    }
  }

  async signOut(): Promise<void> {
    await this.auth.signOut();
    this.credentialsList.set([]);
  }

  /**
   * Save the gateway form. A session belongs to the API it signed in to, so a
   * changed address signs out first.
   */
  private async applyApiAddress(): Promise<void> {
    if (this.gatewayForm.apiBaseUrl !== this.configService.get().apiBaseUrl) await this.auth.signOut();
    this.configService.save(this.gatewayForm);
  }

  clearSaveError(): void {
    // Every caller is a field edit; a test result no longer describes the edited profile.
    this.lastTest.set(null);
    if (this.saveError()) this.saveError.set('');
  }

  saving = signal(false);

  async saveAll(): Promise<void> {
    if (this.saving()) return;
    const all = this.servers();
    const invalid = all.filter(s => !s.url);
    if (invalid.length) {
      // Silently dropping a row the user filled in is data loss. Name it and stop.
      const which = invalid.map(s => s.name || 'Untitled server').join(', ');
      this.saveError.set(
        `${which} ${invalid.length === 1 ? 'has' : 'have'} no server URL. ` +
        `Add one, or remove the row, before saving.`
      );
      return;
    }
    this.saveError.set('');

    // Credentials first: a server is saved pointing at an entry only once IRIS has it.
    // The API address may have just changed, so it is saved before calling it.
    await this.applyApiAddress();
    this.saving.set(true);
    try {
      for (const server of all) {
        const d = this.drafts()[server.id];
        if (!d) continue;
        const name = server.name || 'Untitled server';
        if (!d.username) throw new Error(`${name}: credentials need a username.`);
        try {
          const saved = d.mode === 'new'
            ? await firstValueFrom(this.api.createCredentials(d.id, d.username, d.password))
            : await firstValueFrom(this.api.updateCredentials(d.id, d.username, d.password));
          server.credentials = saved.id;
          this.setDraft(server.id, null);
        } catch (err) {
          throw new Error(`${name}: ${apiErrorMessage(err, 'Could not save its credentials')}`);
        }
      }
    } catch (err: any) {
      this.saving.set(false);
      this.saveError.set(err.message);
      this.loadCredentials();
      return;
    }
    this.saving.set(false);

    const validServers = all;
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
      certPath: validServers[0]?.certPath || '',
      keyPath: validServers[0]?.keyPath || '',
      trustDir: validServers[0]?.trustDir || '',
      crlDir: validServers[0]?.crlDir || '',
      clientURI: validServers[0]?.clientURI || '',
    });

    setTimeout(() => this.closed.emit(), 500);
  }

  /**
   * A new Sign & Encrypt profile is managed: no certificate paths are filled in, so
   * IRIS uses its own client identity. The old per-profile defaults are gone on purpose.
   */
  onSecurityModeChange(_mode: number): void {
    this.lastTest.set(null);
    this.testStatus.set('');
  }

  onOverlayClick(event: MouseEvent): void {
    if ((event.target as HTMLElement).classList.contains('fixed')) {
      this.closed.emit();
    }
  }
}

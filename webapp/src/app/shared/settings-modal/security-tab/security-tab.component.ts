import { Component, computed, inject, input, OnInit, output, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpErrorResponse } from '@angular/common/http';
import { ApiService, apiErrorMessage } from '../../../core/services/api.service';
import { ConfigService } from '../../../core/services/config.service';
import { IdentityStatus, TrustedServer } from '../../../core/models/opcua.models';
import { bytesToHex } from '../../../core/util/hex';
import { ConfirmDialogComponent } from '../../confirm-dialog/confirm-dialog.component';

type Slot = 'cert' | 'key' | 'pfx';

const inputCls =
  'w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all';
const labelCls = 'block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1';

/**
 * The IRIS instance's OPC UA client identity: one certificate shared by every
 * Sign & Encrypt connection. The private key is never shown; an uploaded key is
 * held only for the length of the request.
 */
@Component({
  selector: 'app-security-tab',
  standalone: true,
  imports: [CommonModule, FormsModule, ConfirmDialogComponent],
  template: `
    <section class="space-y-6">
      <header class="flex items-center gap-2">
        <span class="w-1 h-5 bg-primary rounded-full"></span>
        <div>
          <h3 class="text-xs font-bold uppercase tracking-widest text-on-surface-variant">IRIS client identity</h3>
          <p class="text-sm text-on-surface-variant">The certificate identifies IRIS to OPC UA servers. Its private key stays on IRIS.</p>
        </div>
      </header>

      @if (loading()) {
        <p class="text-sm text-on-surface-variant">Loading…</p>
      } @else if (forbidden()) {
        <p class="text-sm text-error font-medium" role="alert">Managing OPC UA certificates needs a SuperUser account.</p>
      } @else if (loadError()) {
        <p class="text-sm text-error font-medium" role="alert">{{ loadError() }}</p>
      } @else if (status()) {
        @let st = status()!;
        @if (st.configured) {
          <div class="p-4 rounded-xl bg-surface-container-low space-y-3">
            <div class="flex items-center justify-between gap-3">
              <h4 class="text-sm font-semibold text-on-surface">
                Default IRIS client ·
                <span [class]="stateClass()">{{ stateText() }}</span>
              </h4>
            </div>
            @for (issue of st.errors; track issue.code) {
              <p class="text-xs text-error">{{ issue.message }}</p>
            }
            @for (issue of st.warnings; track issue.code) {
              <p class="text-xs text-amber-700">{{ issue.message }}</p>
            }
            <dl class="grid grid-cols-[7rem_1fr] gap-x-3 gap-y-1.5 text-sm">
              <dt class="text-on-surface-variant">Client URI</dt>
              <dd class="break-all">{{ st.clientURI }}</dd>
              <dt class="text-on-surface-variant">Fingerprint</dt>
              <dd class="flex items-start gap-2">
                <code class="font-mono text-xs break-all">{{ st.fingerprint }}</code>
                <button type="button" (click)="copyFingerprint()" title="Copy fingerprint"
                        class="text-on-surface-variant hover:text-primary shrink-0">
                  <span class="material-symbols-outlined text-base">{{ copied() ? 'check' : 'content_copy' }}</span>
                </button>
              </dd>
              <dt class="text-on-surface-variant">Valid</dt>
              <dd>{{ st.notBefore }} to {{ st.notAfter }}</dd>
              <dt class="text-on-surface-variant">Source</dt>
              <dd>{{ st.source }}</dd>
            </dl>
            <div class="flex flex-wrap gap-3 pt-2">
              <button type="button" (click)="download('der')" class="px-4 py-2 text-sm font-semibold rounded-lg border border-outline-variant/30 text-primary hover:bg-primary/5">Download certificate (DER)</button>
              <button type="button" (click)="download('pem')" class="px-4 py-2 text-sm font-semibold rounded-lg border border-outline-variant/30 text-primary hover:bg-primary/5">Download certificate (PEM)</button>
              <button type="button" (click)="askReplace(createNew)" class="px-4 py-2 text-sm font-semibold rounded-lg text-error hover:bg-error-container/30">Replace…</button>
            </div>
          </div>
        } @else {
          <div class="p-4 rounded-xl bg-surface-container-low">
            <h4 class="text-sm font-semibold text-on-surface">No identity configured</h4>
            <p class="text-sm text-on-surface-variant">Create a certificate and private key on IRIS, or use an existing pair.</p>
          </div>
          @for (c of st.candidates ?? []; track c.certPath) {
            <div class="p-3 rounded-lg bg-tertiary-fixed text-on-tertiary-fixed flex items-center justify-between gap-3 text-sm">
              <span>A certificate was found on IRIS: {{ c.clientURI || c.certPath }}@if (c.notAfter) { · expires {{ c.notAfter }}}</span>
              <button type="button" (click)="useCandidate(c.certPath, c.keyPath)" class="font-semibold underline shrink-0">Use it</button>
            </div>
          }
          <div class="flex flex-wrap gap-3">
            <button type="button" (click)="createNew()" [disabled]="busy()"
                    class="px-5 py-2.5 bg-primary text-on-primary text-sm font-semibold rounded-lg shadow-lg shadow-primary/20 hover:brightness-110 disabled:opacity-60">Create client identity</button>
            <button type="button" (click)="showImport.set(!showImport())"
                    class="px-5 py-2.5 text-primary text-sm font-semibold rounded-lg border border-outline-variant/30 hover:bg-primary/5">Use existing certificate</button>
          </div>
        }

        @if (!st.configured && showImport()) {
          <ng-container *ngTemplateOutlet="importForm" />
        }

        @if (message()) {
          <p class="text-sm text-on-surface-variant" role="status">{{ message() }}</p>
        }
        @if (error()) {
          <p class="text-sm text-error font-medium" role="alert">{{ error() }}</p>
        }

        <details class="text-sm text-on-surface-variant">
          <summary class="cursor-pointer font-semibold">Advanced</summary>
          <div class="mt-4 space-y-5">
            @if (!st.configured) {
              <div>
                <label [class]="labelCls" for="sec-client-uri">Client URI</label>
                <input id="sec-client-uri" type="text" [class]="inputCls" placeholder="urn:iris:opcua-client"
                       [ngModel]="clientURI()" (ngModelChange)="clientURI.set($event)">
                <p class="text-xs mt-1 ml-1">Used for a newly created certificate. Leave empty for the default.</p>
              </div>
              <div class="space-y-2">
                <p class="font-semibold">Use files already on IRIS</p>
                <input type="text" [class]="inputCls" placeholder="Certificate path on IRIS" aria-label="Certificate path on IRIS"
                       [ngModel]="certPath()" (ngModelChange)="certPath.set($event)">
                <input type="text" [class]="inputCls" placeholder="Private key path on IRIS" aria-label="Private key path on IRIS"
                       [ngModel]="keyPath()" (ngModelChange)="keyPath.set($event)">
                <button type="button" (click)="useFiles()" [disabled]="!canUseFiles() || busy()"
                        class="px-4 py-2 text-sm font-semibold rounded-lg border border-outline-variant/30 text-primary disabled:opacity-50">Validate and use</button>
              </div>
            } @else if (st.advanced) {
              <dl class="grid grid-cols-[7rem_1fr] gap-x-3 gap-y-1.5">
                <dt>Certificate file</dt><dd class="font-mono text-xs break-all">{{ st.advanced.certPath }}</dd>
                <dt>Key file</dt><dd class="font-mono text-xs break-all">{{ st.advanced.keyPath }}</dd>
                <dt>Store root</dt><dd class="font-mono text-xs break-all">{{ st.advanced.storeRoot }}</dd>
              </dl>
            }
            <div>
              <p class="font-semibold mb-2">Trusted servers</p>
              @for (s of trusted(); track s.key) {
                <div class="flex items-center justify-between gap-3 py-1.5 border-b border-outline-variant/10">
                  <div class="min-w-0">
                    <p class="text-sm text-on-surface truncate">{{ s.label || s.url }}</p>
                    <p class="text-[10px] font-mono truncate">{{ s.url }}</p>
                  </div>
                  <button type="button" (click)="stopTrusting(s)" class="text-xs font-semibold text-error hover:underline shrink-0">Stop trusting</button>
                </div>
              } @empty {
                <p class="text-xs">No trusted servers yet.</p>
              }
            </div>
          </div>
        </details>
      }

      @if (returnTo()) {
        <footer class="pt-4 border-t border-outline-variant/10">
          <button type="button" (click)="returned.emit()" class="text-sm font-semibold text-primary hover:underline">Return to {{ returnTo() }}</button>
        </footer>
      }
    </section>

    <ng-template #importForm>
      <div class="p-4 rounded-xl border border-outline-variant/20 space-y-4">
        @if (insecure()) {
          <p class="text-xs text-amber-800 bg-amber-50 rounded-lg p-3" role="alert">
            This sends the private key over an unencrypted connection. Prefer “Use files already on IRIS” under Advanced.
          </p>
        }
        <!-- Re-created after each import so the browser drops the chosen files. -->
        @for (k of [formKey()]; track k) {
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label [class]="labelCls" for="sec-cert">Certificate (.der)</label>
              <input id="sec-cert" type="file" accept=".der,.crt,.cer" (change)="onFile('cert', $event)" [class]="inputCls">
            </div>
            <div>
              <label [class]="labelCls" for="sec-key">Private key (.der)</label>
              <input id="sec-key" type="file" accept=".der,.key" (change)="onFile('key', $event)" [class]="inputCls">
            </div>
            <div>
              <label [class]="labelCls" for="sec-pfx">Or one .pfx / .p12 file</label>
              <input id="sec-pfx" type="file" accept=".pfx,.p12" (change)="onFile('pfx', $event)" [class]="inputCls">
            </div>
            <div>
              <label [class]="labelCls" for="sec-pfx-pw">File password</label>
              <input id="sec-pfx-pw" type="password" autocomplete="off" [class]="inputCls"
                     [ngModel]="pfxPassword()" (ngModelChange)="pfxPassword.set($event)">
            </div>
          </div>
        }
        <button type="button" (click)="submitImport()" [disabled]="!canImport() || busy()"
                class="px-4 py-2 bg-primary text-on-primary text-sm font-semibold rounded-lg disabled:opacity-50">Validate and use</button>
      </div>
    </ng-template>

    @if (pending()) {
      <app-confirm-dialog
        title="Replace the client identity?"
        [detail]="replaceDetail()"
        confirmLabel="Replace"
        (confirmed)="confirmReplace()"
        (cancelled)="pending.set(null)" />
    }
  `,
})
export class SecurityTabComponent implements OnInit {
  private api = inject(ApiService);
  private config = inject(ConfigService);

  /** Name of the server profile to go back to, when Security was opened from it. */
  returnTo = input('');
  returned = output<void>();

  readonly inputCls = inputCls;
  readonly labelCls = labelCls;

  loading = signal(true);
  forbidden = signal(false);
  loadError = signal('');
  status = signal<IdentityStatus | null>(null);
  trusted = signal<TrustedServer[]>([]);
  busy = signal(false);
  error = signal('');
  message = signal('');
  copied = signal(false);

  showImport = signal(false);
  clientURI = signal('');
  certPath = signal('');
  keyPath = signal('');
  pfxPassword = signal('');
  formKey = signal(0);
  /** The Replace dialog's action, or null while it is closed. */
  pending = signal<(() => void) | null>(null);

  // Picked files, kept as hex only until the request is sent.
  private picked = signal<Record<Slot, string>>({ cert: '', key: '', pfx: '' });

  readonly createNew = () => this.run(this.api.createIdentity({ clientURI: this.clientURI().trim() || undefined, ...this.guard() }), 'Identity created on IRIS.');

  canUseFiles = computed(() => !!this.certPath().trim() && !!this.keyPath().trim());
  canImport = computed(() => {
    const p = this.picked();
    return (!!p.cert && !!p.key) || (!!p.pfx && !!this.pfxPassword());
  });

  /** A key upload over plain http to anything but this machine is readable on the wire. */
  insecure = computed(() => {
    try {
      const u = new URL(this.config.get().apiBaseUrl, location.href);
      return u.protocol === 'http:' && u.hostname !== 'localhost' && u.hostname !== '127.0.0.1';
    } catch {
      return false;
    }
  });

  stateText = computed(() => {
    const st = this.status();
    if (!st) return '';
    if (st.errors.some((e) => e.code === 'expired')) return 'Expired';
    if (st.errors.length) return 'Needs attention';
    if (st.daysLeft !== undefined && st.daysLeft <= 30) return `Expires in ${st.daysLeft} days`;
    return st.ready ? 'Ready' : 'Not ready';
  });

  stateClass = computed(() => {
    const t = this.stateText();
    if (t === 'Ready') return 'text-emerald-700';
    if (t.startsWith('Expires')) return 'text-amber-700';
    return 'text-error';
  });

  replaceDetail = computed(() => {
    const impact = this.status()?.impact;
    const lines: string[] = [];
    for (const p of impact?.pipelines ?? []) lines.push(`${p.namespace} · ${p.name} · ${p.url}`);
    for (const s of impact?.servers ?? []) lines.push(`${s.label || s.key} · ${s.url}`);
    if (lines.length) lines.push('', 'Each of these servers must approve the new certificate before these connections work again.');
    else lines.push('Servers must approve the new certificate before connections using it work again.');
    return lines.join('\n');
  });

  ngOnInit(): void {
    this.refresh();
  }

  hasPickedFiles(): boolean {
    const p = this.picked();
    return !!(p.cert || p.key || p.pfx || this.pfxPassword());
  }

  private refresh(): void {
    this.api.getIdentity().subscribe({
      next: (st) => {
        this.status.set(st);
        this.loading.set(false);
        this.loadTrusted();
      },
      error: (err) => {
        this.loading.set(false);
        if (err instanceof HttpErrorResponse && err.status === 403) this.forbidden.set(true);
        else this.loadError.set(apiErrorMessage(err, 'Could not load the client identity'));
      },
    });
  }

  private loadTrusted(): void {
    this.api.listTrustedServers().subscribe({ next: (l) => this.trusted.set(l), error: () => this.trusted.set([]) });
  }

  private guard(): { replace?: boolean; currentFingerprint?: string } {
    const st = this.status();
    return st?.configured ? { replace: true, currentFingerprint: st.fingerprint } : {};
  }

  private run(call: import('rxjs').Observable<IdentityStatus>, done: string): void {
    this.busy.set(true);
    this.error.set('');
    this.message.set('');
    call.subscribe({
      next: (st) => {
        this.busy.set(false);
        this.status.set(st);
        this.message.set(done);
        this.showImport.set(false);
        this.loadTrusted();
      },
      error: (err) => {
        this.busy.set(false);
        this.error.set(apiErrorMessage(err));
      },
    });
  }

  askReplace(action: () => void): void {
    this.pending.set(action);
  }

  confirmReplace(): void {
    const action = this.pending();
    this.pending.set(null);
    action?.();
  }

  onFile(slot: Slot, ev: Event): void {
    const file = (ev.target as HTMLInputElement).files?.[0];
    if (file) void this.pickFile(slot, file);
    else this.picked.update((p) => ({ ...p, [slot]: '' }));
  }

  async pickFile(slot: Slot, file: File): Promise<void> {
    const hex = bytesToHex(await file.arrayBuffer());
    this.picked.update((p) => ({ ...p, [slot]: hex }));
  }

  /** Drops every trace of the upload: hex, password and the file inputs themselves. */
  private scrub(): void {
    this.picked.set({ cert: '', key: '', pfx: '' });
    this.pfxPassword.set('');
    this.formKey.update((k) => k + 1);
  }

  submitImport(): void {
    if (this.status()?.configured) this.askReplace(() => void this.importPair());
    else void this.importPair();
  }

  async importPair(): Promise<void> {
    const p = this.picked();
    const body = p.pfx && this.pfxPassword()
      ? { pkcs12: p.pfx, password: this.pfxPassword() }
      : { certificate: p.cert, key: p.key };
    this.scrub();
    this.run(this.api.importIdentity({ ...body, ...this.guard() }), 'Certificate imported.');
  }

  useCandidate(certPath: string, keyPath: string): void {
    this.run(this.api.useIdentityFiles({ certPath, keyPath }), 'Using the certificate found on IRIS.');
  }

  useFiles(): void {
    this.run(this.api.useIdentityFiles({ certPath: this.certPath().trim(), keyPath: this.keyPath().trim(), ...this.guard() }), 'Using the files on IRIS.');
  }

  copyFingerprint(): void {
    const fp = this.status()?.fingerprint;
    if (!fp) return;
    navigator.clipboard?.writeText(fp).then(() => {
      this.copied.set(true);
      setTimeout(() => this.copied.set(false), 1500);
    }, () => undefined);
  }

  download(format: 'der' | 'pem'): void {
    this.error.set('');
    this.api.downloadClientCertificate(format).subscribe({
      next: (blob) => {
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `iris-opcua-client.${format}`;
        a.click();
        URL.revokeObjectURL(url);
      },
      error: (err) => this.error.set(apiErrorMessage(err, 'Download failed')),
    });
  }

  stopTrusting(s: TrustedServer): void {
    this.api.removeTrustedServer(s.key).subscribe({
      next: () => this.loadTrusted(),
      error: (err) => this.error.set(apiErrorMessage(err)),
    });
  }
}

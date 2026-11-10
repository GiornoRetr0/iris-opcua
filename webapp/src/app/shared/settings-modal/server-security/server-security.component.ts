import { Component, effect, ElementRef, inject, input, output, signal, untracked } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ApiService, apiErrorMessage } from '../../../core/services/api.service';
import {
  ConnectionTestResult, IdentityStatus, isManaged, ServerCertificateReview, ServerProfile,
} from '../../../core/models/opcua.models';
import { bytesToHex } from '../../../core/util/hex';
import { saveBlob } from '../../../core/util/download';

const inputCls =
  'w-full bg-surface-container-low border border-outline-variant/20 rounded-lg px-4 py-2.5 text-sm focus:ring-2 focus:ring-primary focus:border-transparent outline-none transition-all';
const labelCls = 'block text-[10px] font-bold text-on-surface-variant uppercase mb-1.5 ml-1';
const btnCls = 'px-4 py-2 text-sm font-semibold rounded-lg border border-outline-variant/30 text-primary hover:bg-primary/5 disabled:opacity-50';

/**
 * Sign & Encrypt readiness for one server profile: IRIS's own identity, the server's
 * certificate, and whether the server has approved IRIS. A profile that still has
 * certificate paths is manual and shows those instead.
 */
@Component({
  selector: 'app-server-security',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <section>
      <header class="mb-4 flex items-center gap-2">
        <span class="w-1 h-5 bg-tertiary rounded-full"></span>
        <h3 class="text-xs font-bold uppercase tracking-widest text-on-surface-variant">Sign &amp; Encrypt readiness</h3>
      </header>

      @if (manual()) {
        <p class="text-sm text-on-surface mb-3"><strong class="font-semibold">Manual certificate files</strong> — this profile uses the paths below, as before.</p>
        <details class="text-sm text-on-surface-variant" [open]="true">
          <summary class="cursor-pointer font-semibold mb-4">Advanced</summary>
          <div class="grid grid-cols-1 gap-6">
            <div>
              <label [class]="labelCls">Client URI (must match certificate)</label>
              <input type="text" [(ngModel)]="server().clientURI" [class]="inputCls">
            </div>
            <div>
              <label [class]="labelCls">Client Certificate (DER path on IRIS server)</label>
              <input type="text" [(ngModel)]="server().certPath" [class]="inputCls">
            </div>
            <div>
              <label [class]="labelCls">Private Key (DER path on IRIS server)</label>
              <input type="text" [(ngModel)]="server().keyPath" [class]="inputCls">
            </div>
            <div>
              <label [class]="labelCls">Trust List Directory</label>
              <input type="text" [(ngModel)]="server().trustDir" [class]="inputCls">
            </div>
            <div>
              <label [class]="labelCls">Revocation List Directory</label>
              <input type="text" [(ngModel)]="server().crlDir" [class]="inputCls">
            </div>
          </div>
        </details>
      } @else {
        <ul class="space-y-3">
          <!-- 1. IRIS client identity -->
          <li class="p-4 rounded-xl bg-surface-container-low">
            <div class="flex items-center justify-between gap-3">
              <div class="min-w-0">
                <p class="text-sm font-semibold text-on-surface">IRIS client identity</p>
                <p class="text-xs" [class]="identityOk() ? 'text-emerald-700' : 'text-error'">{{ identityText() }}</p>
              </div>
              @if (!identityOk() && identityLoaded()) {
                <button type="button" (click)="setupIdentity.emit()" [class]="btnCls">Set up identity</button>
              }
            </div>
          </li>

          <!-- 2. Server certificate -->
          <li class="p-4 rounded-xl bg-surface-container-low space-y-3">
            <div class="flex items-center justify-between gap-3">
              <div class="min-w-0">
                <p class="text-sm font-semibold text-on-surface">Server certificate</p>
                <p class="text-xs" [class]="serverOk() ? 'text-emerald-700' : 'text-on-surface-variant'">{{ serverText() }}</p>
                @if (current() && current()!.changed) {
                  <p class="text-xs font-semibold text-error">Server certificate changed—review and approve the replacement.</p>
                }
                @if (inspectError()) {
                  <p class="text-xs text-error" role="alert">{{ inspectError() }}</p>
                }
              </div>
              <div class="flex gap-2 shrink-0">
                @if (current() && !serverOk()) {
                  <button type="button" (click)="reviewing.set(!reviewing())" [class]="btnCls">Review certificate</button>
                }
                @if (!inspecting()) {
                  <button type="button" (click)="inspect()" [disabled]="!server().url" [class]="btnCls">{{ current() ? 'Check again' : 'Check server' }}</button>
                }
              </div>
            </div>

            @if (current() && (reviewing() || (current()!.needsIssuer && !current()!.changed))) {
              @let r = current()!;
              <div class="p-4 rounded-lg border border-outline-variant/20 space-y-3">
                @if (!r.offersSignAndEncrypt) {
                  <p class="text-sm text-error font-medium">This server does not offer Sign &amp; Encrypt.</p>
                }
                @for (p of r.identity.problems; track p) {
                  <p class="text-sm text-error">{{ p }}</p>
                }
                @if (r.changed && r.previous) {
                  <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <div>
                      <p class="text-[10px] font-bold uppercase text-on-surface-variant mb-1">Trusted until now</p>
                      <ng-container *ngTemplateOutlet="certView; context: { c: r.previous }" />
                    </div>
                    <div>
                      <p class="text-[10px] font-bold uppercase text-on-surface-variant mb-1">Offered now</p>
                      <ng-container *ngTemplateOutlet="certView; context: { c: r.certificate }" />
                    </div>
                  </div>
                } @else {
                  <ng-container *ngTemplateOutlet="certView; context: { c: r.certificate }" />
                }
                @if (r.applicationUri) {
                  <p class="text-xs text-on-surface-variant">Application URI: <span class="break-all">{{ r.applicationUri }}</span></p>
                }
                <p class="text-xs text-on-surface-variant">Compare this fingerprint with the one the server's administrator gives you.</p>
                @if (!r.trusted || r.changed) {
                  <button type="button" (click)="trust()" [disabled]="!canTrust() || busy()"
                          class="px-4 py-2 bg-primary text-on-primary text-sm font-semibold rounded-lg disabled:opacity-50">
                    {{ r.changed ? 'Approve replacement' : 'Trust this server' }}
                  </button>
                }
                @if (r.needsIssuer) {
                  <div class="space-y-2 pt-2 border-t border-outline-variant/10">
                    <p class="text-sm text-on-surface">This certificate was issued by <span class="font-semibold">{{ r.issuerName }}</span>. Add that issuer's certificate and revocation list.</p>
                    <label [class]="labelCls" for="iss-ca">CA certificate</label>
                    <input id="iss-ca" type="file" accept=".der,.crt,.cer" [class]="inputCls" (change)="onIssuerFile('ca', $event)">
                    <label [class]="labelCls" for="iss-crl">Revocation list (CRL)</label>
                    <input id="iss-crl" type="file" accept=".crl,.der" [class]="inputCls" (change)="onIssuerFile('crl', $event)">
                    <button type="button" (click)="addIssuer()" [disabled]="!canAddIssuer() || busy()" [class]="btnCls">Add issuer</button>
                  </div>
                }
                @if (actionError()) {
                  <p class="text-sm text-error font-medium" role="alert">{{ actionError() }}</p>
                }
              </div>
            }
          </li>

          <!-- 3. Server approval of IRIS -->
          <li class="p-4 rounded-xl bg-surface-container-low space-y-2">
            <p class="text-sm font-semibold text-on-surface">Server approval of IRIS</p>
            @if (approval(); as a) {
              <p class="text-xs" [class]="a.ok ? 'text-emerald-700' : 'text-error'">{{ a.text }}</p>
              @if (a.fingerprint) {
                <p class="text-xs text-on-surface-variant">IRIS certificate fingerprint: <code class="font-mono break-all">{{ a.fingerprint }}</code></p>
                <p class="text-xs text-on-surface-variant">IRIS cannot make the server trust it: the server's administrator has to approve this certificate on the server.</p>
                <button type="button" (click)="downloadCertificate()" [class]="btnCls">Download IRIS certificate</button>
                @if (downloadError()) {
                  <p class="text-xs text-error" role="alert">{{ downloadError() }}</p>
                }
              }
            } @else {
              <p class="text-xs text-on-surface-variant">Checked when you test the connection.</p>
            }
          </li>
        </ul>
      }
    </section>

    <ng-template #certView let-c="c">
      <dl class="grid grid-cols-[6rem_1fr] gap-x-3 gap-y-1 text-xs">
        <dt class="text-on-surface-variant">Subject</dt><dd class="break-all">{{ c.subject }}</dd>
        <dt class="text-on-surface-variant">Issuer</dt><dd class="break-all">{{ c.issuer }}</dd>
        <dt class="text-on-surface-variant">Valid</dt><dd>{{ c.notBefore }} to {{ c.notAfter }}</dd>
        <dt class="text-on-surface-variant">SHA-256</dt><dd><code class="font-mono break-all">{{ c.sha256 }}</code></dd>
      </dl>
    </ng-template>
  `,
})
export class ServerSecurityComponent {
  private api = inject(ApiService);
  private host = inject<ElementRef<HTMLElement>>(ElementRef);

  server = input.required<ServerProfile>();
  /** The last Test Connection result for this server, if any. */
  testResult = input<ConnectionTestResult | null>(null);
  setupIdentity = output<void>();

  readonly inputCls = inputCls;
  readonly labelCls = labelCls;
  readonly btnCls = btnCls;

  /** Decided when the profile is shown: clearing a path while typing must not flip the form. */
  manual = signal(false);
  identity = signal<IdentityStatus | null>(null);
  identityLoaded = signal(false);
  private review = signal<ServerCertificateReview | null>(null);
  /**
   * The review, only while it still describes the profile's URL. Editing the URL
   * in place does not recreate this component, so a review made for another address
   * must stop being actionable the moment the address differs.
   */
  current = (): ServerCertificateReview | null => (this.checkedUrl === this.server().url ? this.review() : null);
  /** Bumped by every reset and inspect; a response for an older one is dropped. */
  private requestId = 0;
  inspecting = signal(false);
  inspectError = signal('');
  reviewing = signal(false);
  busy = signal(false);
  actionError = signal('');
  downloadError = signal('');
  private issuer = signal<{ ca: string; crl: string }>({ ca: '', crl: '' });
  private checkedUrl = '';

  constructor() {
    effect(() => {
      const s = this.server();
      untracked(() => this.reset(s));
    });
  }

  private reset(s: ServerProfile): void {
    this.manual.set(!isManaged(s));
    this.requestId++;
    this.inspecting.set(false);
    this.review.set(null);
    this.reviewing.set(false);
    this.inspectError.set('');
    this.actionError.set('');
    this.downloadError.set('');
    this.scrubIssuer();
    if (this.manual()) return;
    this.identityLoaded.set(false);
    this.api.getIdentity().subscribe({
      next: (st) => { this.identity.set(st); this.identityLoaded.set(true); },
      error: () => { this.identity.set(null); this.identityLoaded.set(true); },
    });
    if (s.url) this.inspect();
  }

  identityOk(): boolean {
    const st = this.identity();
    return !!st && st.configured && st.ready;
  }

  identityText(): string {
    const st = this.identity();
    if (!this.identityLoaded()) return 'Checking…';
    if (!st || !st.configured) return 'No identity yet';
    if (st.errors.some((e) => e.code === 'expired')) return 'Expired';
    if (!st.ready) return 'Needs attention';
    return st.daysLeft !== undefined && st.daysLeft <= 30 ? `Ready · expires in ${st.daysLeft} days` : 'Ready';
  }

  serverOk(): boolean {
    const r = this.current();
    return !!r && r.trusted && !r.changed && !r.needsIssuer;
  }

  serverText(): string {
    const r = this.current();
    if (this.inspecting()) return 'Checking the server…';
    if (this.review() && !r) return 'The URL changed — check the server again';
    if (!r) return this.server().url ? 'Not checked yet' : 'Enter the server URL first';
    if (this.serverOk()) return `Trusted · expires ${r.certificate.notAfter}`;
    if (r.changed) return 'Not trusted until you approve the new certificate';
    if (r.needsIssuer) return 'Trusted, but its issuer is missing';
    return 'Not trusted yet';
  }

  canTrust(): boolean {
    const r = this.current();
    return !!r && r.offersSignAndEncrypt && r.identity.problems.length === 0;
  }

  canAddIssuer(): boolean {
    const i = this.issuer();
    return !!i.ca && !!i.crl;
  }

  approval(): { ok: boolean; text: string; fingerprint?: string } | null {
    const t = this.testResult();
    if (!t?.security) return null;
    if (t.connected) return { ok: true, text: 'Approved' };
    const d = t.security.diagnosis;
    if (!d) return { ok: false, text: t.error || 'The connection failed.' };
    if (d.category === 'clientNotApproved') return { ok: false, text: d.message, fingerprint: d.clientFingerprint };
    return { ok: false, text: d.message };
  }

  inspect(): void {
    const url = this.server().url;
    if (!url) return;
    const id = ++this.requestId;
    this.inspecting.set(true);
    this.inspectError.set('');
    this.actionError.set('');
    this.reviewing.set(false);
    this.api.inspectServer(url).subscribe({
      next: (r) => {
        if (id !== this.requestId) return;
        this.inspecting.set(false);
        this.checkedUrl = url;
        this.review.set(r);
      },
      error: (err) => {
        if (id !== this.requestId) return;
        this.inspecting.set(false);
        this.review.set(null);
        this.inspectError.set(apiErrorMessage(err, 'Could not inspect the server'));
      },
    });
  }

  trust(): void {
    const r = this.current();
    if (!r || !this.canTrust()) return;
    this.busy.set(true);
    this.actionError.set('');
    // The URL the review was made for, which is the profile's (current() checks).
    this.api.trustServer(this.checkedUrl, r.certificate.sha256, this.server().name || undefined).subscribe({
      next: (next) => { this.busy.set(false); if (this.checkedUrl === this.server().url) this.review.set(next); },
      error: (err) => { this.busy.set(false); this.actionError.set(apiErrorMessage(err)); },
    });
  }

  onIssuerFile(slot: 'ca' | 'crl', ev: Event): Promise<void> {
    const file = (ev.target as HTMLInputElement).files?.[0];
    if (file) return this.pickIssuer(slot, file);
    this.issuer.update((i) => ({ ...i, [slot]: '' }));
    return Promise.resolve();
  }

  async pickIssuer(slot: 'ca' | 'crl', file: File): Promise<void> {
    const hex = bytesToHex(await file.arrayBuffer());
    this.issuer.update((i) => ({ ...i, [slot]: hex }));
  }

  addIssuer(): void {
    if (!this.current() || !this.canAddIssuer()) return;
    const { ca, crl } = this.issuer();
    this.busy.set(true);
    this.actionError.set('');
    this.api.addServerIssuer(this.checkedUrl, ca, crl).subscribe({
      next: (next) => { this.busy.set(false); this.scrubIssuer(); if (this.checkedUrl === this.server().url) this.review.set(next); },
      error: (err) => { this.busy.set(false); this.actionError.set(apiErrorMessage(err)); },
    });
  }

  private scrubIssuer(): void {
    this.issuer.set({ ca: '', crl: '' });
    this.host.nativeElement.querySelectorAll<HTMLInputElement>('input[type=file]').forEach((i) => (i.value = ''));
  }

  downloadCertificate(): void {
    this.downloadError.set('');
    this.api.downloadClientCertificate('der').subscribe({
      next: (blob) => saveBlob(blob, 'iris-opcua-client.der'),
      error: (err) => this.downloadError.set(apiErrorMessage(err, 'Download failed')),
    });
  }
}

import { TestBed } from '@angular/core/testing';
import { of } from 'rxjs';
import { SettingsModalComponent } from './settings-modal.component';
import { ApiService } from '../../core/services/api.service';
import { AuthService } from '../../core/services/auth.service';
import { ConfigService } from '../../core/services/config.service';
import { ServerCertificateReview, ServerProfile } from '../../core/models/opcua.models';

describe('SettingsModalComponent security readiness', () => {
  const stored: ServerProfile = { id: 's1', name: 'PLC', url: 'opc.tcp://plc:4840', securityMode: 1, credentials: '' };
  let api: jasmine.SpyObj<ApiService>;

  function create() {
    api = jasmine.createSpyObj('ApiService', ['listCredentials', 'test', 'getIdentity', 'inspectServer', 'listTrustedServers']);
    api.listCredentials.and.returnValue(of([]));
    api.getIdentity.and.returnValue(of({ configured: false, ready: false, errors: [], warnings: [] }));
    api.inspectServer.and.returnValue(of({ trusted: true, changed: false, needsIssuer: false, certificate: { notAfter: '2030' } } as unknown as ServerCertificateReview));
    api.listTrustedServers.and.returnValue(of([]));
    TestBed.configureTestingModule({
      imports: [SettingsModalComponent],
      providers: [
        { provide: ApiService, useValue: api },
        { provide: AuthService, useValue: { user: () => 'admin' } },
        { provide: ConfigService, useValue: { get: () => ({ servers: [{ ...stored }], apiBaseUrl: 'http://localhost/api', apiUsername: '', autoRefreshInterval: 5000 }), hosted: () => false, save: () => undefined } },
      ],
    });
    return TestBed.createComponent(SettingsModalComponent);
  }

  it('leaves the certificate paths empty when a new profile switches to Sign & Encrypt', () => {
    const f = create();
    f.detectChanges();
    const c = f.componentInstance;
    c.addNewServer();
    c.editingServer()!.securityMode = 3;
    c.onSecurityModeChange(3);
    const s = c.editingServer()!;
    expect([s.certPath, s.keyPath, s.trustDir, s.crlDir]).toEqual(['', '', '', '']);
    expect(s.clientURI).toBe('');
  });

  it('reports a managed success as Connected · Sign & Encrypt', async () => {
    const f = create();
    f.detectChanges();
    const c = f.componentInstance;
    c.editingServer()!.securityMode = 3;
    api.test.and.returnValue(of({ url: 'u', connected: true, responseTimeMs: 4, security: { managed: true, identityReady: true, serverTrusted: true } }));
    await c.testServerConnection();
    expect(c.testStatus()).toBe('Connected · Sign & Encrypt');
    expect(c.testFailed()).toBeFalse();
  });

  it('reports a managed failure with the diagnosis and never offers None', async () => {
    const f = create();
    f.detectChanges();
    const c = f.componentInstance;
    c.editingServer()!.securityMode = 3;
    api.test.and.returnValue(of({ url: 'u', connected: false, responseTimeMs: 4, error: 'raw', security: { managed: true, identityReady: true, serverTrusted: true, diagnosis: { category: 'network', message: 'Could not reach the server.' } } }));
    await c.testServerConnection();
    expect(c.testStatus()).toBe('Could not reach the server.');
    expect(c.testFailed()).toBeTrue();
    expect(c.editingServer()!.securityMode).toBe(3);
  });

  it('a long test message wraps under the button and cannot push Save out of the modal', async () => {
    const f = create();
    f.detectChanges();
    const c = f.componentInstance;
    c.editingServer()!.securityMode = 3;
    const long = 'The OPC UA server has not approved IRIS certificate yet. '.repeat(6);
    api.test.and.returnValue(of({ url: 'u', connected: false, responseTimeMs: 4, security: { managed: true, identityReady: true, serverTrusted: true, diagnosis: { category: 'network', message: long } } }));
    await c.testServerConnection();
    f.detectChanges();
    const el = f.nativeElement as HTMLElement;
    const msg = el.querySelector('span.break-words')!.closest('p')!;
    expect(msg.className).not.toContain('max-w-xs');
    expect(msg.className).toContain('min-w-0');
    const left = msg.parentElement!;
    expect(left.className).toContain('sm:flex-1');
    expect(left.className).toContain('min-w-0');
    expect(left.className).toContain('flex-col');
    const save = Array.from(el.querySelectorAll('button')).find((b) => b.textContent!.includes('Save Changes'))!;
    expect(save.parentElement!.className).toContain('shrink-0');
  });

  it('opens the Security tab for this server from Set up identity', () => {
    const f = create();
    f.detectChanges();
    const c = f.componentInstance;
    c.editingServer()!.securityMode = 3;
    f.detectChanges();
    const btn = Array.from((f.nativeElement as HTMLElement).querySelectorAll('button')).find((b) => b.textContent!.includes('Set up identity')) as HTMLButtonElement;
    btn.click();
    f.detectChanges();
    expect(c.activeTab()).toBe('security');
    expect(c.returnTo()).toBe('s1');
    expect((f.nativeElement as HTMLElement).textContent).toContain('Return to PLC');
  });

  it('clears the last test result when the URL or credentials are edited', async () => {
    const f = create();
    f.detectChanges();
    const c = f.componentInstance;
    c.editingServer()!.securityMode = 3;
    api.test.and.returnValue(of({ url: 'u', connected: true, responseTimeMs: 4, security: { managed: true, identityReady: true, serverTrusted: true } }));
    await c.testServerConnection();
    expect(c.lastTest()).not.toBeNull();
    f.detectChanges();
    const url = (f.nativeElement as HTMLElement).querySelector('input[placeholder="opc.tcp://localhost:4840"]') as HTMLInputElement;
    url.value = 'opc.tcp://other:4840';
    url.dispatchEvent(new Event('input'));
    expect(c.lastTest()).toBeNull();
    await c.testServerConnection();
    expect(c.lastTest()).not.toBeNull();
    c.chooseCredentials('SomeEntry');
    expect(c.lastTest()).toBeNull();
  });

  it('keeps the unsecured success text for mode None', async () => {
    const f = create();
    f.detectChanges();
    const c = f.componentInstance;
    api.test.and.returnValue(of({ url: 'u', connected: true, responseTimeMs: 7 }));
    await c.testServerConnection();
    expect(c.testStatus()).toBe('Connected (7ms)');
    expect(c.lastTest()).toBeNull();
  });
});

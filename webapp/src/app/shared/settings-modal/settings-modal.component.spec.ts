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
});

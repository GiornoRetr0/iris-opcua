import { ComponentFixture, TestBed } from '@angular/core/testing';
import { HttpErrorResponse } from '@angular/common/http';
import { of, throwError } from 'rxjs';
import { ServerSecurityComponent } from './server-security.component';
import { ApiService } from '../../../core/services/api.service';
import { ConnectionTestResult, IdentityStatus, ServerCertificateReview, ServerProfile } from '../../../core/models/opcua.models';

const identity = (over: Partial<IdentityStatus> = {}): IdentityStatus => ({
  configured: true, ready: true, fingerprint: 'AA:BB', errors: [], warnings: [], ...over,
});

const cert = (sha: string, over = {}) => ({
  subject: 'CN=plc', issuer: 'CN=plc', notBefore: '2026-01-01', notAfter: '2030-01-01',
  sha256: sha, sanUris: [], sanDns: [], sanIps: [], selfSigned: true, ...over,
});

const review = (over: Partial<ServerCertificateReview> = {}): ServerCertificateReview => ({
  url: 'opc.tcp://plc:4840', key: 'k', offersSignAndEncrypt: true, policies: [], applicationUri: 'urn:plc',
  certificate: cert('11:22:33:44'), identity: { uriMatches: true, hostMatches: true, problems: [] },
  trusted: false, pinnedFingerprint: '', changed: false, needsIssuer: false, issuerName: '', ...over,
});

const profile = (over: Partial<ServerProfile> = {}): ServerProfile => ({
  id: 's1', name: 'PLC', url: 'opc.tcp://plc:4840', securityMode: 3, credentials: '', ...over,
});

describe('ServerSecurityComponent', () => {
  let api: jasmine.SpyObj<ApiService>;
  let fixture: ComponentFixture<ServerSecurityComponent>;
  const el = () => fixture.nativeElement as HTMLElement;
  const button = (text: string) =>
    Array.from(el().querySelectorAll('button')).find((b) => b.textContent!.includes(text)) as HTMLButtonElement | undefined;

  async function create(opts: { server?: ServerProfile; id?: IdentityStatus; rev?: ServerCertificateReview | HttpErrorResponse; test?: ConnectionTestResult | null } = {}) {
    api = jasmine.createSpyObj('ApiService', ['getIdentity', 'inspectServer', 'trustServer', 'addServerIssuer', 'downloadClientCertificate']);
    api.getIdentity.and.returnValue(of(opts.id ?? identity()));
    const rev = opts.rev ?? review({ trusted: true, pinnedFingerprint: '11:22:33:44' });
    api.inspectServer.and.returnValue(rev instanceof HttpErrorResponse ? throwError(() => rev) : of(rev));
    await TestBed.configureTestingModule({
      imports: [ServerSecurityComponent],
      providers: [{ provide: ApiService, useValue: api }],
    }).compileComponents();
    fixture = TestBed.createComponent(ServerSecurityComponent);
    fixture.componentRef.setInput('server', opts.server ?? profile());
    fixture.componentRef.setInput('testResult', opts.test ?? null);
    fixture.detectChanges();
    await fixture.whenStable();
    fixture.detectChanges();
  }

  it('shows the three readiness rows and no path inputs for a managed profile', async () => {
    await create();
    const t = el().textContent!;
    expect(t).toContain('IRIS client identity');
    expect(t).toContain('Server certificate');
    expect(t).toContain('Server approval of IRIS');
    expect(t).toContain('Checked when you test the connection.');
    expect(t).toContain('Trusted · expires 2030-01-01');
    expect(el().querySelector('input[type=text]')).toBeNull();
    expect(t).not.toContain('Manual certificate files');
  });

  it('keeps the five inputs, untouched, inside Advanced for a manual profile', async () => {
    const server = profile({ certPath: '/c.der', keyPath: '/k.der', trustDir: '/t/', crlDir: '/r/', clientURI: 'urn:x' });
    await create({ server });
    expect(el().textContent).toContain('Manual certificate files');
    const details = el().querySelector('details')!;
    expect(details.textContent).toContain('Advanced');
    const inputs = Array.from(details.querySelectorAll('input')) as HTMLInputElement[];
    await fixture.whenStable();
    expect(inputs.length).toBe(5);
    expect(inputs.map((i) => i.value).sort()).toEqual(['/c.der', '/k.der', '/r/', '/t/', 'urn:x']);
    expect(api.inspectServer).not.toHaveBeenCalled();
    expect(server.certPath).toBe('/c.der');
  });

  it('sends Set up identity to the parent when the identity is missing', async () => {
    await create({ id: identity({ configured: false, ready: false }) });
    let fired = 0;
    fixture.componentInstance.setupIdentity.subscribe(() => fired++);
    expect(el().textContent).toContain('No identity yet');
    button('Set up identity')!.click();
    expect(fired).toBe(1);
  });

  it('flags an expired identity with Set up identity', async () => {
    await create({ id: identity({ ready: false, errors: [{ code: 'expired', message: 'x' }] }) });
    expect(el().textContent).toContain('Expired');
    expect(button('Set up identity')).toBeTruthy();
  });

  it('reviews and trusts a new server certificate', async () => {
    await create({ rev: review() });
    expect(button('Trust this server')).toBeUndefined();
    button('Review certificate')!.click();
    fixture.detectChanges();
    const t = el().textContent!;
    expect(t).toContain('11:22:33:44');
    expect(t).toContain('urn:plc');
    expect(t).toContain("Compare this fingerprint with the one the server's administrator gives you.");
    api.trustServer.and.returnValue(of(review({ trusted: true, pinnedFingerprint: '11:22:33:44' })));
    button('Trust this server')!.click();
    fixture.detectChanges();
    expect(api.trustServer).toHaveBeenCalledWith('opc.tcp://plc:4840', '11:22:33:44', 'PLC');
    expect(el().textContent).toContain('Trusted · expires 2030-01-01');
  });

  it('shows the changed headline with old and new side by side and approves the replacement', async () => {
    await create({ rev: review({ trusted: false, changed: true, pinnedFingerprint: '99:99', previous: cert('99:99') }) });
    expect(el().textContent).toContain('Server certificate changed—review and approve the replacement.');
    button('Review certificate')!.click();
    fixture.detectChanges();
    expect(el().textContent).toContain('99:99');
    expect(el().textContent).toContain('11:22:33:44');
    api.trustServer.and.returnValue(of(review({ trusted: true })));
    button('Approve replacement')!.click();
    expect(api.trustServer).toHaveBeenCalledWith('opc.tcp://plc:4840', '11:22:33:44', 'PLC');
  });

  it('disables Trust and lists identity problems', async () => {
    await create({ rev: review({ identity: { uriMatches: false, hostMatches: true, problems: ['The certificate names a different application URI.'] } }) });
    button('Review certificate')!.click();
    fixture.detectChanges();
    expect(el().textContent).toContain('The certificate names a different application URI.');
    expect(button('Trust this server')!.disabled).toBeTrue();
  });

  it('disables Trust when the server does not offer Sign & Encrypt', async () => {
    await create({ rev: review({ offersSignAndEncrypt: false }) });
    button('Review certificate')!.click();
    fixture.detectChanges();
    expect(el().textContent).toContain('This server does not offer Sign & Encrypt.');
    expect(button('Trust this server')!.disabled).toBeTrue();
  });

  it('asks for the CA and CRL when the server needs an issuer, and sends them as hex', async () => {
    await create({ rev: review({ trusted: true, needsIssuer: true, issuerName: 'CN=Plant CA' }) });
    button('Review certificate')!.click();
    fixture.detectChanges();
    expect(el().textContent).toContain('CN=Plant CA');
    expect(button('Add issuer')!.disabled).toBeTrue();
    const c = fixture.componentInstance;
    await c.pickIssuer('ca', new File([new Uint8Array([1, 2])], 'ca.der'));
    await c.pickIssuer('crl', new File([new Uint8Array([0xab])], 'ca.crl'));
    fixture.detectChanges();
    api.addServerIssuer.and.returnValue(of(review({ trusted: true })));
    button('Add issuer')!.click();
    expect(api.addServerIssuer).toHaveBeenCalledWith('opc.tcp://plc:4840', '0102', 'AB');
  });

  it('shows an inspect failure with the server message', async () => {
    await create({ rev: new HttpErrorResponse({ status: 400, error: { status: 'error', error: 'Could not reach the server' } }) });
    expect(el().textContent).toContain('Could not reach the server');
  });

  it('shows Approved after a successful test', async () => {
    await create({ test: { url: 'u', connected: true, responseTimeMs: 5, security: { managed: true, identityReady: true, serverTrusted: true } } });
    expect(el().textContent).toContain('Approved');
  });

  it('offers the IRIS certificate when the server has not approved it', async () => {
    const test: ConnectionTestResult = {
      url: 'u', connected: false, responseTimeMs: 5,
      security: { managed: true, identityReady: true, serverTrusted: true, diagnosis: { category: 'clientNotApproved', message: 'The OPC UA server has not approved IRIS\'s certificate yet.', clientFingerprint: 'AA:BB:CC' } },
    };
    await create({ test });
    expect(el().textContent).toContain("The OPC UA server has not approved IRIS's certificate yet.");
    expect(el().textContent).toContain('AA:BB:CC');
    expect(button('Download IRIS certificate')).toBeTruthy();
    expect(button('None')).toBeUndefined();
  });

  it('shows another diagnosis without a download button', async () => {
    const test: ConnectionTestResult = {
      url: 'u', connected: false, responseTimeMs: 5,
      security: { managed: true, identityReady: true, serverTrusted: true, diagnosis: { category: 'network', message: 'Could not reach the server.' } },
    };
    await create({ test });
    expect(el().textContent).toContain('Could not reach the server.');
    expect(button('Download IRIS certificate')).toBeUndefined();
  });
});

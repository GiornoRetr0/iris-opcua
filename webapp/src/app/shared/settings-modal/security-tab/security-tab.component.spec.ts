import { ComponentFixture, TestBed } from '@angular/core/testing';
import { HttpErrorResponse } from '@angular/common/http';
import { of, throwError } from 'rxjs';
import { SecurityTabComponent } from './security-tab.component';
import { ApiService } from '../../../core/services/api.service';
import { ConfigService } from '../../../core/services/config.service';
import { IdentityStatus } from '../../../core/models/opcua.models';

const configured = (over: Partial<IdentityStatus> = {}): IdentityStatus => ({
  configured: true,
  ready: true,
  source: 'generated',
  clientURI: 'urn:iris:opcua-client',
  fingerprint: 'AA:BB:CC',
  notBefore: '2026-01-01',
  notAfter: '2027-01-01',
  daysLeft: 200,
  errors: [],
  warnings: [],
  impact: { pipelines: [{ namespace: 'OPCUA', name: 'PLC', url: 'opc.tcp://plc:4840' }], servers: [{ key: 'k', url: 'opc.tcp://x', label: 'X' }] },
  advanced: { certPath: '/c.der', keyPath: '/k.der', storeRoot: '/store' },
  ...over,
});

describe('SecurityTabComponent', () => {
  let api: jasmine.SpyObj<ApiService>;
  let fixture: ComponentFixture<SecurityTabComponent>;
  const el = () => fixture.nativeElement as HTMLElement;

  async function create(status: IdentityStatus | HttpErrorResponse, base = 'http://localhost:52783/csp/opcua/api') {
    api = jasmine.createSpyObj('ApiService', ['getIdentity', 'createIdentity', 'importIdentity', 'useIdentityFiles', 'downloadClientCertificate', 'listTrustedServers', 'removeTrustedServer']);
    api.getIdentity.and.returnValue(status instanceof HttpErrorResponse ? throwError(() => status) : of(status));
    api.listTrustedServers.and.returnValue(of([]));
    api.createIdentity.and.returnValue(of(configured()));
    api.importIdentity.and.returnValue(of(configured()));
    await TestBed.configureTestingModule({
      imports: [SecurityTabComponent],
      providers: [
        { provide: ApiService, useValue: api },
        { provide: ConfigService, useValue: { get: () => ({ apiBaseUrl: base }) } },
      ],
    }).compileComponents();
    fixture = TestBed.createComponent(SecurityTabComponent);
    fixture.detectChanges();
    await fixture.whenStable();
    fixture.detectChanges();
  }
  const button = (text: string) =>
    Array.from(el().querySelectorAll('button')).find((b) => b.textContent!.includes(text)) as HTMLButtonElement | undefined;

  it('offers Create client identity when not configured', async () => {
    await create({ configured: false, ready: false, errors: [], warnings: [] });
    expect(button('Create client identity')).toBeTruthy();
    expect(el().textContent).toContain('Use existing certificate');
  });

  it('explains a 403', async () => {
    await create(new HttpErrorResponse({ status: 403, error: { status: 'error', error: 'x' } }));
    expect(el().textContent).toContain('Managing OPC UA certificates needs a SuperUser account.');
  });

  it('shows Expired when errors contain expired', async () => {
    await create(configured({ ready: false, errors: [{ code: 'expired', message: 'Certificate expired' }] }));
    expect(el().textContent).toContain('Expired');
  });

  it('shows Ready and the fingerprint when configured', async () => {
    await create(configured());
    expect(el().textContent).toContain('Default IRIS client');
    expect(el().textContent).toContain('Ready');
    expect(el().textContent).toContain('AA:BB:CC');
  });

  it('shows days left when close to expiry', async () => {
    await create(configured({ daysLeft: 12 }));
    expect(el().textContent).toContain('Expires in 12 days');
  });

  it('Replace lists the impact and posts replace with the current fingerprint', async () => {
    await create(configured());
    button('Replace')!.click();
    fixture.detectChanges();
    const dialog = el().querySelector('app-confirm-dialog')!;
    expect(dialog.textContent).toContain('OPCUA · PLC · opc.tcp://plc:4840');
    expect(dialog.textContent).toContain('Each of these servers must approve the new certificate before these connections work again.');
    (Array.from(dialog.querySelectorAll('button')).find((b) => b.textContent!.includes('Replace')) as HTMLButtonElement).click();
    expect(api.createIdentity).toHaveBeenCalledWith(jasmine.objectContaining({ replace: true, currentFingerprint: 'AA:BB:CC' }));
  });

  it('warns about sending a key over plain http to a remote host', async () => {
    await create({ configured: false, ready: false, errors: [], warnings: [] }, 'http://iris.example.com/csp/opcua/api');
    button('Use existing certificate')!.click();
    fixture.detectChanges();
    expect(el().textContent).toContain('This sends the private key over an unencrypted connection.');
  });

  it('does not warn on localhost', async () => {
    await create({ configured: false, ready: false, errors: [], warnings: [] });
    button('Use existing certificate')!.click();
    fixture.detectChanges();
    expect(el().textContent).not.toContain('This sends the private key');
  });

  it('clears the file inputs and keeps key material out of the DOM after import', async () => {
    await create({ configured: false, ready: false, errors: [], warnings: [] });
    button('Use existing certificate')!.click();
    fixture.detectChanges();
    expect(el().querySelectorAll('input[type=file]').length).toBe(3);
    const cert = new File([new Uint8Array([1, 2])], 'c.der');
    const key = new File([new Uint8Array([0xab, 0xcd])], 'k.der');
    await fixture.componentInstance.pickFile('cert', cert);
    await fixture.componentInstance.pickFile('key', key);
    await fixture.componentInstance.importPair();
    fixture.detectChanges();
    expect(api.importIdentity).toHaveBeenCalledWith(jasmine.objectContaining({ certificate: '0102', key: 'ABCD' }));
    expect(el().innerHTML).not.toContain('ABCD');
    for (const i of Array.from(el().querySelectorAll('input[type=file]')) as HTMLInputElement[]) {
      expect(i.value).toBe('');
    }
    expect(fixture.componentInstance.hasPickedFiles()).toBeFalse();
  });
});

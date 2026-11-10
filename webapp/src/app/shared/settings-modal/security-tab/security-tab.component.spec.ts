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
    api.useIdentityFiles.and.returnValue(of(configured()));
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

  const openReplace = () => {
    button('Replace…')!.click();
    fixture.detectChanges();
  };
  const confirmDialog = () => {
    const dialog = el().querySelector('app-confirm-dialog')!;
    (Array.from(dialog.querySelectorAll('button')).find((b) => b.textContent!.trim() === 'Replace') as HTMLButtonElement).click();
  };

  it('Replace offers the routes, lists the impact and posts replace with the current fingerprint and URI', async () => {
    await create(configured());
    openReplace();
    expect(el().querySelector('app-confirm-dialog')).toBeNull();
    button('Create new certificate')!.click();
    fixture.detectChanges();
    const dialog = el().querySelector('app-confirm-dialog')!;
    const detail = dialog.querySelector('p')!;
    // The detail is one string with line breaks; the dialog must render them.
    expect(detail.classList).toContain('whitespace-pre-line');
    expect(detail.textContent!.split('\n')).toContain('OPCUA · PLC · opc.tcp://plc:4840');
    expect(detail.textContent).toContain('Each of these servers must approve the new certificate before these connections work again.');
    confirmDialog();
    expect(api.createIdentity).toHaveBeenCalledWith({ clientURI: 'urn:iris:opcua-client', replace: true, currentFingerprint: 'AA:BB:CC' });
  });

  it('a Client URI edited under Advanced wins on replace', async () => {
    await create(configured());
    openReplace();
    fixture.componentInstance.clientURI.set('urn:new');
    button('Create new certificate')!.click();
    fixture.detectChanges();
    confirmDialog();
    expect(api.createIdentity).toHaveBeenCalledWith(jasmine.objectContaining({ clientURI: 'urn:new', replace: true }));
  });

  it('replaces with files already on IRIS behind the same confirmation', async () => {
    await create(configured());
    openReplace();
    fixture.componentInstance.certPath.set('/a.der');
    fixture.componentInstance.keyPath.set('/a.key');
    api.useIdentityFiles.and.returnValue(of(configured()));
    fixture.componentInstance.useFiles();
    fixture.detectChanges();
    expect(api.useIdentityFiles).not.toHaveBeenCalled();
    confirmDialog();
    expect(api.useIdentityFiles).toHaveBeenCalledWith({ certPath: '/a.der', keyPath: '/a.key', replace: true, currentFingerprint: 'AA:BB:CC' });
  });

  it('replaces with an uploaded pair behind the same confirmation, then holds nothing', async () => {
    await create(configured());
    openReplace();
    button('Use existing certificate')!.click();
    fixture.detectChanges();
    const c = fixture.componentInstance;
    await c.onFile('cert', { target: { files: [new File([new Uint8Array([1, 2])], 'c.der')] } } as unknown as Event);
    await c.onFile('key', { target: { files: [new File([new Uint8Array([0xab, 0xcd])], 'k.der')] } } as unknown as Event);
    c.submitImport();
    fixture.detectChanges();
    expect(api.importIdentity).not.toHaveBeenCalled();
    confirmDialog();
    expect(api.importIdentity).toHaveBeenCalledWith({ certificate: '0102', key: 'ABCD', replace: true, currentFingerprint: 'AA:BB:CC' });
    expect(c.heldUpload()).toBe('');
  });

  it('on a 409 reloads the identity so the next confirmation uses the new fingerprint', async () => {
    await create(configured());
    api.createIdentity.and.returnValues(
      throwError(() => new HttpErrorResponse({ status: 409, error: { status: 'error', error: 'The identity changed' } })),
      of(configured())
    );
    api.getIdentity.and.returnValue(of(configured({ fingerprint: 'DD:EE', impact: { pipelines: [], servers: [{ key: 'z', url: 'opc.tcp://z', label: 'Z' }] } })));
    openReplace();
    button('Create new certificate')!.click();
    fixture.detectChanges();
    confirmDialog();
    fixture.detectChanges();
    expect(el().textContent).toContain('The identity changed');
    expect(api.getIdentity).toHaveBeenCalledTimes(2);
    expect(el().querySelector('app-confirm-dialog')).toBeNull();
    openReplace();
    button('Create new certificate')!.click();
    fixture.detectChanges();
    expect(el().querySelector('app-confirm-dialog')!.textContent).toContain('Z · opc.tcp://z');
    confirmDialog();
    expect(api.createIdentity.calls.mostRecent().args[0]).toEqual(jasmine.objectContaining({ currentFingerprint: 'DD:EE' }));
  });

  it('offers Use it only for a ready candidate', async () => {
    const cand = { certPath: '/c', keyPath: '/k', clientURI: 'urn:old', fingerprint: 'F', notAfter: '2020-01-01', ready: false };
    await create({ configured: false, ready: false, errors: [], warnings: [], candidates: [cand] });
    expect(el().textContent).toContain('urn:old');
    expect(button('Use it')).toBeUndefined();
  });

  it('offers Use it for a ready candidate', async () => {
    const cand = { certPath: '/c', keyPath: '/k', clientURI: 'urn:ok', fingerprint: 'F', notAfter: '2030-01-01', ready: true };
    await create({ configured: false, ready: false, errors: [], warnings: [], candidates: [cand] });
    button('Use it')!.click();
    expect(api.useIdentityFiles).toHaveBeenCalledWith({ certPath: '/c', keyPath: '/k' });
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

  async function pickPair(c: SecurityTabComponent) {
    await c.onFile('cert', { target: { files: [new File([new Uint8Array([1, 2])], 'c.der')] } } as unknown as Event);
    await c.onFile('key', { target: { files: [new File([new Uint8Array([0xab, 0xcd])], 'k.der')] } } as unknown as Event);
  }

  it('holds the key only until the request is sent, and the DOM never shows it', async () => {
    await create({ configured: false, ready: false, errors: [], warnings: [] });
    button('Use existing certificate')!.click();
    fixture.detectChanges();
    const c = fixture.componentInstance;
    await pickPair(c);
    expect(c.heldUpload()).toContain('ABCD');
    c.submitImport();
    fixture.detectChanges();
    expect(api.importIdentity).toHaveBeenCalledWith(jasmine.objectContaining({ certificate: '0102', key: 'ABCD' }));
    expect(c.heldUpload()).toBe('');
    expect(el().innerHTML).not.toContain('ABCD');
    for (const i of Array.from(el().querySelectorAll('input[type=file]')) as HTMLInputElement[]) expect(i.value).toBe('');
    expect(JSON.stringify(c.status())).not.toContain('ABCD');
  });

  it('scrubs the key and password when the import fails', async () => {
    await create({ configured: false, ready: false, errors: [], warnings: [] });
    api.importIdentity.and.returnValue(throwError(() => new HttpErrorResponse({ status: 400, error: { status: 'error', error: 'Key does not match' } })));
    button('Use existing certificate')!.click();
    fixture.detectChanges();
    const c = fixture.componentInstance;
    await pickPair(c);
    c.pfxPassword.set('s3cret');
    c.submitImport();
    fixture.detectChanges();
    expect(el().textContent).toContain('Key does not match');
    expect(c.heldUpload()).toBe('');
    expect(el().innerHTML).not.toContain('s3cret');
  });
});

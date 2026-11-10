import { TestBed } from '@angular/core/testing';
import { HttpClient, provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { firstValueFrom } from 'rxjs';
import { AuthService } from './auth.service';
import { authInterceptor } from './auth.interceptor';
import { ConfigService } from './config.service';

/**
 * The IRIS sign-in: the password is used once and never stored; the session is a
 * JWT pair in sessionStorage, refreshed one at a time; an API without JWT falls
 * back to Basic held in memory only.
 */
describe('AuthService and authInterceptor', () => {
  let http: HttpTestingController;
  let client: HttpClient;
  let auth: AuthService;
  const KEY = 'opcua-console::session::/api';
  const flush = () => new Promise((r) => setTimeout(r));

  function setup(hosted = true): void {
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(withInterceptors([authInterceptor])),
        provideHttpClientTesting(),
        { provide: ConfigService, useValue: { hosted, get: () => ({ apiBaseUrl: '/api' }), save: () => {} } },
      ],
    });
    http = TestBed.inject(HttpTestingController);
    client = TestBed.inject(HttpClient);
    auth = TestBed.inject(AuthService);
  }

  /** A token response living `seconds`. */
  const tokens = (n: number, seconds = 60) => ({ access_token: `a${n}`, refresh_token: `r${n}`, iat: 1000, exp: 1000 + seconds });

  async function signInWithJwt(seconds = 60): Promise<void> {
    const p = auth.signIn('opc', 'pw-secret');
    await flush();
    const login = http.expectOne('/api/login');
    expect(login.request.body).toEqual({ user: 'opc', password: 'pw-secret' });
    login.flush(tokens(1, seconds));
    await p;
  }

  /** Issue an API call and return its request once the interceptor has sent it. */
  async function call(url = '/api/pipelines') {
    const result = firstValueFrom(client.get(url));
    await flush();
    return { result, req: () => http.expectOne(url) };
  }

  beforeEach(() => sessionStorage.removeItem(KEY));
  afterEach(() => {
    http.verify();
    sessionStorage.removeItem(KEY);
  });

  it('signs in with JWT: Bearer on API calls, tokens in sessionStorage, never the password', async () => {
    setup();
    await signInWithJwt();
    expect(auth.user()).toBe('opc');
    const stored = sessionStorage.getItem(KEY)!;
    expect(stored).toContain('a1');
    expect(stored).not.toContain('pw-secret');

    const c = await call();
    const req = c.req();
    expect(req.request.headers.get('Authorization')).toBe('Bearer a1');
    req.flush({});
    await c.result;
  });

  it('leaves other URLs alone', async () => {
    setup();
    await signInWithJwt();
    const p = firstValueFrom(client.get('/elsewhere'));
    await flush();
    const req = http.expectOne('/elsewhere');
    expect(req.request.headers.has('Authorization')).toBeFalse();
    req.flush({});
    await p;
  });

  it('falls back to Basic in memory when the API has no JWT', async () => {
    setup();
    const p = auth.signIn('opc', 'pw-secret');
    await flush();
    http.expectOne('/api/login').flush('Not Found', { status: 404, statusText: 'Not Found' });
    await flush();
    const ping = http.expectOne('/api/ping');
    expect(ping.request.headers.get('Authorization')).toBe('Basic ' + btoa('opc:pw-secret'));
    ping.flush({ status: 'ok' });
    await p;
    expect(auth.user()).toBe('opc');
    expect(sessionStorage.getItem(KEY)).toBeNull();

    const c = await call();
    const req = c.req();
    expect(req.request.headers.get('Authorization')).toBe('Basic ' + btoa('opc:pw-secret'));
    req.flush({});
    await c.result;
  });

  it('rejects a wrong password and stays signed out', async () => {
    setup();
    const p = auth.signIn('opc', 'wrong');
    await flush();
    http.expectOne('/api/login').flush('Not Found', { status: 404, statusText: 'Not Found' });
    await flush();
    http.expectOne('/api/ping').flush('Not Found', { status: 404, statusText: 'Not Found' });
    await expectAsync(p).toBeRejectedWithError(/did not accept/);
    expect(auth.user()).toBeNull();
  });

  it('refreshes before expiry, once for concurrent calls, and rotates the refresh token', async () => {
    setup();
    await signInWithJwt(10); // inside the refresh margin at once
    const one = firstValueFrom(client.get('/api/one'));
    const two = firstValueFrom(client.get('/api/two'));
    await flush();
    const refresh = http.expectOne('/api/refresh');
    expect(refresh.request.body).toEqual({ grant_type: 'refresh_token', refresh_token: 'r1' });
    refresh.flush(tokens(2));
    await flush();
    for (const url of ['/api/one', '/api/two']) {
      const req = http.expectOne(url);
      expect(req.request.headers.get('Authorization')).toBe('Bearer a2');
      req.flush({});
    }
    await Promise.all([one, two]);
    expect(sessionStorage.getItem(KEY)).toContain('r2');
  });

  it('on a refused token, refreshes once and repeats the call', async () => {
    setup();
    await signInWithJwt();
    const c = await call();
    c.req().flush('Not Found', { status: 404, statusText: 'Not Found' });
    await flush();
    http.expectOne('/api/refresh').flush(tokens(2));
    await flush();
    const retry = http.expectOne('/api/pipelines');
    expect(retry.request.headers.get('Authorization')).toBe('Bearer a2');
    retry.flush({ ok: 1 });
    expect(await c.result).toEqual({ ok: 1 });
  });

  it('ends the session when the refresh is refused, and the call fails', async () => {
    setup();
    await signInWithJwt();
    const c = await call();
    c.req().flush('Not Found', { status: 404, statusText: 'Not Found' });
    await flush();
    http.expectOne('/api/refresh').flush('Not Found', { status: 404, statusText: 'Not Found' });
    await expectAsync(c.result).toBeRejected();
    expect(auth.user()).toBeNull();
    expect(sessionStorage.getItem(KEY)).toBeNull();
  });

  it('signs out by revoking the token', async () => {
    setup();
    await signInWithJwt();
    const p = auth.signOut();
    const logout = http.expectOne('/api/logout');
    expect(logout.request.headers.get('Authorization')).toBe('Bearer a1');
    logout.flush('');
    await p;
    expect(auth.user()).toBeNull();
    expect(sessionStorage.getItem(KEY)).toBeNull();
  });

  it('restores the session from sessionStorage in a new instance', async () => {
    sessionStorage.setItem(KEY, JSON.stringify({ mode: 'bearer', username: 'opc', access: 'a9', refresh: 'r9', expiresAt: Date.now() + 60_000 }));
    setup();
    expect(auth.user()).toBe('opc');
    const c = await call();
    const req = c.req();
    expect(req.request.headers.get('Authorization')).toBe('Bearer a9');
    req.flush({});
    await c.result;
  });

  it('the development server signs in on its own', async () => {
    setup(false);
    await flush();
    http.expectOne('/api/login').flush(tokens(1));
    await auth.ready;
    expect(auth.user()).toBe('SuperUser');
  });
});

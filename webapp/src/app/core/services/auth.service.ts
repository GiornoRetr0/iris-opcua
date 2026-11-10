import { Injectable, inject, signal } from '@angular/core';
import { HttpClient, HttpContext, HttpContextToken, HttpHeaders } from '@angular/common/http';
import { firstValueFrom, timeout } from 'rxjs';
import { ConfigService } from './config.service';

/**
 * Set on the requests AuthService makes itself (/login, /refresh, /logout, the
 * Basic probe), so the interceptor neither adds a login to them nor retries them.
 */
export const AUTH_REQUEST = new HttpContextToken<boolean>(() => false);

/**
 * The console's IRIS sign-in. The password is used once, to sign in, and never
 * stored.
 *
 * With JWT authentication on the REST application (the installer and the Docker
 * demo switch it on), `POST /login` returns an access token and a refresh token.
 * They are kept in sessionStorage, so they last for this browser tab and end with
 * it; the access token is refreshed shortly before it expires. IRIS rotates the
 * refresh token on every refresh and, if an old one is replayed, revokes the whole
 * chain, so there is never more than one refresh in flight.
 *
 * An application without JWT answers /login with 404. Then the console keeps a
 * Basic login in memory only: it works until the page is reloaded.
 */
interface BearerSession {
  mode: 'bearer';
  username: string;
  access: string;
  refresh: string;
  /** Local clock, ms. Computed from the token's lifetime, so server clock skew does not matter. */
  expiresAt: number;
}

interface BasicSession {
  mode: 'basic';
  username: string;
  header: string;
}

type Session = BearerSession | BasicSession;

interface TokenResponse {
  access_token: string;
  refresh_token: string;
  iat: number;
  exp: number;
}

/** Refresh this long before the access token expires. */
const REFRESH_MARGIN_MS = 15_000;

/** The account the development server signs in with on its own (`ng serve` only). */
const DEV_LOGIN = { username: 'SuperUser', password: 'SYS' };

@Injectable({ providedIn: 'root' })
export class AuthService {
  private http = inject(HttpClient);
  private config = inject(ConfigService);

  private session: Session | null = null;
  private refreshing: Promise<boolean> | null = null;

  /** Who is signed in, or null. */
  readonly user = signal<string | null>(null);

  /** Resolves once a stored session is restored, or the development login tried. */
  readonly ready: Promise<void>;

  constructor() {
    this.session = this.restore();
    this.user.set(this.session?.username ?? null);
    this.ready = this.session || this.config.hosted
      ? Promise.resolve()
      : this.signIn(DEV_LOGIN.username, DEV_LOGIN.password).catch(() => undefined);
  }

  private get base(): string {
    return this.config.get().apiBaseUrl.replace(/\/+$/, '');
  }

  /** sessionStorage key: per API path, so two namespaces' consoles on one origin stay apart. */
  private get storageKey(): string {
    return `opcua-console::session::${this.base}`;
  }

  /** Whether `url` is a call to the IRIS API this console signs in to. */
  isApiUrl(url: string): boolean {
    return url === this.base || url.startsWith(this.base + '/');
  }

  /**
   * Sign in. Rejects with an Error whose message says why. Replaces any current
   * session, signing it out first.
   */
  async signIn(username: string, password: string): Promise<void> {
    await this.signOut();
    try {
      const t = await firstValueFrom(
        this.http
          .post<TokenResponse>(`${this.base}/login`, { user: username, password }, { context: authContext() })
          .pipe(timeout(15000))
      );
      this.setSession(bearer(username, t));
      return;
    } catch {
      // A wrong password and an application without JWT both answer 404: ask with
      // Basic to tell them apart.
    }
    const header = 'Basic ' + btoa(username + ':' + password);
    try {
      await firstValueFrom(
        this.http
          .get(`${this.base}/ping`, { context: authContext(), headers: new HttpHeaders({ Authorization: header }) })
          .pipe(timeout(15000))
      );
    } catch {
      throw new Error('IRIS did not accept this username and password.');
    }
    this.setSession({ mode: 'basic', username, header });
  }

  /** Sign out: revoke the tokens (best effort) and forget the session. */
  async signOut(): Promise<void> {
    const s = this.session;
    this.setSession(null);
    if (s?.mode !== 'bearer') return;
    try {
      await firstValueFrom(
        this.http
          .post(`${this.base}/logout`, {}, {
            context: authContext(),
            headers: new HttpHeaders({ Authorization: `Bearer ${s.access}` }),
            responseType: 'text',
          })
          .pipe(timeout(5000))
      );
    } catch {
      // The tokens expire on their own.
    }
  }

  /** The Authorization header for the next API call, refreshing first if due; null when signed out. */
  async authorization(): Promise<string | null> {
    await this.ready;
    let s = this.session;
    if (s?.mode === 'bearer' && s.expiresAt - Date.now() < REFRESH_MARGIN_MS) {
      await this.refresh();
      s = this.session;
    }
    if (!s) return null;
    return s.mode === 'bearer' ? `Bearer ${s.access}` : s.header;
  }

  /**
   * Swap the refresh token for new tokens. One at a time: concurrent callers share
   * the refresh in flight. On failure the session ends. Returns whether it worked.
   */
  refresh(): Promise<boolean> {
    if (!this.refreshing) {
      this.refreshing = this.doRefresh().finally(() => (this.refreshing = null));
    }
    return this.refreshing;
  }

  private async doRefresh(): Promise<boolean> {
    const s = this.session;
    if (s?.mode !== 'bearer') return false;
    try {
      const t = await firstValueFrom(
        this.http
          .post<TokenResponse>(`${this.base}/refresh`, { grant_type: 'refresh_token', refresh_token: s.refresh }, { context: authContext() })
          .pipe(timeout(15000))
      );
      // Signed out or in as someone else meanwhile: keep what is there now.
      if (this.session === s) this.setSession(bearer(s.username, t));
      return true;
    } catch {
      if (this.session === s) this.setSession(null);
      return false;
    }
  }

  private setSession(s: Session | null): void {
    this.session = s;
    this.user.set(s?.username ?? null);
    try {
      // Only tokens are stored, never a Basic login, which carries the password.
      if (s?.mode === 'bearer') sessionStorage.setItem(this.storageKey, JSON.stringify(s));
      else sessionStorage.removeItem(this.storageKey);
    } catch {
      // storage unavailable: the session lasts until reload
    }
    if (s) this.config.save({ apiUsername: s.username });
  }

  private restore(): Session | null {
    try {
      const raw = sessionStorage.getItem(this.storageKey);
      const s = raw ? (JSON.parse(raw) as BearerSession) : null;
      return s?.mode === 'bearer' && s.access && s.refresh ? s : null;
    } catch {
      return null;
    }
  }
}

function authContext(): HttpContext {
  return new HttpContext().set(AUTH_REQUEST, true);
}

function bearer(username: string, t: TokenResponse): BearerSession {
  const lifetimeMs = Math.max(0, (t.exp - t.iat) * 1000);
  return { mode: 'bearer', username, access: t.access_token, refresh: t.refresh_token, expiresAt: Date.now() + lifetimeMs };
}

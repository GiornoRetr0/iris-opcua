import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpErrorResponse, HttpHeaders } from '@angular/common/http';
import { Observable, map, timeout, catchError, throwError, from } from 'rxjs';
import { ConfigService } from './config.service';
import { AuthService } from './auth.service';
import {
  OpcuaNode,
  NodeReadResult,
  ConnectionTestResult,
  Pipeline,
  DeployResult,
  ServerProfile,
  Schema,
  CreateSchemaRequest,
  CreateSchemaResult,
  SchemaValidation,
  CredentialsEntry,
  isManaged,
  IdentityStatus,
  CreateIdentityRequest,
  ImportIdentityRequest,
  UseIdentityFilesRequest,
  ServerCertificateReview,
  TrustedServer,
} from '../models/opcua.models';

interface ApiEnvelope<T> {
  status: 'ok' | 'error';
  data?: T;
  error?: string;
}

/** What the console shows when IRIS refuses the API account (HTTP 401). */
export const SIGN_IN_FAILED = 'Sign-in failed';

/** Settings' notice when a call needs a sign-in and there is none (never was, or it ended). */
export const NOT_SIGNED_IN = 'Not signed in';

/** The message of our {"status":"error","error":"…"} envelope, if the body is one. */
function envelopeError(err: HttpErrorResponse): string {
  const body = err.error as Partial<ApiEnvelope<unknown>> | null;
  if (body && typeof body === 'object' && body.status === 'error' && typeof body.error === 'string') {
    return body.error;
  }
  return '';
}

/**
 * Whether IRIS refused the API account. Our own Login answers 401, but under the
 * default security setup it never runs: CSP calls it as CSPSystem, which cannot
 * read the code database, so IRIS itself answers a bare text/html 404 (audit #16).
 * A real 404 from our API always carries the envelope (e.g. GET /schemas/NoSuch),
 * so a 404 without one is the failed sign-in.
 */
export function isSignInFailure(err: unknown): boolean {
  if (!(err instanceof HttpErrorResponse)) return false;
  if (err.status === 401) return true;
  return err.status === 404 && !envelopeError(err);
}

/**
 * The message to show for a failed API call, whatever its HTTP status.
 *
 * The API answers errors with a real status (400, 401, 403, 404, 409, 500) and the
 * envelope {"status":"error","error":"…"}; a 500 says only "Internal error.
 * Reference …", the detail being in the Interoperability event log (source
 * OPCUA.REST.Handler), not the application error log. Angular
 * puts that envelope in HttpErrorResponse.error. Its own `message` ("Http failure
 * response for …") is never shown.
 */
export function apiErrorMessage(err: unknown, fallback = 'Request failed'): string {
  if (err instanceof HttpErrorResponse) {
    const body = envelopeError(err);
    if (body) return body;
    if (isSignInFailure(err)) return SIGN_IN_FAILED;
    if (err.status === 0) return 'Cannot reach the IRIS API';
    return `${fallback} (HTTP ${err.status})`;
  }
  if (err instanceof Error && err.message) return err.message;
  return fallback;
}

/** A username and password sent with one request, never stored. */
export interface InlineLogin {
  username: string;
  password: string;
}

function unwrap<T>(res: ApiEnvelope<T>): T {
  if (res.status === 'error') throw new Error(res.error || 'Unknown API error');
  return res.data as T;
}

@Injectable({ providedIn: 'root' })
export class ApiService {
  private http = inject(HttpClient);
  private configService = inject(ConfigService);
  private auth = inject(AuthService);

  private get baseUrl(): string {
    return this.configService.get().apiBaseUrl.replace(/\/+$/, '');
  }

  /** The sign-in is added by authInterceptor. */
  private get headers(): HttpHeaders {
    return new HttpHeaders({ 'Content-Type': 'application/json' });
  }

  /**
   * Common error path for every call. A failed sign-in (see isSignInFailure) means
   * there is no IRIS session (never signed in, or it ended and could not be
   * refreshed) or IRIS refused it, so Settings opens on the sign-in tab with the
   * reason. The error still reaches the caller, which shows apiErrorMessage(err).
   */
  private fail(err: any): Observable<never> {
    if (err?.name === 'TimeoutError') {
      return throwError(() => new Error('Request timed out'));
    }
    if (isSignInFailure(err)) {
      const notice = this.auth.user() ? SIGN_IN_FAILED : NOT_SIGNED_IN;
      document.dispatchEvent(new CustomEvent('open-settings', { detail: { tab: 'gateway', notice } }));
    }
    return throwError(() => err);
  }

  /**
   * Build request body with connection params from a specific server profile.
   * The session's login is the server's `credentials` ID, which the API resolves on
   * the server. `login` replaces it for one request: the Test Connection of a
   * username and password not saved yet.
   */
  private buildBody(params: Record<string, any> = {}, server?: ServerProfile, login?: InlineLogin): Record<string, any> {
    if (server) {
      const body: Record<string, any> = {
        url: server.url,
        securityMode: server.securityMode,
        ...params,
      };
      if (login) {
        body['username'] = login.username;
        body['password'] = login.password;
      } else if (server.credentials) {
        body['credentials'] = server.credentials;
      }
      // A managed Sign & Encrypt profile sends no certificate fields: IRIS supplies
      // its own identity and trust store.
      if (!isManaged(server)) {
        if (server.certPath) body['certPath'] = server.certPath;
        if (server.keyPath) body['keyPath'] = server.keyPath;
        if (server.trustDir) body['trustDir'] = server.trustDir;
        if (server.crlDir) body['crlDir'] = server.crlDir;
        if (server.clientURI) body['clientURI'] = server.clientURI;
      }
      return body;
    }

    // Legacy fallback: use flat config fields
    const cfg = this.configService.get();
    const body: Record<string, any> = {
      url: cfg.serverUrl,
      securityMode: cfg.securityMode,
      ...params,
    };
    if (cfg.certPath) body['certPath'] = cfg.certPath;
    if (cfg.keyPath) body['keyPath'] = cfg.keyPath;
    if (cfg.trustDir) body['trustDir'] = cfg.trustDir;
    if (cfg.crlDir) body['crlDir'] = cfg.crlDir;
    if (cfg.clientURI) body['clientURI'] = cfg.clientURI;
    return body;
  }

  private post<T>(endpoint: string, params: Record<string, any> = {}, timeoutMs = 15000, server?: ServerProfile): Observable<T> {
    return this.postBody<T>(endpoint, this.buildBody(params, server), timeoutMs);
  }

  /**
   * POST for managing an existing pipeline: sends only `params`, never the
   * connection fields. The server reads a pipeline's endpoint and credentials
   * from the pipeline itself (its password sits in an IRIS credentials entry,
   * audit #15).
   */
  private postPlain<T>(endpoint: string, params: Record<string, any>, timeoutMs = 15000): Observable<T> {
    return this.postBody<T>(endpoint, params, timeoutMs);
  }

  private postBody<T>(endpoint: string, body: Record<string, any>, timeoutMs: number): Observable<T> {
    return this.http
      .post<ApiEnvelope<T>>(`${this.baseUrl}${endpoint}`, body, {
        headers: this.headers,
      })
      .pipe(
        timeout(timeoutMs),
        map((res) => {
          if (res.status === 'error') throw new Error(res.error || 'Unknown API error');
          return res.data as T;
        }),
        catchError((err) => this.fail(err))
      );
  }

  ping(): Observable<{ timestamp: string; version: string }> {
    return this.http
      .get<ApiEnvelope<{ timestamp: string; version: string }>>(`${this.baseUrl}/ping`, {
        headers: this.headers,
      })
      .pipe(
        timeout(5000),
        map((res) => {
          if (res.status === 'error') throw new Error(res.error);
          return res.data!;
        }),
        catchError((err) => this.fail(err))
      );
  }

  browse(nodeNs?: number, nodeId?: string | number, nodeIdType?: number, server?: ServerProfile): Observable<OpcuaNode[]> {
    const params: Record<string, any> = {};
    if (nodeNs != null) params['nodeNs'] = nodeNs;
    if (nodeId != null) params['nodeId'] = String(nodeId);
    if (nodeIdType != null) params['nodeIdType'] = nodeIdType;
    return this.post<OpcuaNode[]>('/browse', params, 15000, server);
  }

  read(nodeNs: number, nodeId: string | number, nodeIdType: number, server?: ServerProfile): Observable<NodeReadResult> {
    return this.post<NodeReadResult>('/read', {
      nodeNs,
      nodeId: String(nodeId),
      nodeIdType,
    }, 15000, server);
  }

  test(server?: ServerProfile, login?: InlineLogin): Observable<ConnectionTestResult> {
    return this.postBody<ConnectionTestResult>('/test', this.buildBody({}, server, login), 15000);
  }

  // ── IRIS credentials entries: where OPC UA usernames and passwords live ──

  /** Every entry's ID, username and users. Never a password. */
  listCredentials(): Observable<CredentialsEntry[]> {
    return this.request<CredentialsEntry[]>('get', '/credentials');
  }

  /** Create an entry. 409 if the ID is taken. */
  createCredentials(id: string, username: string, password: string): Observable<{ id: string; username: string }> {
    return this.http
      .post<ApiEnvelope<{ id: string; username: string }>>(`${this.baseUrl}/credentials`, { id, username, password }, { headers: this.headers })
      .pipe(timeout(15000), map(unwrap), catchError((err) => this.fail(err)));
  }

  /** Change an entry. An empty password keeps the stored one. */
  updateCredentials(id: string, username: string, password: string): Observable<{ id: string; username: string }> {
    const body: Record<string, string> = { username };
    if (password) body['password'] = password;
    return this.http
      .put<ApiEnvelope<{ id: string; username: string }>>(`${this.baseUrl}/credentials/${encodeURIComponent(id)}`, body, { headers: this.headers })
      .pipe(timeout(15000), map(unwrap), catchError((err) => this.fail(err)));
  }

  // ── Managed Sign & Encrypt: the IRIS client identity and trusted servers ──

  private securityBody<T>(method: 'post' | 'delete', endpoint: string, body?: unknown, timeoutMs = 30000): Observable<T> {
    return this.http
      .request<ApiEnvelope<T>>(method, `${this.baseUrl}${endpoint}`, { headers: this.headers, body })
      .pipe(timeout(timeoutMs), map(unwrap), catchError((err) => this.fail(err)));
  }

  getIdentity(): Observable<IdentityStatus> {
    return this.request<IdentityStatus>('get', '/security/identity');
  }

  createIdentity(body: CreateIdentityRequest): Observable<IdentityStatus> {
    return this.securityBody<IdentityStatus>('post', '/security/identity', body);
  }

  importIdentity(body: ImportIdentityRequest): Observable<IdentityStatus> {
    return this.securityBody<IdentityStatus>('post', '/security/identity/import', body);
  }

  useIdentityFiles(body: UseIdentityFilesRequest): Observable<IdentityStatus> {
    return this.securityBody<IdentityStatus>('post', '/security/identity/files', body);
  }

  /** The public client certificate, as a file. A blob request, so the JWT interceptor applies. */
  downloadClientCertificate(format: 'der' | 'pem'): Observable<Blob> {
    return this.http
      .get(`${this.baseUrl}/security/identity/certificate`, { params: { format }, responseType: 'blob' })
      .pipe(
        timeout(15000),
        // A blob request leaves an error body as a Blob: read it back into the usual
        // envelope so apiErrorMessage shows the server's own message.
        catchError((err) => from(this.readBlobError(err))),
        catchError((err) => this.fail(err))
      );
  }

  private async readBlobError(err: any): Promise<never> {
    if (err instanceof HttpErrorResponse && err.error instanceof Blob) {
      let body: unknown = null;
      try {
        const text = await err.error.text();
        try { body = JSON.parse(text); } catch { body = text; }
      } catch { /* unreadable body: keep none */ }
      throw new HttpErrorResponse({ status: err.status, statusText: err.statusText, url: err.url ?? undefined, headers: err.headers, error: body });
    }
    throw err;
  }

  listTrustedServers(): Observable<TrustedServer[]> {
    return this.request<TrustedServer[]>('get', '/security/servers');
  }

  inspectServer(url: string): Observable<ServerCertificateReview> {
    return this.securityBody<ServerCertificateReview>('post', '/security/servers/inspect', { url });
  }

  trustServer(url: string, fingerprint: string, label?: string): Observable<ServerCertificateReview> {
    const body: Record<string, string> = { url, fingerprint };
    if (label) body['label'] = label;
    return this.securityBody<ServerCertificateReview>('post', '/security/servers/trust', body);
  }

  /** Hex (uppercase) CA certificate and revocation list for a CA-signed server. */
  addServerIssuer(url: string, caCertificate: string, crl: string): Observable<ServerCertificateReview> {
    return this.securityBody<ServerCertificateReview>('post', '/security/servers/issuer', { url, caCertificate, crl });
  }

  removeTrustedServer(key: string): Observable<unknown> {
    return this.securityBody<unknown>('delete', `/security/servers/${encodeURIComponent(key)}`);
  }

  deploy(params: Record<string, any>, server?: ServerProfile): Observable<DeployResult> {
    return this.post<DeployResult>('/deploy', params, 60000, server);
  }

  listPipelines(): Observable<Pipeline[]> {
    return this.postPlain<Pipeline[]>('/pipelines', {});
  }

  togglePipeline(name: string): Observable<any> {
    return this.postPlain('/pipelines/toggle', { name });
  }

  deletePipeline(name: string): Observable<any> {
    return this.postPlain('/pipelines/delete', { name });
  }

  /**
   * Rebind a pipeline's device list.
   *
   * The schema is fixed once a pipeline is deployed, so this is what editing a
   * pipeline means: a settings-only update, no regeneration and no recompile.
   */
  /**
   * @param categories omit to leave them alone, pass [] to clear them. The backend
   * distinguishes absent from empty, so this must not be defaulted to [] — that
   * would strip every category on a device-only edit.
   */
  rebindPipeline(
    name: string,
    devices: string,
    categories?: string[]
  ): Observable<{ updated: number; name: string; deviceCount: number; restarted: number; restartNote: string }> {
    const body: Record<string, unknown> = { name, devices };
    if (categories !== undefined) body['categories'] = categories;
    return this.postPlain('/pipelines/rebind', body, 30000);
  }

  // ── Schemas: reusable device types, independent of any pipeline ──

  /** GET/DELETE helper — /schemas uses real verbs, unlike the POST-only endpoints. */
  private request<T>(
    method: 'get' | 'delete',
    endpoint: string,
    timeoutMs = 15000
  ): Observable<T> {
    return this.http
      .request<ApiEnvelope<T>>(method, `${this.baseUrl}${endpoint}`, { headers: this.headers })
      .pipe(
        timeout(timeoutMs),
        map((res) => {
          if (res.status === 'error') throw new Error(res.error || 'Unknown API error');
          return res.data as T;
        }),
        catchError((err) => this.fail(err))
      );
  }

  listSchemas(): Observable<Schema[]> {
    return this.request<Schema[]>('get', '/schemas');
  }

  getSchema(schemaClass: string): Observable<Schema> {
    return this.request<Schema>('get', `/schemas/${encodeURIComponent(schemaClass)}`);
  }

  /** Create a schema. No production, service item, or device binding side effects. */
  createSchema(req: CreateSchemaRequest): Observable<CreateSchemaResult> {
    return this.http
      .post<ApiEnvelope<CreateSchemaResult>>(`${this.baseUrl}/schemas`, req, {
        headers: this.headers,
      })
      .pipe(
        timeout(60000),
        map((res) => {
          if (res.status === 'error') throw new Error(res.error || 'Unknown API error');
          return res.data as CreateSchemaResult;
        }),
        catchError((err) => this.fail(err))
      );
  }

  /** Delete a schema. Refused by the server while a pipeline still references it. */
  deleteSchema(schemaClass: string): Observable<{ deleted: boolean; schemaClass: string }> {
    return this.request('delete', `/schemas/${encodeURIComponent(schemaClass)}`, 30000);
  }

  /**
   * Dry-run a device binding: browse each device and report which of the
   * schema's columns resolve. Moves "does this device really have these nodes?"
   * back to before deploy.
   */
  validateSchema(
    schemaClass: string,
    devices: string,
    server?: ServerProfile
  ): Observable<SchemaValidation> {
    return this.post<SchemaValidation>(
      `/schemas/${encodeURIComponent(schemaClass)}/validate`,
      { devices },
      30000,
      server
    );
  }
}

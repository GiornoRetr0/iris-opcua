import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpErrorResponse, HttpHeaders } from '@angular/common/http';
import { Observable, map, timeout, catchError, throwError } from 'rxjs';
import { ConfigService } from './config.service';
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
} from '../models/opcua.models';

interface ApiEnvelope<T> {
  status: 'ok' | 'error';
  data?: T;
  error?: string;
}

/** What the console shows when IRIS refuses the API account (HTTP 401). */
export const SIGN_IN_FAILED = 'Sign-in failed';

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
 * The API answers errors with a real status (400, 401, 404, 409, 500) and the
 * envelope {"status":"error","error":"…"}; a 500 says only "Internal error.
 * Reference …", the detail being in the IRIS application error log. Angular
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

@Injectable({ providedIn: 'root' })
export class ApiService {
  private http = inject(HttpClient);
  private configService = inject(ConfigService);

  private get baseUrl(): string {
    return this.configService.get().apiBaseUrl.replace(/\/+$/, '');
  }

  private get headers(): HttpHeaders {
    const cfg = this.configService.get();
    let headers = new HttpHeaders({ 'Content-Type': 'application/json' });
    if (cfg.apiUsername) {
      headers = headers.set(
        'Authorization',
        'Basic ' + btoa(cfg.apiUsername + ':' + (cfg.apiPassword || ''))
      );
    }
    return headers;
  }

  /**
   * Common error path for every call. A failed sign-in (see isSignInFailure) in
   * the hosted console means the IRIS account in Settings no longer signs in
   * (wrong or changed password, disabled account), so Settings opens on that tab
   * with the reason. The error still
   * reaches the caller, which shows apiErrorMessage(err).
   */
  private fail(err: any): Observable<never> {
    if (err?.name === 'TimeoutError') {
      return throwError(() => new Error('Request timed out'));
    }
    if (isSignInFailure(err) && this.configService.hosted) {
      document.dispatchEvent(
        new CustomEvent('open-settings', { detail: { tab: 'gateway', notice: SIGN_IN_FAILED } })
      );
    }
    return throwError(() => err);
  }

  /** Build request body with connection params from a specific server profile */
  private buildBody(params: Record<string, any> = {}, server?: ServerProfile): Record<string, any> {
    if (server) {
      const body: Record<string, any> = {
        url: server.url,
        securityMode: server.securityMode,
        ...params,
      };
      if (server.username) body['username'] = server.username;
      if (server.password) body['password'] = server.password;
      if (server.certPath) body['certPath'] = server.certPath;
      if (server.keyPath) body['keyPath'] = server.keyPath;
      if (server.trustDir) body['trustDir'] = server.trustDir;
      if (server.crlDir) body['crlDir'] = server.crlDir;
      if (server.clientURI) body['clientURI'] = server.clientURI;
      return body;
    }

    // Legacy fallback: use flat config fields
    const cfg = this.configService.get();
    const body: Record<string, any> = {
      url: cfg.serverUrl,
      securityMode: cfg.securityMode,
      ...params,
    };
    if (cfg.username) body['username'] = cfg.username;
    if (cfg.password) body['password'] = cfg.password;
    if (cfg.certPath) body['certPath'] = cfg.certPath;
    if (cfg.keyPath) body['keyPath'] = cfg.keyPath;
    if (cfg.trustDir) body['trustDir'] = cfg.trustDir;
    if (cfg.crlDir) body['crlDir'] = cfg.crlDir;
    if (cfg.clientURI) body['clientURI'] = cfg.clientURI;
    return body;
  }

  private post<T>(endpoint: string, params: Record<string, any> = {}, timeoutMs = 15000, server?: ServerProfile): Observable<T> {
    return this.http
      .post<ApiEnvelope<T>>(`${this.baseUrl}${endpoint}`, this.buildBody(params, server), {
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

  test(server?: ServerProfile): Observable<ConnectionTestResult> {
    return this.post<ConnectionTestResult>('/test', {}, 15000, server);
  }

  deploy(params: Record<string, any>, server?: ServerProfile): Observable<DeployResult> {
    return this.post<DeployResult>('/deploy', params, 60000, server);
  }

  listPipelines(): Observable<Pipeline[]> {
    return this.post<Pipeline[]>('/pipelines', {});
  }

  togglePipeline(name: string): Observable<any> {
    return this.post('/pipelines/toggle', { name });
  }

  deletePipeline(name: string): Observable<any> {
    return this.post('/pipelines/delete', { name });
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
    return this.post('/pipelines/rebind', body, 30000);
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

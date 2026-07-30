import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Observable, map, timeout, catchError, throwError } from 'rxjs';
import { ConfigService } from './config.service';
import {
  OpcuaNode,
  NodeReadResult,
  ConnectionTestResult,
  Pipeline,
  DeployResult,
  ServerProfile,
  MetricsSnapshot,
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
        catchError((err) => {
          if (err.name === 'TimeoutError') {
            return throwError(() => new Error('Request timed out'));
          }
          return throwError(() => err);
        })
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
        })
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

  editPipeline(params: Record<string, any>, server?: ServerProfile): Observable<any> {
    return this.post('/pipelines/edit', params, 60000, server);
  }

  getMetrics(): Observable<MetricsSnapshot> {
    return this.post<MetricsSnapshot>('/metrics', {}, 10000);
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
        catchError((err) => {
          if (err.name === 'TimeoutError') {
            return throwError(() => new Error('Request timed out'));
          }
          return throwError(() => err);
        })
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
        })
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

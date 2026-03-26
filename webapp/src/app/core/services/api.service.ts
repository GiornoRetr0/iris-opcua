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

  /** Build request body with connection params merged in */
  private buildBody(params: Record<string, any> = {}): Record<string, any> {
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

  private post<T>(endpoint: string, params: Record<string, any> = {}, timeoutMs = 15000): Observable<T> {
    return this.http
      .post<ApiEnvelope<T>>(`${this.baseUrl}${endpoint}`, this.buildBody(params), {
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

  browse(nodeNs?: number, nodeId?: string | number, nodeIdType?: number): Observable<OpcuaNode[]> {
    const params: Record<string, any> = {};
    if (nodeNs != null) params['nodeNs'] = nodeNs;
    if (nodeId != null) params['nodeId'] = String(nodeId);
    if (nodeIdType != null) params['nodeIdType'] = nodeIdType;
    return this.post<OpcuaNode[]>('/browse', params);
  }

  read(nodeNs: number, nodeId: string | number, nodeIdType: number): Observable<NodeReadResult> {
    return this.post<NodeReadResult>('/read', {
      nodeNs,
      nodeId: String(nodeId),
      nodeIdType,
    });
  }

  test(): Observable<ConnectionTestResult> {
    return this.post<ConnectionTestResult>('/test', {});
  }

  deploy(params: Record<string, any>): Observable<DeployResult> {
    return this.post<DeployResult>('/deploy', params, 60000);
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
}

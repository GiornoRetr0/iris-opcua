import { Injectable, signal, computed } from '@angular/core';
import { AppConfig, ServerProfile } from '../models/opcua.models';

const STORAGE_KEY = 'precisionArchitect::config';

let _nextId = 1;
function generateId(): string {
  return 'srv_' + Date.now().toString(36) + '_' + (_nextId++).toString(36);
}

const DEFAULTS: AppConfig = {
  serverUrl: '',
  securityMode: 1,
  username: '',
  password: '',
  apiBaseUrl: '/iris/csp/opcua/api',
  apiUsername: 'SuperUser',
  apiPassword: 'SYS',
  certPath: '',
  keyPath: '',
  trustDir: '',
  crlDir: '',
  clientURI: '',
  rootNodeId: '84',
  rootNodeNs: 0,
  autoRefreshInterval: 5,
  servers: [],
};

@Injectable({ providedIn: 'root' })
export class ConfigService {
  private _config = signal<AppConfig>({ ...DEFAULTS });

  readonly config = this._config.asReadonly();

  constructor() {
    this.load();
  }

  load(): void {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (raw) {
        const saved = JSON.parse(raw);
        const merged = { ...DEFAULTS };
        for (const key of Object.keys(saved)) {
          if (saved[key] !== '' && saved[key] != null) {
            (merged as any)[key] = saved[key];
          }
        }

        // Migration: if legacy single-server config exists but no servers[], convert it
        if (merged.serverUrl && (!merged.servers || merged.servers.length === 0)) {
          merged.servers = [{
            id: generateId(),
            name: this.deriveServerName(merged.serverUrl),
            url: merged.serverUrl,
            securityMode: merged.securityMode,
            username: merged.username,
            password: merged.password,
            certPath: merged.certPath,
            keyPath: merged.keyPath,
            trustDir: merged.trustDir,
            crlDir: merged.crlDir,
            clientURI: merged.clientURI,
            rootNodeId: merged.rootNodeId,
            rootNodeNs: merged.rootNodeNs,
          }];
        }

        this._config.set(merged);
      }
    } catch {
      // ignore corrupt storage
    }
  }

  save(partial: Partial<AppConfig>): void {
    const updated = { ...this._config(), ...partial };
    this._config.set(updated);
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(updated));
    } catch {
      // storage full or unavailable
    }
  }

  get(): AppConfig {
    return this._config();
  }

  // --- Server profile management ---

  getServers(): ServerProfile[] {
    return this._config().servers || [];
  }

  getServer(id: string): ServerProfile | undefined {
    return this.getServers().find(s => s.id === id);
  }

  addServer(server: Omit<ServerProfile, 'id'>): ServerProfile {
    const newServer: ServerProfile = { ...server, id: generateId() };
    const servers = [...this.getServers(), newServer];
    this.save({ servers });
    return newServer;
  }

  updateServer(id: string, updates: Partial<ServerProfile>): void {
    const servers = this.getServers().map(s =>
      s.id === id ? { ...s, ...updates } : s
    );
    this.save({ servers });
  }

  removeServer(id: string): void {
    const servers = this.getServers().filter(s => s.id !== id);
    this.save({ servers });
  }

  /** Derive a short display name from a server URL */
  private deriveServerName(url: string): string {
    try {
      const match = url.match(/:\/\/([^:/]+)/);
      return match ? match[1] : 'Server';
    } catch {
      return 'Server';
    }
  }
}

import { Injectable, signal, computed } from '@angular/core';
import { AppConfig } from '../models/opcua.models';

const STORAGE_KEY = 'precisionArchitect::config';

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
};

@Injectable({ providedIn: 'root' })
export class ConfigService {
  private _config = signal<AppConfig>({ ...DEFAULTS });

  readonly config = this._config.asReadonly();
  readonly isSecureMode = computed(() => this._config().securityMode === 3);

  constructor() {
    this.load();
  }

  load(): void {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (raw) {
        const saved = JSON.parse(raw);
        // Don't let empty saved values override non-empty defaults
        const merged = { ...DEFAULTS };
        for (const key of Object.keys(saved)) {
          if (saved[key] !== '' && saved[key] != null) {
            (merged as any)[key] = saved[key];
          }
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
}

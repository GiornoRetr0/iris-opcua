import { Injectable, signal, inject } from '@angular/core';
import { AppConfig, ServerProfile } from '../models/opcua.models';
import { RUNTIME_CONFIG } from '../runtime-config';

/**
 * Where configuration lives: `localStorage`, per-browser rather than per-user. It
 * holds the server list, the API address and the last IRIS username, and no
 * password: each OPC UA server names an IRIS credentials entry, read on the server,
 * and the IRIS sign-in is a token in sessionStorage (AuthService). The UI states the
 * browser-local part so a user is not surprised when their servers do not follow
 * them to another machine.
 */
const STORAGE_KEY = 'opcua-console::config';

/**
 * The previous key, from an earlier iteration of the product. Read once and
 * migrated so nobody loses their servers to a rename — the name was shipping
 * internal branding and would eventually surface in a support call.
 */
const LEGACY_STORAGE_KEY = 'precisionArchitect::config';

let _nextId = 1;
function generateId(): string {
  return 'srv_' + Date.now().toString(36) + '_' + (_nextId++).toString(36);
}

const DEFAULTS: AppConfig = {
  serverUrl: '',
  securityMode: 1,
  apiBaseUrl: '/iris/csp/opcua/api',
  apiUsername: 'SuperUser',
  autoRefreshInterval: 5,
  servers: [],
};

@Injectable({ providedIn: 'root' })
export class ConfigService {
  private readonly runtime = inject(RUNTIME_CONFIG);

  /**
   * IRIS serves this console next to its REST API (installed by the terminal
   * installer). The API address is then fixed by the installation, and there is
   * no default account: the user signs in with their own IRIS account.
   */
  readonly hosted = !!this.runtime.apiBaseUrl;

  /**
   * Several namespaces may each host a console on one IRIS origin, sharing one
   * localStorage. Keyed by API path so their server lists stay apart.
   */
  private readonly storageKey = this.hosted ? `${STORAGE_KEY}::${this.runtime.apiBaseUrl}` : STORAGE_KEY;

  private readonly defaults: AppConfig = this.hosted
    ? { ...DEFAULTS, apiBaseUrl: this.runtime.apiBaseUrl!, apiUsername: '' }
    : DEFAULTS;

  private _config = signal<AppConfig>({ ...this.defaults });

  readonly config = this._config.asReadonly();

  constructor() {
    this.load();
  }

  load(): void {
    try {
      let raw = localStorage.getItem(this.storageKey);
      if (!raw && !this.hosted) {
        // One-time migration off the old key. Written under the new key
        // immediately so this branch is taken exactly once.
        const legacy = localStorage.getItem(LEGACY_STORAGE_KEY);
        if (legacy) {
          localStorage.setItem(STORAGE_KEY, legacy);
          localStorage.removeItem(LEGACY_STORAGE_KEY);
          raw = legacy;
        }
      }
      if (raw) {
        const saved = JSON.parse(raw);
        const merged = { ...this.defaults };
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
            credentials: '',
            certPath: merged.certPath,
            keyPath: merged.keyPath,
            trustDir: merged.trustDir,
            crlDir: merged.crlDir,
            clientURI: merged.clientURI,
          }];
        }

        // Passwords used to be stored here: the IRIS API's and every OPC UA server's.
        // They are dropped, not moved: sign in again, and choose each server's
        // credentials again in Settings. Written back at once, so the passwords leave
        // localStorage on first load.
        const stripped = this.stripPasswords(merged);
        this._config.set(this.pin(merged));
        if (stripped) this.persist();
      }
    } catch {
      // ignore corrupt storage
    }
  }

  save(partial: Partial<AppConfig>): void {
    this._config.set(this.pin({ ...this._config(), ...partial }));
    this.persist();
  }

  private persist(): void {
    try {
      localStorage.setItem(this.storageKey, JSON.stringify(this._config()));
    } catch {
      // storage full or unavailable
    }
  }

  /**
   * Remove the password fields older versions stored (the IRIS API password, and an
   * OPC UA username and password at the top level and on every server), and give
   * each server a `credentials` field.
   * Returns whether anything was removed.
   */
  private stripPasswords(cfg: AppConfig): boolean {
    let stripped = false;
    const drop = (o: any) => {
      for (const key of ['username', 'password']) {
        if (key in o) {
          delete o[key];
          stripped = true;
        }
      }
    };
    drop(cfg);
    if ('apiPassword' in cfg) {
      delete (cfg as any).apiPassword;
      stripped = true;
    }
    cfg.servers = (cfg.servers || []).map((s) => {
      const copy: any = { ...s };
      drop(copy);
      if (typeof copy.credentials !== 'string') copy.credentials = '';
      return copy as ServerProfile;
    });
    return stripped;
  }

  /** A hosted console always calls the API it was installed with. */
  private pin(cfg: AppConfig): AppConfig {
    return this.hosted ? { ...cfg, apiBaseUrl: this.runtime.apiBaseUrl! } : cfg;
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

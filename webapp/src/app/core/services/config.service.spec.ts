import { TestBed } from '@angular/core/testing';
import { ConfigService } from './config.service';
import { RUNTIME_CONFIG } from '../runtime-config';

/**
 * Older consoles stored every OPC UA username and password in localStorage. They are
 * dropped on load, not moved anywhere, and the cleaned config is written back at once.
 */
describe('ConfigService drops stored OPC UA passwords', () => {
  const KEY = 'opcua-console::config';

  afterEach(() => localStorage.removeItem(KEY));

  it('removes them from servers and the legacy fields, and rewrites storage', () => {
    localStorage.setItem(KEY, JSON.stringify({
      apiBaseUrl: '/api', apiUsername: 'SuperUser', apiPassword: 'SYS',
      username: 'legacy', password: 'legacy-secret',
      servers: [{ id: 's1', name: 'plc', url: 'opc.tcp://plc:4840', securityMode: 1, username: 'opc', password: 'opcua-secret' }],
    }));
    TestBed.configureTestingModule({ providers: [{ provide: RUNTIME_CONFIG, useValue: {} }] });
    const cfg = TestBed.inject(ConfigService).get();

    expect(cfg.servers[0].credentials).toBe('');
    expect('password' in cfg.servers[0]).toBeFalse();
    expect('username' in cfg.servers[0]).toBeFalse();
    const stored = localStorage.getItem(KEY)!;
    expect(stored).not.toContain('opcua-secret');
    expect(stored).not.toContain('legacy-secret');
    // The IRIS API sign-in is a separate matter and stays.
    expect(cfg.apiPassword).toBe('SYS');
  });
});

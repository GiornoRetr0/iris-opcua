import { TestBed } from '@angular/core/testing';
import { HttpErrorResponse, provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { ApiService, apiErrorMessage } from './api.service';
import { ConfigService } from './config.service';

/**
 * The API answers every error with a real HTTP status and the usual envelope
 * ({"status":"error","error":"…"}). The console must show that message for any
 * status, and a failed IRIS sign-in (401) in the hosted console opens Settings.
 */
describe('apiErrorMessage', () => {
  it('reads the envelope for any status', () => {
    for (const status of [400, 404, 409, 500]) {
      const err = new HttpErrorResponse({ status, error: { status: 'error', error: `msg ${status}` } });
      expect(apiErrorMessage(err)).toBe(`msg ${status}`);
    }
  });

  it('says sign-in failed on a 401 without a JSON body', () => {
    expect(apiErrorMessage(new HttpErrorResponse({ status: 401, error: '' }))).toBe('Sign-in failed');
  });

  it('says sign-in failed on IRIS\'s own 404, which has no envelope', () => {
    // Under the default security setup CSP answers a failed sign-in with a bare
    // text/html 404; Angular leaves the unparsed text in .error.
    expect(apiErrorMessage(new HttpErrorResponse({ status: 404, error: 'Not Found' }))).toBe('Sign-in failed');
    expect(apiErrorMessage(new HttpErrorResponse({ status: 404, error: null }))).toBe('Sign-in failed');
  });

  it('shows our own message for an enveloped 404', () => {
    const err = new HttpErrorResponse({
      status: 404,
      error: { status: 'error', error: "Schema 'OPCUA.DS.NoSuch' does not exist" },
    });
    expect(apiErrorMessage(err)).toBe("Schema 'OPCUA.DS.NoSuch' does not exist");
  });

  it('never shows Angular\'s "Http failure response" text', () => {
    const err = new HttpErrorResponse({ status: 502, error: '<html>Bad Gateway</html>', url: 'http://x/api/ping' });
    expect(apiErrorMessage(err)).not.toContain('Http failure');
    expect(apiErrorMessage(err)).toContain('502');
  });

  it('uses an Error\'s message, else the fallback', () => {
    expect(apiErrorMessage(new Error('Request timed out'))).toBe('Request timed out');
    expect(apiErrorMessage(undefined)).toBe('Request failed');
  });
});

describe('ApiService on 401', () => {
  let http: HttpTestingController;
  let events: CustomEvent[];
  const listener = (e: Event) => events.push(e as CustomEvent);

  function setup(hosted: boolean): ApiService {
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        {
          provide: ConfigService,
          useValue: { hosted, get: () => ({ apiBaseUrl: '/api', apiUsername: 'u', apiPassword: 'p' }) },
        },
      ],
    });
    http = TestBed.inject(HttpTestingController);
    return TestBed.inject(ApiService);
  }

  beforeEach(() => {
    events = [];
    document.addEventListener('open-settings', listener);
  });

  afterEach(() => document.removeEventListener('open-settings', listener));

  it('opens Settings on the sign-in tab in the hosted console', () => {
    const api = setup(true);
    let message = '';
    api.listPipelines().subscribe({ error: (e) => (message = apiErrorMessage(e)) });
    http.expectOne('/api/pipelines').flush({ status: 'error', error: 'Sign-in failed' }, { status: 401, statusText: 'Unauthorized' });

    expect(message).toBe('Sign-in failed');
    expect(events.length).toBe(1);
    expect(events[0].detail).toEqual({ tab: 'gateway', notice: 'Sign-in failed' });
  });

  it('opens Settings on IRIS\'s bare 404 for a failed sign-in', () => {
    const api = setup(true);
    let message = '';
    api.listPipelines().subscribe({ error: (e) => (message = apiErrorMessage(e)) });
    http.expectOne('/api/pipelines').flush('Not Found', { status: 404, statusText: 'Not Found' });

    expect(message).toBe('Sign-in failed');
    expect(events.length).toBe(1);
    expect(events[0].detail).toEqual({ tab: 'gateway', notice: 'Sign-in failed' });
  });

  it('does not open Settings for an enveloped 404', () => {
    const api = setup(true);
    api.getSchema('X').subscribe({ error: () => {} });
    http.expectOne('/api/schemas/X').flush({ status: 'error', error: 'nope' }, { status: 404, statusText: 'Not Found' });
    expect(events.length).toBe(0);
  });

  it('does not open Settings outside the hosted console', () => {
    const api = setup(false);
    api.listSchemas().subscribe({ error: () => {} });
    http.expectOne('/api/schemas').flush({ status: 'error', error: 'Sign-in failed' }, { status: 401, statusText: 'Unauthorized' });
    expect(events.length).toBe(0);
  });
});

/**
 * Audit #15: a pipeline's OPC UA password lives in its IRIS credentials entry,
 * set at deploy. Managing an existing pipeline (list, toggle, delete, rebind)
 * reads that entry server-side, so these calls send no connection fields and
 * never carry the browser's stored OPC UA password.
 */
describe('ApiService pipeline management sends no OPC UA credentials', () => {
  let http: HttpTestingController;
  let api: ApiService;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        {
          provide: ConfigService,
          useValue: {
            hosted: false,
            get: () => ({
              apiBaseUrl: '/api', apiUsername: 'u', apiPassword: 'p',
              serverUrl: 'opc.tcp://plc', securityMode: 1, username: 'user1', password: 'opcua-secret',
            }),
          },
        },
      ],
    });
    http = TestBed.inject(HttpTestingController);
    api = TestBed.inject(ApiService);
  });

  afterEach(() => http.verify());

  it('rebind, toggle, delete and list carry only their own fields', () => {
    api.rebindPipeline('P1', 'i=85', ['OPCUA']).subscribe();
    api.togglePipeline('P1').subscribe();
    api.deletePipeline('P1').subscribe();
    api.listPipelines().subscribe();
    const bodies = [
      http.expectOne('/api/pipelines/rebind'),
      http.expectOne('/api/pipelines/toggle'),
      http.expectOne('/api/pipelines/delete'),
      http.expectOne('/api/pipelines'),
    ].map((req) => req.request.body);

    expect(bodies[0]).toEqual({ name: 'P1', devices: 'i=85', categories: ['OPCUA'] });
    expect(bodies[1]).toEqual({ name: 'P1' });
    expect(bodies[2]).toEqual({ name: 'P1' });
    expect(bodies[3]).toEqual({});
    for (const body of bodies) expect(JSON.stringify(body)).not.toContain('opcua-secret');
  });

  it('deploy still sends the username and password', () => {
    api.deploy({ schemaClass: 'S', devices: 'i=85' }).subscribe();
    const body = http.expectOne('/api/deploy').request.body;
    expect(body.username).toBe('user1');
    expect(body.password).toBe('opcua-secret');
  });
});

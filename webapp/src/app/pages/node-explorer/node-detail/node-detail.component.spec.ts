import { ComponentFixture, TestBed } from '@angular/core/testing';
import { signal } from '@angular/core';
import { Subject, of } from 'rxjs';
import { NodeDetailComponent } from './node-detail.component';
import { ApiService } from '../../../core/services/api.service';
import { ConfigService } from '../../../core/services/config.service';
import { NodeReadResult, ServerProfile, TreeNode } from '../../../core/models/opcua.models';
import { localClock, localDateTime } from '../../../core/util/iris-time';

const CERT: ServerProfile = { id: 'cert', name: 'CertServer', url: 'opc.tcp://certified-server:10001', securityMode: 3, credentials: '' };
const PLC: ServerProfile = { id: 'plc', name: 'UaCPPServer', url: 'opc.tcp://localhost:10000', securityMode: 1, credentials: '' };

function node(over: Partial<TreeNode> = {}): TreeNode {
  return {
    nodeNs: 0, nodeId: 17634, nodeIdType: 0, displayName: 'LocalTime', nodeCategory: 'variable',
    hasChildren: false, level: 2, serverId: 'cert', ...over,
  } as TreeNode;
}

function good(over: Partial<NodeReadResult> = {}): NodeReadResult {
  return { nodeNs: 0, nodeId: '17634', nodeIdType: 0, value: 255, statusCode: 0,
           inferredType: 'OPCUA.Types.IntegerDataValue', ...over };
}

describe('NodeDetailComponent', () => {
  let api: jasmine.SpyObj<ApiService>;
  let cfg: ReturnType<typeof signal<any>>;
  let fixture: ComponentFixture<NodeDetailComponent>;
  let c: NodeDetailComponent;

  beforeEach(() => {
    api = jasmine.createSpyObj<ApiService>('ApiService', ['read']);
    api.read.and.returnValue(of(good()));
    cfg = signal<any>({ autoRefreshInterval: 5, servers: [CERT, PLC] });
    TestBed.configureTestingModule({
      imports: [NodeDetailComponent],
      providers: [
        { provide: ApiService, useValue: api },
        {
          provide: ConfigService,
          useValue: {
            config: cfg.asReadonly(),
            get: () => cfg(),
            getServer: (id: string) => (cfg().servers as ServerProfile[]).find((s) => s.id === id),
          },
        },
      ],
    });
    fixture = TestBed.createComponent(NodeDetailComponent);
    c = fixture.componentInstance;
  });

  afterEach(() => fixture.destroy());

  function select(n: TreeNode | null): void {
    fixture.componentRef.setInput('node', n);
    fixture.detectChanges();
  }

  describe('server', () => {
    it("reads from the server the node was browsed from, not the default one", () => {
      select(node());
      expect(api.read).toHaveBeenCalledWith(0, 17634, 0, CERT);
    });

    it('does not fall back to the default server when the node\'s server was removed', () => {
      select(node({ serverId: 'gone' }));
      expect(api.read).not.toHaveBeenCalled();
      expect(c.lastError()).toContain('no longer configured');
    });

    it('names the server in the breadcrumb', () => {
      const objects = node({ displayName: 'Objects', nodeId: 85, nodeCategory: 'folder' });
      const server = node({ displayName: 'Server', nodeId: 2253, nodeCategory: 'object', parentRef: objects });
      select(node({ parentRef: server }));
      expect(c.breadcrumb()).toEqual(['CertServer', 'Objects', 'Server', 'LocalTime']);
    });
  });

  describe('Bad status', () => {
    it('is a failed read, not a fresh one', () => {
      api.read.and.returnValue(of(good({ statusCode: 0x80340000, value: '' })));
      select(node());
      expect(c.lastSuccessAt()).toBeNull();
      expect(c.consecutiveFailures()).toBe(1);
      expect(c.lastError()).toContain('BadNodeIdUnknown');
      expect(c.ageLabel()).toBe('never read');
    });

    it('Good and Uncertain still count as fresh', () => {
      api.read.and.returnValue(of(good({ statusCode: 0x40000000 })));
      select(node());
      expect(c.lastSuccessAt()).not.toBeNull();
      expect(c.consecutiveFailures()).toBe(0);
    });
  });

  describe('properties', () => {
    it('have a data type, like variables', () => {
      select(node({ nodeCategory: 'property' }));
      expect(c.dataTypeLabel()).toBe('Integer');
    });

    it('a folder still has none', () => {
      select(node({ nodeCategory: 'folder' }));
      expect(c.dataTypeLabel()).toContain('not applicable');
    });
  });

  describe('timestamps', () => {
    it('are UTC from the API and shown in local time', () => {
      const expected = localClock(new Date(Date.UTC(2026, 10, 10, 23, 41, 29)));
      expect(c.formatTimestamp('2026-11-10 23:41:29.3923420')).toBe(expected);
    });

    it('the null DateTime and garbage show as missing', () => {
      expect(c.formatTimestamp('1601-01-01 00:00:00.0000000')).toBe('—');
      expect(c.formatTimestamp('nonsense')).toBe('—');
      api.read.and.returnValue(of(good({ sourceTimestamp: '1601-01-01 00:00:00.0000000' })));
      select(node());
      expect(c.sourceTimestampText()).toBe('');
    });
  });

  describe('hero value', () => {
    const hero = (value: any, inferredType = 'OPCUA.Types.StringDataValue') =>
      c.formatHeroValue(good({ value, inferredType }));

    it('does not read a leading number out of a string', () => {
      expect(hero('3 phases')).toBe('3 phases');
      expect(hero('12abc')).toBe('12abc');
    });

    it('shows a timestamp as a local date and time, not 2026', () => {
      const expected = localDateTime(new Date(Date.UTC(2026, 10, 10, 23, 43, 40)));
      expect(hero('2026-11-10 23:43:40.3923420', 'OPCUA.Types.TimeStampDataValue')).toBe(expected);
    });

    it('keeps every digit of an Int64', () => {
      expect(hero('9223372036854775807', 'OPCUA.Types.IntegerDataValue')).toBe('9223372036854775807');
      expect(hero(-42, 'OPCUA.Types.IntegerDataValue')).toBe('-42');
    });

    it('shows decimals without losing small values', () => {
      expect(hero(21.5, 'OPCUA.Types.DoubleDataValue')).toBe('21.50');
      expect(hero(0.001, 'OPCUA.Types.DoubleDataValue')).toBe('0.00100');
      expect(hero(0, 'OPCUA.Types.DoubleDataValue')).toBe('0');
    });

    it('shows a Boolean as true/false', () => {
      expect(hero(0, 'OPCUA.Types.BooleanDataValue')).toBe('false');
      expect(hero(1, 'OPCUA.Types.BooleanDataValue')).toBe('true');
    });

    it('shows an array as JSON', () => {
      expect(hero([1, 2, 3], 'OPCUA.Types.ArrayDataValue.Integer')).toBe('[1,2,3]');
    });
  });

  describe('read ordering', () => {
    it("drops the previous node's answer when another node is selected", () => {
      const first = new Subject<NodeReadResult>();
      api.read.and.returnValues(first, of(good({ value: 'B' })));
      select(node({ displayName: 'A' }));
      select(node({ displayName: 'B', nodeId: 2994 }));

      expect(first.observed).toBeFalse();
      expect(c.readResult()?.value).toBe('B');
    });

    it('clears the previous node\'s value while the new read runs', () => {
      api.read.and.returnValues(of(good({ value: 'A' })), new Subject<NodeReadResult>());
      select(node({ displayName: 'A' }));
      select(node({ displayName: 'B', nodeId: 2994 }));
      expect(c.readResult()).toBeNull();
    });

    it('a timer tick waits for the read in flight', () => {
      api.read.and.returnValue(new Subject<NodeReadResult>());
      select(node());
      c.readValue(true);
      expect(api.read).toHaveBeenCalledTimes(1);
    });

    it('a manual Read replaces the read in flight, so answers cannot cross', () => {
      const first = new Subject<NodeReadResult>();
      const second = new Subject<NodeReadResult>();
      api.read.and.returnValues(first, second);
      select(node());
      c.readValue();
      expect(first.observed).toBeFalse();
      second.next(good({ value: 'new' }));
      expect(c.readResult()?.value).toBe('new');
      expect(c.readLoading()).toBeFalse();
    });
  });

  describe('node id types', () => {
    it('follow the native numbering: 0 Numeric, 3 String, 4 GUID, 5 ByteString', () => {
      const cases: [number, string, string][] = [
        [0, 'i', 'Numeric'], [3, 's', 'String'], [4, 'g', 'GUID'], [5, 'b', 'ByteString'],
      ];
      for (const [t, prefix, name] of cases) {
        select(node({ nodeIdType: t }));
        expect(c.idPrefix()).withContext(`type ${t}`).toBe(prefix);
        expect(c.idTypeName()).withContext(`type ${t}`).toBe(name);
      }
    });
  });

  describe('refresh interval', () => {
    it('applies a settings change without reselecting the node', () => {
      select(node());
      const spy = spyOn(window, 'setInterval').and.callThrough();
      cfg.set({ ...cfg(), autoRefreshInterval: 7 });
      fixture.detectChanges();
      expect(spy).toHaveBeenCalledWith(jasmine.any(Function), 7000);
    });
  });
});

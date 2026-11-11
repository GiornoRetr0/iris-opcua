import { TestBed } from '@angular/core/testing';
import { of, throwError } from 'rxjs';
import { OpcuaTreeComponent } from './opcua-tree.component';
import { ApiService } from '../../core/services/api.service';
import { ConfigService } from '../../core/services/config.service';
import { ServerProfile, TreeNode } from '../../core/models/opcua.models';

const CERT: ServerProfile = { id: 'cert', name: 'CertServer', url: 'opc.tcp://certified-server:10001', securityMode: 3, credentials: '' };

describe('OpcuaTreeComponent browse failure', () => {
  let api: jasmine.SpyObj<ApiService>;
  let tree: OpcuaTreeComponent;

  beforeEach(() => {
    api = jasmine.createSpyObj<ApiService>('ApiService', ['browse']);
    TestBed.configureTestingModule({
      imports: [OpcuaTreeComponent],
      providers: [
        { provide: ApiService, useValue: api },
        { provide: ConfigService, useValue: { getServer: (id: string) => (id === 'cert' ? CERT : undefined) } },
      ],
    });
    // No detectChanges: the constructor's effect (which browses roots) never runs.
    tree = TestBed.createComponent(OpcuaTreeComponent).componentInstance;
  });

  const folder = (): TreeNode =>
    ({ nodeNs: 0, nodeId: 2253, nodeIdType: 0, displayName: 'Server', nodeCategory: 'object',
       hasChildren: true, level: 1, serverId: 'cert' }) as TreeNode;

  it('is shown as an error, not as an empty node, and is retried on the next expand', () => {
    const n = folder();
    api.browse.and.returnValue(throwError(() => new Error('BadConnectionClosed')));

    tree.toggleExpand(n);

    expect(n.expanded).toBeFalse();
    expect(n.children).toBeUndefined();
    expect(tree.childCount(n)).toBeNull();
    expect(n.browseError).toBe('BadConnectionClosed');

    api.browse.and.returnValue(of([{ nodeNs: 0, nodeId: 2256, displayName: 'ServerStatus' } as any]));
    tree.toggleExpand(n);

    expect(api.browse).toHaveBeenCalledTimes(2);
    expect(api.browse.calls.mostRecent().args[3]).toBe(CERT);
    expect(n.browseError).toBeUndefined();
    expect(n.expanded).toBeTrue();
    expect(n.children?.length).toBe(1);
  });
});

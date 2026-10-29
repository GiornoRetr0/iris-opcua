import { TestBed } from '@angular/core/testing';
import { Router } from '@angular/router';
import { of, throwError } from 'rxjs';
import { PipelinesDashboardComponent } from './pipelines-dashboard.component';
import { ApiService } from '../../core/services/api.service';
import { ConfigService } from '../../core/services/config.service';

/**
 * A delete or toggle can fail *after* its change was saved, e.g. "Pipeline deleted,
 * but the running production could not be updated: …". The dashboard must show
 * that text and reload the list, so a pipeline that is gone doesn't stay on screen.
 */
describe('PipelinesDashboardComponent action errors', () => {
  let api: jasmine.SpyObj<ApiService>;
  let component: PipelinesDashboardComponent;

  beforeEach(() => {
    api = jasmine.createSpyObj<ApiService>('ApiService', ['listPipelines', 'deletePipeline', 'togglePipeline']);
    api.listPipelines.and.returnValue(of([]));
    TestBed.configureTestingModule({
      imports: [PipelinesDashboardComponent],
      providers: [
        { provide: ApiService, useValue: api },
        { provide: ConfigService, useValue: { get: () => ({ autoRefreshInterval: 5 }) } },
        { provide: Router, useValue: jasmine.createSpyObj('Router', ['navigate']) },
      ],
    });
    // No detectChanges: ngOnInit (and its refresh timer) never runs.
    component = TestBed.createComponent(PipelinesDashboardComponent).componentInstance;
  });

  it('shows the server text and reloads after a delete that failed once saved', () => {
    const text = "Pipeline deleted, but the running production could not be updated: production 'OPCUA.Pipeline.Production' is troubled";
    api.deletePipeline.and.returnValue(throwError(() => new Error(text)));
    component.pendingDelete.set({ name: 'Line 3.Press-A' } as any);

    component.confirmDelete();

    expect(component.actionError()).toBe(text);
    expect(api.listPipelines).toHaveBeenCalledTimes(1);
  });

  it('reloads after a toggle that failed once saved', () => {
    const text = "Pipeline enabled and saved, but the production could not be updated: production 'OPCUA.Pipeline.Production' is suspended";
    api.togglePipeline.and.returnValue(throwError(() => new Error(text)));

    component.togglePipeline({ name: 'Line 3.Press-A' } as any);

    expect(component.actionError()).toBe(text);
    expect(api.listPipelines).toHaveBeenCalledTimes(1);
  });
});

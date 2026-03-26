import { Routes } from '@angular/router';

export const routes: Routes = [
  {
    path: '',
    redirectTo: 'explorer',
    pathMatch: 'full',
  },
  {
    path: 'explorer',
    loadComponent: () =>
      import('./pages/node-explorer/node-explorer.component').then(
        (m) => m.NodeExplorerComponent
      ),
  },
  {
    path: 'pipelines',
    loadComponent: () =>
      import('./pages/pipelines-dashboard/pipelines-dashboard.component').then(
        (m) => m.PipelinesDashboardComponent
      ),
  },
  {
    path: 'pipelines/new',
    loadComponent: () =>
      import('./pages/pipeline-wizard/pipeline-wizard.component').then(
        (m) => m.PipelineWizardComponent
      ),
  },
  {
    path: 'pipelines/edit/:name',
    loadComponent: () =>
      import('./pages/pipeline-wizard/pipeline-wizard.component').then(
        (m) => m.PipelineWizardComponent
      ),
  },
];

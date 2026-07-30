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
    path: 'schemas',
    loadComponent: () =>
      import('./pages/schema-library/schema-library.component').then(
        (m) => m.SchemaLibraryComponent
      ),
  },
  {
    path: 'schemas/new',
    loadComponent: () =>
      import('./pages/schema-builder/schema-builder.component').then(
        (m) => m.SchemaBuilderComponent
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
    path: 'pipelines/bind/:schema',
    loadComponent: () =>
      import('./pages/device-binding/device-binding.component').then(
        (m) => m.DeviceBindingComponent
      ),
  },
  {
    // Editing a pipeline means changing its device binding — the schema is fixed
    // at deploy time — so it is the binding screen, not a separate wizard.
    path: 'pipelines/edit/:name',
    loadComponent: () =>
      import('./pages/device-binding/device-binding.component').then(
        (m) => m.DeviceBindingComponent
      ),
  },
  {
    // Creating a pipeline starts from a schema, so send people to pick one.
    path: 'pipelines/new',
    redirectTo: 'schemas',
  },
  {
    path: 'docs',
    loadComponent: () =>
      import('./pages/documentation/documentation.component').then(
        (m) => m.DocumentationComponent
      ),
  },
  {
    // Unknown paths land somewhere useful instead of a blank page — notably
    // /monitoring, which existed until the Monitoring tab was removed and may
    // still be bookmarked.
    path: '**',
    redirectTo: 'explorer',
  },
];

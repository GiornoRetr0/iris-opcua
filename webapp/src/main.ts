import { bootstrapApplication } from '@angular/platform-browser';
import { appConfig } from './app/app.config';
import { AppComponent } from './app/app.component';
import { RUNTIME_CONFIG, loadRuntimeConfig } from './app/core/runtime-config';

loadRuntimeConfig()
  .then((runtime) =>
    bootstrapApplication(AppComponent, {
      providers: [...appConfig.providers, { provide: RUNTIME_CONFIG, useValue: runtime }],
    })
  )
  .catch((err) => console.error(err));

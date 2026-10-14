import { ApplicationConfig, provideZoneChangeDetection } from '@angular/core';
import { provideRouter, withHashLocation } from '@angular/router';
import { provideHttpClient } from '@angular/common/http';

import { routes } from './app.routes';

export const appConfig: ApplicationConfig = {
  providers: [
    provideZoneChangeDetection({ eventCoalescing: true }),
    // Hash URLs: a static IRIS web application has no index.html fallback, so a
    // path route would 404 on reload. Also keeps the console path-independent.
    provideRouter(routes, withHashLocation()),
    provideHttpClient(),
  ],
};

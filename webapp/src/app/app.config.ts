import { ApplicationConfig, provideZoneChangeDetection } from '@angular/core';
import { provideRouter, withHashLocation } from '@angular/router';
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { authInterceptor } from './core/services/auth.interceptor';

import { routes } from './app.routes';

export const appConfig: ApplicationConfig = {
  providers: [
    provideZoneChangeDetection({ eventCoalescing: true }),
    // Hash URLs: a static IRIS web application has no index.html fallback, so a
    // path route would 404 on reload. Also keeps the console path-independent.
    // Relies on index.html having no <base>; see the note there.
    provideRouter(routes, withHashLocation()),
    // The IRIS sign-in is added to API calls here, not by each caller.
    provideHttpClient(withInterceptors([authInterceptor])),
  ],
};

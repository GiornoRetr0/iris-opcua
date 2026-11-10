import { HttpErrorResponse, HttpInterceptorFn, HttpRequest } from '@angular/common/http';
import { inject } from '@angular/core';
import { catchError, from, switchMap, throwError } from 'rxjs';
import { AUTH_REQUEST, AuthService } from './auth.service';
import { isSignInFailure } from './api.service';

/**
 * Adds the IRIS sign-in to every call to the API. If IRIS refuses a token (it
 * expired or was revoked, e.g. after a restart), the token is refreshed once and
 * the call repeated; when that fails too, the error reaches the caller, and
 * ApiService opens Settings to sign in again.
 */
export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const auth = inject(AuthService);
  if (req.context.get(AUTH_REQUEST) || !auth.isApiUrl(req.url)) return next(req);

  const withAuth = (r: HttpRequest<unknown>, header: string | null) =>
    header ? r.clone({ setHeaders: { Authorization: header } }) : r;

  return from(auth.authorization()).pipe(
    switchMap((header) =>
      next(withAuth(req, header)).pipe(
        catchError((err: unknown) => {
          if (!header?.startsWith('Bearer ') || !(err instanceof HttpErrorResponse) || !isSignInFailure(err)) {
            return throwError(() => err);
          }
          return from(auth.refresh()).pipe(
            switchMap((ok) => (ok ? from(auth.authorization()) : throwError(() => err))),
            switchMap((fresh) => (fresh ? next(withAuth(req, fresh)) : throwError(() => err)))
          );
        })
      )
    )
  );
};

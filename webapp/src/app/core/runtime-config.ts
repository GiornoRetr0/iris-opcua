import { InjectionToken } from '@angular/core';

/**
 * Deployment facts the console cannot know at build time. When IRIS hosts the
 * console, the terminal installer writes `config.json` next to `index.html`
 * naming the REST application of the same namespace. Absent (e.g. `ng serve`),
 * the console behaves as a standalone app configured in Settings.
 */
export interface RuntimeConfig {
  /** Path of the REST API on the same origin, e.g. `/csp/opcua/api`. */
  apiBaseUrl?: string;
}

export const RUNTIME_CONFIG = new InjectionToken<RuntimeConfig>('RUNTIME_CONFIG', {
  factory: () => ({}),
});

/** Fetched relative to the document, so it works under any web application path. */
export async function loadRuntimeConfig(): Promise<RuntimeConfig> {
  try {
    const res = await fetch('config.json', { cache: 'no-store' });
    if (!res.ok) return {};
    const cfg = await res.json();
    return typeof cfg?.apiBaseUrl === 'string' && cfg.apiBaseUrl ? { apiBaseUrl: cfg.apiBaseUrl } : {};
  } catch {
    // Not hosted: the dev server answers with index.html, which is not JSON.
    return {};
  }
}

import { InjectionToken } from '@angular/core';

/**
 * Deployment facts the console cannot know at build time. When IRIS hosts the
 * console, the terminal installer writes `config.json` next to `index.html`
 * naming the REST application of the same namespace. Absent (e.g. `ng serve`),
 * the console behaves as a standalone app configured in Settings.
 */
export interface RuntimeConfig {
  /**
   * Path of the REST API on the same origin, e.g. `/iris262/csp/opcua/api`. The
   * installer writes it relative to the console (`../api`), since a web server may
   * mount IRIS under a prefix it cannot see; resolved here against the page.
   */
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
    if (typeof cfg?.apiBaseUrl !== 'string' || !cfg.apiBaseUrl) return {};
    return { apiBaseUrl: new URL(cfg.apiBaseUrl, document.baseURI).pathname };
  } catch {
    // Not hosted: the dev server answers with index.html, which is not JSON.
    return {};
  }
}

// content.js — Entry point / orchestrator
(function () {
  'use strict';

  const NS = (window.__opcuaExt = window.__opcuaExt || {});

  // Clean up stale elements from previous extension loads
  var stale = document.getElementById('cat_OPCUA');
  if (stale) stale.remove();
  var stalePanel = document.getElementById('opcua-panel');
  if (stalePanel) stalePanel.remove();

  function init() {
    // Wait for the selector element to appear
    var selector = document.getElementById('selector');
    if (selector) {
      bootstrap();
      return;
    }

    // MutationObserver fallback: wait for #selector to appear
    var observer = new MutationObserver(function (mutations, obs) {
      if (document.getElementById('selector')) {
        obs.disconnect();
        bootstrap();
      }
    });

    observer.observe(document.body, { childList: true, subtree: true });

    // Safety timeout: stop waiting after 30s
    setTimeout(function () {
      observer.disconnect();
    }, 30000);
  }

  async function bootstrap() {
    if (!NS.ApiClient) return;

    // Derive API URL from current page
    var apiBaseUrl = NS.ApiClient.deriveApiBaseUrl();
    if (!apiBaseUrl) return;

    // Probe the API to check if OPC UA adapter is installed
    // Try with default creds first, then without auth
    var reachable = await NS.ApiClient.pingUrl(apiBaseUrl, 'SuperUser', 'SYS');
    if (!reachable) {
      reachable = await NS.ApiClient.pingUrl(apiBaseUrl, '', '');
    }
    if (!reachable) return; // OPC UA adapter not available — stay silent

    // Load per-instance config from chrome.storage
    if (NS.ConfigPanel) {
      var cfg = await NS.ConfigPanel.load();
      // Initialize ApiClient with loaded config (apiBaseUrl is always derived)
      NS.ApiClient.setConfig(cfg);
    }

    // Restore persisted DAV nodes
    if (NS.DataAccessView) {
      await NS.DataAccessView.loadMonitoredNodes();
    }

    // Wire config change callback
    if (NS.ConfigPanel) {
      NS.ConfigPanel.setChangeCallback(function (config, serverChanged) {
        if (NS.ApiClient) NS.ApiClient.setConfig(config);
        if (serverChanged) {
          if (NS.DataAccessView) NS.DataAccessView.clearAll();
          if (NS.ContentPanel && NS.ContentPanel.isActive()) {
            if (NS.TreeBrowser) NS.TreeBrowser.loadRoot();
            NS.ContentPanel.updateConnectionStatus();
          }
          // Reload DAV nodes for new server
          if (NS.DataAccessView) NS.DataAccessView.loadMonitoredNodes();
        }
      });
    }

    // Inject sidebar nav button
    if (NS.SidebarInjector) {
      NS.SidebarInjector.inject();
    }

    // Pre-create the content panel (hidden)
    if (NS.ContentPanel) {
      NS.ContentPanel.createPanel();
    }
  }

  // Start when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();

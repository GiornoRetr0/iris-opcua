// popup.js — Browser action: status + quick links (multi-instance aware)
(function () {
  'use strict';

  var STORAGE_PREFIX = 'opcuaExtConfig::';

  /** Derive API base URL from a portal page URL */
  function deriveApiBaseUrl(pageUrl) {
    var idx = pageUrl.indexOf('/csp/sys/');
    if (idx === -1) return '';
    return pageUrl.substring(0, idx) + '/csp/opcua/api';
  }

  /** Derive portal link from an API base URL */
  function derivePortalUrl(apiBaseUrl) {
    // apiBaseUrl looks like http://host:port/prefix/opcua/api
    var match = apiBaseUrl.match(/^(https?:\/\/[^/]+)(.*?)\/csp\/opcua\/api$/);
    if (match) {
      return match[1] + match[2] + '/csp/sys/%25CSP.Portal.Home.zen?$NAMESPACE=OPCUA&';
    }
    return '';
  }

  function render(cfg, apiBaseUrl) {
    document.getElementById('popup-server').textContent = cfg.serverUrl || '-';
    document.getElementById('popup-api').textContent = apiBaseUrl || '-';

    var portalUrl = derivePortalUrl(apiBaseUrl);
    var link = document.getElementById('popup-portal-link');
    if (portalUrl) {
      link.href = portalUrl;
      link.addEventListener('click', function (e) {
        e.preventDefault();
        chrome.tabs.create({ url: portalUrl });
      });
    } else {
      link.href = '#';
      link.textContent = 'No portal detected';
    }

    // Ping API
    if (apiBaseUrl) {
      checkApi(apiBaseUrl, cfg.apiUsername, cfg.apiPassword);
    } else {
      setStatus('Not configured', 'unknown');
    }
  }

  // Try to get instance info from active tab
  chrome.tabs.query({ active: true, currentWindow: true }, function (tabs) {
    var tab = tabs && tabs[0];
    var apiBaseUrl = '';

    if (tab && tab.url) {
      apiBaseUrl = deriveApiBaseUrl(tab.url);
    }

    if (apiBaseUrl) {
      // Active tab is a portal page — load its per-instance config
      var key = STORAGE_PREFIX + apiBaseUrl;
      chrome.storage.local.get(key, function (result) {
        var cfg = (result && result[key]) || {};
        cfg.apiBaseUrl = apiBaseUrl;
        render(cfg, apiBaseUrl);
      });
    } else {
      // Not on a portal page — find first known instance config
      chrome.storage.local.get(null, function (allData) {
        var instanceKey = Object.keys(allData).find(function (k) {
          return k.indexOf(STORAGE_PREFIX) === 0;
        });
        if (instanceKey) {
          var storedApiBase = instanceKey.substring(STORAGE_PREFIX.length);
          var cfg = allData[instanceKey] || {};
          cfg.apiBaseUrl = storedApiBase;
          render(cfg, storedApiBase);
        } else {
          render({}, '');
        }
      });
    }
  });

  function checkApi(baseUrl, apiUser, apiPass) {
    var url = baseUrl.replace(/\/+$/, '') + '/ping';
    var headers = {};
    if (apiUser) {
      headers['Authorization'] = 'Basic ' + btoa(apiUser + ':' + (apiPass || ''));
    }
    fetch(url, { method: 'GET', headers: headers, credentials: 'same-origin' })
      .then(function (resp) {
        if (!resp.ok) throw new Error('HTTP ' + resp.status);
        return resp.json();
      })
      .then(function (json) {
        if (json.status === 'ok') {
          setStatus('Online', 'ok');
        } else {
          setStatus('Error', 'err');
        }
      })
      .catch(function () {
        setStatus('Offline', 'err');
      });
  }

  function setStatus(text, type) {
    var el = document.getElementById('popup-status');
    el.textContent = text;
    el.className = 'popup-badge popup-badge-' + type;
  }
})();

// popup.js — Browser action: status + quick links
(function () {
  'use strict';

  var STORAGE_KEY = 'opcuaExtConfig';

  var defaults = {
    serverUrl: 'opc.tcp://localhost:48010',
    apiBaseUrl: 'http://localhost/iris251/csp/opcua/api'
  };

  chrome.storage.local.get(STORAGE_KEY, function (result) {
    var cfg = (result && result[STORAGE_KEY]) || defaults;

    document.getElementById('popup-server').textContent = cfg.serverUrl || '-';
    document.getElementById('popup-api').textContent = cfg.apiBaseUrl || '-';

    // Build portal link
    var apiBase = cfg.apiBaseUrl || defaults.apiBaseUrl;
    // Extract the prefix (e.g., /iris251) from the API URL
    var match = apiBase.match(/^(https?:\/\/[^/]+)(\/[^/]+)/);
    var portalUrl = match
      ? match[1] + match[2] + '/csp/sys/%25CSP.Portal.Home.zen?$NAMESPACE=OPCUA&'
      : 'http://localhost/iris251/csp/sys/%25CSP.Portal.Home.zen?$NAMESPACE=OPCUA&';

    document.getElementById('popup-portal-link').href = portalUrl;
    document.getElementById('popup-portal-link').addEventListener('click', function (e) {
      e.preventDefault();
      chrome.tabs.create({ url: portalUrl });
    });

    // Ping API
    if (cfg.apiBaseUrl) {
      checkApi(cfg.apiBaseUrl, cfg.apiUsername, cfg.apiPassword);
    } else {
      setStatus('Not configured', 'unknown');
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

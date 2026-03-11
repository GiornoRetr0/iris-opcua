// config-panel.js — Settings form with chrome.storage persistence
(function () {
  'use strict';

  const NS = (window.__opcuaExt = window.__opcuaExt || {});

  function storageKey() {
    var base = NS.ApiClient ? NS.ApiClient.deriveApiBaseUrl() : '';
    return 'opcuaExtConfig::' + base;
  }

  const DEFAULTS = {
    serverUrl: '',
    securityMode: 1,
    username: '',
    password: '',
    apiUsername: 'SuperUser',
    apiPassword: 'SYS',
    autoRefreshInterval: 5,
    rootNodeId: '84',
    rootNodeNs: 0
  };

  let _config = Object.assign({}, DEFAULTS);
  let _panel = null;
  let _visible = false;
  let _onConfigChange = null;

  function setChangeCallback(cb) {
    _onConfigChange = cb;
  }

  /** Load config from chrome.storage (per-instance), returns merged config */
  async function load() {
    var key = storageKey();
    return new Promise((resolve) => {
      if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
        chrome.storage.local.get(key, (result) => {
          if (result && result[key]) {
            Object.assign(_config, result[key]);
          }
          // Always derive apiBaseUrl from current page
          _config.apiBaseUrl = NS.ApiClient ? NS.ApiClient.deriveApiBaseUrl() : '';
          resolve(_config);
        });
      } else {
        _config.apiBaseUrl = NS.ApiClient ? NS.ApiClient.deriveApiBaseUrl() : '';
        resolve(_config);
      }
    });
  }

  /** Save current config to chrome.storage (per-instance, strips derived fields) */
  async function save() {
    var key = storageKey();
    return new Promise((resolve) => {
      if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
        const toSave = Object.assign({}, _config);
        delete toSave.apiBaseUrl; // never persist derived value
        const data = {};
        data[key] = toSave;
        chrome.storage.local.set(data, () => resolve());
      } else {
        resolve();
      }
    });
  }

  function getConfig() {
    return Object.assign({}, _config);
  }

  /** Build the settings panel DOM (hidden by default) */
  function createPanel() {
    if (_panel) return _panel;

    _panel = document.createElement('div');
    _panel.className = 'opcua-ext opcua-config-panel';
    _panel.style.display = 'none';

    _panel.innerHTML =
      '<div class="opcua-config-header">' +
        '<span class="opcua-config-title">OPC UA Settings</span>' +
        '<button class="opcua-config-close" title="Close">\u00D7</button>' +
      '</div>' +
      '<div class="opcua-config-body">' +
        '<div class="opcua-config-group">' +
          '<label>OPC UA Server URL</label>' +
          '<input type="text" id="opcua-cfg-serverUrl" placeholder="opc.tcp://host:port">' +
        '</div>' +
        '<div class="opcua-config-group">' +
          '<label>Security Mode</label>' +
          '<select id="opcua-cfg-securityMode">' +
            '<option value="1">None</option>' +
            '<option value="3">Sign & Encrypt</option>' +
          '</select>' +
        '</div>' +
        '<div class="opcua-config-group opcua-config-row">' +
          '<div class="opcua-config-half">' +
            '<label>Username</label>' +
            '<input type="text" id="opcua-cfg-username" autocomplete="off">' +
          '</div>' +
          '<div class="opcua-config-half">' +
            '<label>Password</label>' +
            '<input type="password" id="opcua-cfg-password" autocomplete="off">' +
          '</div>' +
        '</div>' +
        '<div class="opcua-config-group">' +
          '<label>API Base URL (auto-detected)</label>' +
          '<div id="opcua-cfg-apiBaseUrl" style="padding:4px 6px;background:#f0f0f0;border:1px solid #ccc;border-radius:3px;font-size:12px;word-break:break-all;color:#555;"></div>' +
        '</div>' +
        '<div class="opcua-config-group opcua-config-row">' +
          '<div class="opcua-config-half">' +
            '<label>IRIS API Username</label>' +
            '<input type="text" id="opcua-cfg-apiUsername" autocomplete="off" placeholder="SuperUser">' +
          '</div>' +
          '<div class="opcua-config-half">' +
            '<label>IRIS API Password</label>' +
            '<input type="password" id="opcua-cfg-apiPassword" autocomplete="off">' +
          '</div>' +
        '</div>' +
        '<div class="opcua-config-group opcua-config-row">' +
          '<div class="opcua-config-half">' +
            '<label>Root Node ID</label>' +
            '<input type="text" id="opcua-cfg-rootNodeId" placeholder="84">' +
          '</div>' +
          '<div class="opcua-config-half">' +
            '<label>Root Namespace</label>' +
            '<input type="number" id="opcua-cfg-rootNodeNs" min="0" placeholder="0">' +
          '</div>' +
        '</div>' +
        '<div class="opcua-config-group">' +
          '<label>Auto-refresh Interval (seconds)</label>' +
          '<input type="number" id="opcua-cfg-autoRefreshInterval" min="1" max="60" placeholder="5">' +
        '</div>' +
        '<div class="opcua-config-actions">' +
          '<button id="opcua-cfg-test" class="opcua-btn opcua-btn-secondary">Test Connection</button>' +
          '<button id="opcua-cfg-save" class="opcua-btn opcua-btn-primary">Save</button>' +
        '</div>' +
        '<div id="opcua-cfg-status" class="opcua-config-status"></div>' +
      '</div>';

    // Wire events
    _panel.querySelector('.opcua-config-close').addEventListener('click', hide);
    _panel.querySelector('#opcua-cfg-test').addEventListener('click', handleTest);
    _panel.querySelector('#opcua-cfg-save').addEventListener('click', handleSave);

    return _panel;
  }

  function populateFields() {
    if (!_panel) return;
    _panel.querySelector('#opcua-cfg-serverUrl').value = _config.serverUrl || '';
    _panel.querySelector('#opcua-cfg-securityMode').value = String(_config.securityMode || 1);
    _panel.querySelector('#opcua-cfg-username').value = _config.username || '';
    _panel.querySelector('#opcua-cfg-password').value = _config.password || '';
    _panel.querySelector('#opcua-cfg-apiBaseUrl').textContent = _config.apiBaseUrl || '';
    _panel.querySelector('#opcua-cfg-apiUsername').value = _config.apiUsername || '';
    _panel.querySelector('#opcua-cfg-apiPassword').value = _config.apiPassword || '';
    _panel.querySelector('#opcua-cfg-rootNodeId').value = _config.rootNodeId || '84';
    _panel.querySelector('#opcua-cfg-rootNodeNs').value = _config.rootNodeNs != null ? _config.rootNodeNs : 0;
    _panel.querySelector('#opcua-cfg-autoRefreshInterval').value = _config.autoRefreshInterval || 5;
  }

  function readFields() {
    if (!_panel) return;
    _config.serverUrl = _panel.querySelector('#opcua-cfg-serverUrl').value.trim();
    _config.securityMode = parseInt(_panel.querySelector('#opcua-cfg-securityMode').value, 10) || 1;
    _config.username = _panel.querySelector('#opcua-cfg-username').value.trim();
    _config.password = _panel.querySelector('#opcua-cfg-password').value;
    _config.apiUsername = _panel.querySelector('#opcua-cfg-apiUsername').value.trim();
    _config.apiPassword = _panel.querySelector('#opcua-cfg-apiPassword').value;
    _config.rootNodeId = _panel.querySelector('#opcua-cfg-rootNodeId').value.trim() || '84';
    _config.rootNodeNs = parseInt(_panel.querySelector('#opcua-cfg-rootNodeNs').value, 10) || 0;
    _config.autoRefreshInterval = parseInt(_panel.querySelector('#opcua-cfg-autoRefreshInterval').value, 10) || 5;
  }

  function setStatus(msg, isError) {
    const el = _panel.querySelector('#opcua-cfg-status');
    el.textContent = msg;
    el.className = 'opcua-config-status' + (isError ? ' opcua-config-status-error' : ' opcua-config-status-ok');
    el.style.display = msg ? 'block' : 'none';
  }

  async function handleTest() {
    readFields();
    // Temporarily apply config to ApiClient for the test
    NS.ApiClient.setConfig(_config);
    setStatus('Testing connection...', false);
    try {
      const result = await NS.ApiClient.test();
      if (result.connected) {
        setStatus('Connected to ' + result.url + ' (' + result.responseTimeMs + 'ms)', false);
      } else {
        setStatus('Connection failed: ' + (result.error || 'Unknown error'), true);
      }
    } catch (err) {
      setStatus('Error: ' + err.message, true);
    }
  }

  async function handleSave() {
    const oldServerUrl = _config.serverUrl;
    readFields();
    NS.ApiClient.setConfig(_config);
    await save();
    setStatus('Settings saved', false);
    if (_onConfigChange) {
      _onConfigChange(_config, oldServerUrl !== _config.serverUrl);
    }
  }

  function show() {
    if (!_panel) return;
    populateFields();
    _panel.style.display = 'block';
    _visible = true;
    setStatus('', false);
  }

  function hide() {
    if (!_panel) return;
    _panel.style.display = 'none';
    _visible = false;
  }

  function toggle() {
    _visible ? hide() : show();
  }

  function isVisible() {
    return _visible;
  }

  NS.ConfigPanel = {
    load: load,
    save: save,
    getConfig: getConfig,
    createPanel: createPanel,
    populateFields: populateFields,
    setChangeCallback: setChangeCallback,
    show: show,
    hide: hide,
    toggle: toggle,
    isVisible: isVisible
  };
})();

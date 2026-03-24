// api-client.js — REST communication layer for OPC UA endpoints
(function () {
  'use strict';

  const NS = (window.__opcuaExt = window.__opcuaExt || {});

  const DEFAULT_TIMEOUT = 15000;

  // Connection params merged into every request body
  let _config = {
    serverUrl: '',
    securityMode: 1,
    username: '',
    password: '',
    apiBaseUrl: '',
    apiUsername: '',
    apiPassword: ''
  };

  function setConfig(cfg) {
    Object.assign(_config, cfg);
  }

  function getConfig() {
    return Object.assign({}, _config);
  }

  /** Build request headers including Basic Auth for the IRIS API. */
  function buildHeaders(extra) {
    const headers = Object.assign({}, extra || {});
    if (_config.apiUsername) {
      headers['Authorization'] = 'Basic ' + btoa(_config.apiUsername + ':' + (_config.apiPassword || ''));
    }
    return headers;
  }

  /**
   * Core fetch wrapper.
   * POST JSON to the given endpoint, merge connection params, handle envelope.
   */
  async function request(endpoint, params) {
    if (!_config.apiBaseUrl) {
      throw new Error('API Base URL not configured');
    }

    const url = _config.apiBaseUrl.replace(/\/+$/, '') + endpoint;

    const body = Object.assign({
      url: _config.serverUrl,
      securityMode: _config.securityMode
    }, params);

    // Only include OPC UA auth fields if non-empty
    if (_config.username) body.username = _config.username;
    if (_config.password) body.password = _config.password;

    // Include certificate paths for Sign & Encrypt mode
    if (_config.certPath) body.certPath = _config.certPath;
    if (_config.keyPath) body.keyPath = _config.keyPath;
    if (_config.trustDir) body.trustDir = _config.trustDir;
    if (_config.crlDir) body.crlDir = _config.crlDir;
    if (_config.clientURI) body.clientURI = _config.clientURI;

    const timeout = params._timeout || DEFAULT_TIMEOUT;
    delete params._timeout;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeout);

    try {
      const resp = await fetch(url, {
        method: 'POST',
        headers: buildHeaders({ 'Content-Type': 'application/json' }),
        credentials: 'same-origin',
        body: JSON.stringify(body),
        signal: controller.signal
      });

      clearTimeout(timer);

      if (!resp.ok) {
        const text = await resp.text().catch(() => '');
        throw new Error('HTTP ' + resp.status + ': ' + (text || resp.statusText));
      }

      const json = await resp.json();

      if (json.status === 'error') {
        throw new Error(json.error || 'Unknown API error');
      }

      return json.data;
    } catch (err) {
      clearTimeout(timer);
      if (err.name === 'AbortError') {
        throw new Error('Request timed out after ' + (timeout / 1000) + 's');
      }
      throw err;
    }
  }

  /** Health check — GET only, no body needed. */
  async function ping() {
    if (!_config.apiBaseUrl) {
      throw new Error('API Base URL not configured');
    }
    const url = _config.apiBaseUrl.replace(/\/+$/, '') + '/ping';
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), DEFAULT_TIMEOUT);
    try {
      const resp = await fetch(url, {
        method: 'GET',
        headers: buildHeaders(),
        credentials: 'same-origin',
        signal: controller.signal
      });
      clearTimeout(timer);
      if (!resp.ok) throw new Error('HTTP ' + resp.status);
      const json = await resp.json();
      return json.data;
    } catch (err) {
      clearTimeout(timer);
      if (err.name === 'AbortError') throw new Error('Ping timed out');
      throw err;
    }
  }

  /**
   * Browse children of a node.
   * @param {number} nodeNs - Namespace index (default 0)
   * @param {string|number} nodeId - Node identifier (default 84 = Objects)
   * @param {number} nodeIdType - 0=numeric, 3=string
   * @returns {Array} Array of child node descriptors
   */
  async function browse(nodeNs, nodeId, nodeIdType) {
    const params = {};
    if (nodeNs != null) params.nodeNs = nodeNs;
    if (nodeId != null) params.nodeId = String(nodeId);
    if (nodeIdType != null) params.nodeIdType = nodeIdType;
    return request('/browse', params);
  }

  /**
   * Read a single node value.
   * @returns {Object} {nodeNs, nodeId, nodeIdType, value, sourceTimestamp, serverTimestamp, statusCode, inferredType, readError?}
   */
  async function read(nodeNs, nodeId, nodeIdType) {
    const params = {};
    if (nodeNs != null) params.nodeNs = nodeNs;
    if (nodeId != null) params.nodeId = String(nodeId);
    if (nodeIdType != null) params.nodeIdType = nodeIdType;
    return request('/read', params);
  }

  /**
   * Deploy a data pipeline (generate DataSource + Production, compile, start).
   * @param {Object} params - {nodes, className, dataSourceName, productionName, mode, ...}
   * @returns {Object} {dataSourceClass, productionClass, tableName, deployed, compiled, started, error?}
   */
  async function deploy(params) {
    params._timeout = 60000;
    return request('/deploy', params);
  }

  /**
   * List all deployed pipelines.
   * @returns {Array} Array of pipeline objects with status, nodes, settings
   */
  async function listPipelines() {
    return request('/pipelines', {});
  }

  /**
   * Toggle a pipeline service on/off.
   * @param {string} name - Pipeline service name
   */
  async function togglePipeline(name) {
    return request('/pipelines/toggle', { name: name });
  }

  /**
   * Delete a pipeline.
   * @param {string} name - Pipeline service name
   */
  async function deletePipeline(name) {
    return request('/pipelines/delete', { name: name });
  }

  /**
   * Test OPC UA server connectivity.
   * @returns {Object} {url, connected, responseTimeMs, error?}
   */
  async function test() {
    return request('/test', {});
  }

  /**
   * Derive the OPC UA API base URL from the current page URL.
   * Strips everything from '/csp/' onward and appends '/opcua/api'.
   */
  function deriveApiBaseUrl() {
    var href = window.location.href;
    var idx = href.indexOf('/csp/sys/');
    if (idx === -1) return '';
    return href.substring(0, idx) + '/csp/opcua/api';
  }

  /**
   * Standalone ping to a given API base URL.
   * Returns true if the OPC UA REST API responds, false otherwise.
   */
  async function pingUrl(apiBaseUrl, apiUser, apiPass) {
    if (!apiBaseUrl) return false;
    var url = apiBaseUrl.replace(/\/+$/, '') + '/ping';
    var headers = {};
    if (apiUser) {
      headers['Authorization'] = 'Basic ' + btoa(apiUser + ':' + (apiPass || ''));
    }
    var controller = new AbortController();
    var timer = setTimeout(function () { controller.abort(); }, 5000);
    try {
      var resp = await fetch(url, {
        method: 'GET',
        headers: headers,
        credentials: 'same-origin',
        signal: controller.signal
      });
      clearTimeout(timer);
      if (!resp.ok) return false;
      var json = await resp.json();
      return json.status === 'ok';
    } catch (err) {
      clearTimeout(timer);
      return false;
    }
  }

  NS.ApiClient = {
    setConfig: setConfig,
    getConfig: getConfig,
    ping: ping,
    pingUrl: pingUrl,
    browse: browse,
    read: read,
    deploy: deploy,
    listPipelines: listPipelines,
    togglePipeline: togglePipeline,
    deletePipeline: deletePipeline,
    test: test,
    deriveApiBaseUrl: deriveApiBaseUrl
  };
})();

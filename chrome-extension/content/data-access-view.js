// data-access-view.js — Live-updating table for monitoring multiple OPC UA node values
(function () {
  'use strict';

  const NS = (window.__opcuaExt = window.__opcuaExt || {});

  let _container = null;
  let _monitoredNodes = [];
  let _autoRefreshTimer = null;
  let _autoRefreshRunning = false;
  let _refreshing = false;
  let _lastRefreshTime = null;
  let _visible = false;

  function createPanel() {
    if (_container) return _container;

    _container = document.createElement('div');
    _container.className = 'opcua-ext opcua-dav';
    _container.innerHTML =
      '<div class="opcua-dav-toolbar">' +
        '<button class="opcua-btn opcua-btn-secondary opcua-dav-toggle-btn">' +
          '\u25B6 Start' +
        '</button>' +
        '<button class="opcua-btn opcua-btn-secondary opcua-dav-refresh-btn">' +
          '\u21BB Refresh' +
        '</button>' +
        '<button class="opcua-btn opcua-btn-secondary opcua-dav-clear-btn">' +
          'Clear All' +
        '</button>' +
        '<span class="opcua-dav-status"></span>' +
      '</div>' +
      '<div class="opcua-dav-table-wrapper">' +
        '<table class="opcua-dav-table">' +
          '<thead><tr>' +
            '<th>#</th>' +
            '<th>Node ID</th>' +
            '<th>Display Name</th>' +
            '<th>Value</th>' +
            '<th>Status</th>' +
            '<th>Timestamp</th>' +
            '<th></th>' +
          '</tr></thead>' +
          '<tbody></tbody>' +
        '</table>' +
      '</div>' +
      '<div class="opcua-dav-empty">No nodes monitored. Add nodes from the tree or detail panel.</div>';

    // Wire toolbar buttons
    _container.querySelector('.opcua-dav-toggle-btn')
      .addEventListener('click', handleToggle);
    _container.querySelector('.opcua-dav-refresh-btn')
      .addEventListener('click', function () { refreshAll(); });
    _container.querySelector('.opcua-dav-clear-btn')
      .addEventListener('click', clearAll);

    renderTable();
    return _container;
  }

  function nodeKey(n) {
    return n.nodeNs + ':' + n.nodeId + ':' + (n.nodeIdType || 0);
  }

  function addNode(nodeData) {
    if (!nodeData || nodeData.nodeId == null) return;

    // Deduplicate
    var key = nodeKey(nodeData);
    for (var i = 0; i < _monitoredNodes.length; i++) {
      if (nodeKey(_monitoredNodes[i]) === key) return;
    }

    _monitoredNodes.push({
      nodeNs: nodeData.nodeNs,
      nodeId: nodeData.nodeId,
      nodeIdType: nodeData.nodeIdType || 0,
      displayName: nodeData.displayName || String(nodeData.nodeId),
      value: null,
      sourceTimestamp: null,
      serverTimestamp: null,
      statusCode: null,
      readError: null,
      lastRefreshTime: null
    });

    saveMonitoredNodes();
    renderTable();
  }

  function removeNode(index) {
    if (index < 0 || index >= _monitoredNodes.length) return;
    _monitoredNodes.splice(index, 1);
    saveMonitoredNodes();
    renderTable();
  }

  function clearAll() {
    _monitoredNodes = [];
    stopAutoRefresh();
    saveMonitoredNodes();
    renderTable();
  }

  async function refreshAll() {
    if (_refreshing || _monitoredNodes.length === 0) return;
    _refreshing = true;
    updateStatus('Refreshing...');

    var nodes = _monitoredNodes.map(function (n) {
      return { nodeNs: n.nodeNs, nodeId: String(n.nodeId), nodeIdType: n.nodeIdType };
    });

    try {
      var result = await NS.ApiClient.readBulk(nodes);
      var now = new Date();
      _lastRefreshTime = now;

      if (result && result.nodes) {
        for (var i = 0; i < result.nodes.length && i < _monitoredNodes.length; i++) {
          var r = result.nodes[i];
          var m = _monitoredNodes[i];
          var oldVal = m.value;

          m.value = r.value;
          m.sourceTimestamp = r.sourceTimestamp || null;
          m.serverTimestamp = r.serverTimestamp || null;
          m.statusCode = r.statusCode;
          m.readError = r.readError || null;
          m.lastRefreshTime = now;
          m._changed = (JSON.stringify(oldVal) !== JSON.stringify(r.value));
        }
      }
    } catch (err) {
      for (var j = 0; j < _monitoredNodes.length; j++) {
        _monitoredNodes[j].readError = err.message;
      }
    }

    _refreshing = false;
    renderTable();
    updateStatus();

    // Clear flash after animation
    setTimeout(function () {
      for (var k = 0; k < _monitoredNodes.length; k++) {
        _monitoredNodes[k]._changed = false;
      }
    }, 600);
  }

  function startAutoRefresh() {
    if (_autoRefreshRunning) return;
    _autoRefreshRunning = true;
    var cfg = NS.ConfigPanel ? NS.ConfigPanel.getConfig() : {};
    var interval = (cfg.autoRefreshInterval || 5) * 1000;
    _autoRefreshTimer = setInterval(function () {
      if (_visible && _monitoredNodes.length > 0) {
        refreshAll();
      }
    }, interval);
    updateToggleButton();
    // Immediate first refresh
    if (_monitoredNodes.length > 0) refreshAll();
  }

  function stopAutoRefresh() {
    if (_autoRefreshTimer) {
      clearInterval(_autoRefreshTimer);
      _autoRefreshTimer = null;
    }
    _autoRefreshRunning = false;
    updateToggleButton();
  }

  function handleToggle() {
    if (_autoRefreshRunning) {
      stopAutoRefresh();
    } else {
      startAutoRefresh();
    }
  }

  function updateToggleButton() {
    if (!_container) return;
    var btn = _container.querySelector('.opcua-dav-toggle-btn');
    if (btn) {
      btn.textContent = _autoRefreshRunning ? '\u23F8 Pause' : '\u25B6 Start';
    }
  }

  function updateStatus(msg) {
    if (!_container) return;
    var el = _container.querySelector('.opcua-dav-status');
    if (!el) return;
    if (msg) {
      el.textContent = msg;
      return;
    }
    var parts = ['Monitoring ' + _monitoredNodes.length + ' node' +
      (_monitoredNodes.length !== 1 ? 's' : '')];
    if (_lastRefreshTime) {
      parts.push('Last refresh: ' + formatTime(_lastRefreshTime));
    }
    el.textContent = parts.join(' \u00B7 ');
  }

  function formatTime(d) {
    return d.getHours().toString().padStart(2, '0') + ':' +
      d.getMinutes().toString().padStart(2, '0') + ':' +
      d.getSeconds().toString().padStart(2, '0');
  }

  function setVisible(v) {
    _visible = v;
    if (!v) {
      // Pause auto-refresh when not visible
      if (_autoRefreshTimer) {
        clearInterval(_autoRefreshTimer);
        _autoRefreshTimer = null;
      }
    } else if (_autoRefreshRunning && !_autoRefreshTimer) {
      // Resume
      var cfg = NS.ConfigPanel ? NS.ConfigPanel.getConfig() : {};
      var interval = (cfg.autoRefreshInterval || 5) * 1000;
      _autoRefreshTimer = setInterval(function () {
        if (_visible && _monitoredNodes.length > 0) {
          refreshAll();
        }
      }, interval);
    }
  }

  function renderTable() {
    if (!_container) return;

    var empty = _container.querySelector('.opcua-dav-empty');
    var wrapper = _container.querySelector('.opcua-dav-table-wrapper');
    var tbody = _container.querySelector('.opcua-dav-table tbody');

    if (_monitoredNodes.length === 0) {
      empty.style.display = 'block';
      wrapper.style.display = 'none';
      updateStatus();
      return;
    }

    empty.style.display = 'none';
    wrapper.style.display = 'block';

    var html = '';
    for (var i = 0; i < _monitoredNodes.length; i++) {
      var n = _monitoredNodes[i];
      var valStr = formatValue(n.value);
      var statusClass = '';
      if (n.readError) {
        statusClass = ' opcua-dav-status-bad';
      } else if (n.statusCode === 0 && n.value != null) {
        statusClass = ' opcua-dav-status-good';
      }
      var rowClass = n._changed ? ' opcua-dav-flash' : '';

      html +=
        '<tr class="' + rowClass + '">' +
          '<td class="opcua-dav-col-idx">' + (i + 1) + '</td>' +
          '<td class="opcua-dav-col-nodeid" title="ns=' + n.nodeNs + '; type=' + n.nodeIdType + '">' +
            escHtml(String(n.nodeId)) + '</td>' +
          '<td class="opcua-dav-col-name">' + escHtml(n.displayName) + '</td>' +
          '<td class="opcua-dav-col-value' + rowClass + '">' + valStr + '</td>' +
          '<td class="opcua-dav-col-status' + statusClass + '">' +
            (n.readError ? escHtml(n.readError) : (n.statusCode != null ? n.statusCode : '\u2014')) +
          '</td>' +
          '<td class="opcua-dav-col-ts">' +
            escHtml(n.sourceTimestamp || '\u2014') + '</td>' +
          '<td class="opcua-dav-col-remove">' +
            '<button class="opcua-dav-remove-btn" data-idx="' + i + '" title="Remove">\u00D7</button>' +
          '</td>' +
        '</tr>';
    }
    tbody.innerHTML = html;

    // Wire remove buttons
    var removeBtns = tbody.querySelectorAll('.opcua-dav-remove-btn');
    for (var j = 0; j < removeBtns.length; j++) {
      removeBtns[j].addEventListener('click', function (e) {
        e.stopPropagation();
        var idx = parseInt(this.getAttribute('data-idx'), 10);
        removeNode(idx);
      });
    }

    updateStatus();
  }

  function formatValue(val) {
    if (val == null) return '<span class="opcua-dav-null">\u2014</span>';
    if (Array.isArray(val)) {
      return '<span class="opcua-dav-array">[' +
        val.map(function (v) { return escHtml(String(v)); }).join(', ') +
        ']</span>';
    }
    return escHtml(String(val));
  }

  // Storage — persisted per apiBaseUrl + serverUrl
  function storageKey() {
    var cfg = NS.ApiClient ? NS.ApiClient.getConfig() : {};
    var apiBase = cfg.apiBaseUrl || '';
    var server = cfg.serverUrl || '';
    return 'opcuaExtDAV::' + apiBase + '::' + server;
  }

  function saveMonitoredNodes() {
    var key = storageKey();
    var toSave = _monitoredNodes.map(function (n) {
      return {
        nodeNs: n.nodeNs,
        nodeId: n.nodeId,
        nodeIdType: n.nodeIdType,
        displayName: n.displayName
      };
    });
    if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
      var data = {};
      data[key] = toSave;
      chrome.storage.local.set(data);
    }
  }

  function loadMonitoredNodes() {
    var key = storageKey();
    return new Promise(function (resolve) {
      if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
        chrome.storage.local.get(key, function (result) {
          if (result && result[key] && Array.isArray(result[key])) {
            _monitoredNodes = result[key].map(function (n) {
              return {
                nodeNs: n.nodeNs,
                nodeId: n.nodeId,
                nodeIdType: n.nodeIdType,
                displayName: n.displayName || String(n.nodeId),
                value: null,
                sourceTimestamp: null,
                serverTimestamp: null,
                statusCode: null,
                readError: null,
                lastRefreshTime: null
              };
            });
          }
          renderTable();
          resolve();
        });
      } else {
        resolve();
      }
    });
  }

  function getNodeCount() {
    return _monitoredNodes.length;
  }

  function escHtml(s) {
    var d = document.createElement('div');
    d.textContent = s;
    return d.innerHTML;
  }

  NS.DataAccessView = {
    createPanel: createPanel,
    addNode: addNode,
    removeNode: removeNode,
    clearAll: clearAll,
    refreshAll: refreshAll,
    startAutoRefresh: startAutoRefresh,
    stopAutoRefresh: stopAutoRefresh,
    setVisible: setVisible,
    loadMonitoredNodes: loadMonitoredNodes,
    getNodeCount: getNodeCount
  };
})();

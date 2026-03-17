// node-detail.js — Right pane: read values, timestamps, type
(function () {
  'use strict';

  const NS = (window.__opcuaExt = window.__opcuaExt || {});

  let _container = null;
  let _currentNode = null;
  let _autoRefreshTimer = null;
  let _autoRefreshEnabled = false;

  function createPanel() {
    if (_container) return _container;

    _container = document.createElement('div');
    _container.className = 'opcua-ext opcua-detail';
    _container.innerHTML =
      '<div class="opcua-detail-empty">Select a node to view details</div>';

    return _container;
  }

  function showNode(nodeData) {
    if (!_container) return;
    _currentNode = nodeData;
    stopAutoRefresh();
    render();

    // Auto-read for Variable nodes
    if (nodeData.nodeClass === 'Variable') {
      readCurrentNode();
    }
  }

  function render() {
    if (!_container || !_currentNode) return;
    const n = _currentNode;
    const isVariable = (n.nodeClass === 'Variable');

    let html =
      '<div class="opcua-detail-header">' +
        '<span class="opcua-detail-icon">' + (isVariable ? '\uD83C\uDFF7\uFE0F' : '\uD83D\uDCC1') + '</span>' +
        '<span class="opcua-detail-name">' + escHtml(n.displayName) + '</span>' +
      '</div>' +
      '<table class="opcua-detail-meta">' +
        '<tr><td class="opcua-detail-label">Node ID</td><td>' + escHtml(String(n.nodeId)) + '</td></tr>' +
        '<tr><td class="opcua-detail-label">Namespace</td><td>' + n.nodeNs + '</td></tr>' +
        '<tr><td class="opcua-detail-label">ID Type</td><td>' + nodeIdTypeLabel(n.nodeIdType) + '</td></tr>' +
        '<tr><td class="opcua-detail-label">Class</td><td>' + escHtml(n.nodeClass || 'Unknown') + '</td></tr>' +
      '</table>';

    if (isVariable) {
      html +=
        '<div class="opcua-detail-actions">' +
          '<button class="opcua-btn opcua-btn-secondary opcua-detail-read-btn">Read</button>' +
          '<button class="opcua-btn opcua-btn-primary opcua-detail-add-dav-btn">+ DAV</button>' +
          '<label class="opcua-detail-autorefresh">' +
            '<input type="checkbox" class="opcua-detail-autorefresh-cb"' +
              (_autoRefreshEnabled ? ' checked' : '') + '>' +
            ' Auto-refresh' +
          '</label>' +
        '</div>' +
        '<div class="opcua-detail-value-section">' +
          renderValueSection() +
        '</div>';
    } else {
      html +=
        '<div class="opcua-detail-object-msg">' +
          'This is an Object node. Expand it in the tree to browse its children.' +
        '</div>';
    }

    _container.innerHTML = html;

    // Wire events
    const readBtn = _container.querySelector('.opcua-detail-read-btn');
    if (readBtn) {
      readBtn.addEventListener('click', readCurrentNode);
    }
    const davBtn = _container.querySelector('.opcua-detail-add-dav-btn');
    if (davBtn) {
      davBtn.addEventListener('click', function () {
        if (_currentNode && NS.DataAccessView) {
          NS.DataAccessView.addNode(_currentNode);
          if (NS.ContentPanel) {
            NS.ContentPanel.switchToTab('dav');
            NS.ContentPanel.updateDAVBadge();
          }
        }
      });
    }
    const cb = _container.querySelector('.opcua-detail-autorefresh-cb');
    if (cb) {
      cb.addEventListener('change', function () {
        _autoRefreshEnabled = this.checked;
        if (_autoRefreshEnabled) {
          startAutoRefresh();
        } else {
          stopAutoRefresh();
        }
      });
    }
  }

  function renderValueSection() {
    const n = _currentNode;
    if (!n._readResult && !n._readError && !n._reading) {
      return '<div class="opcua-detail-placeholder">Click "Read" or select a Variable node</div>';
    }
    if (n._reading) {
      return '<div class="opcua-detail-loading"><span class="opcua-spinner"></span> Reading...</div>';
    }
    if (n._readError) {
      return '<div class="opcua-detail-error">' + escHtml(n._readError) + '</div>' +
        (n._readResult && n._readResult.inferredType
          ? '<div class="opcua-detail-type">Type: ' + escHtml(shortType(n._readResult.inferredType)) + '</div>'
          : '');
    }

    const r = n._readResult;
    let valHtml;
    if (Array.isArray(r.value)) {
      valHtml = '<div class="opcua-detail-array">' +
        r.value.map(function (v, i) { return '<div class="opcua-detail-array-item"><span class="opcua-detail-array-idx">[' + i + ']</span> ' + escHtml(String(v)) + '</div>'; }).join('') +
        '</div>';
    } else if (r.value != null) {
      valHtml = '<div class="opcua-detail-val">' + escHtml(String(r.value)) + '</div>';
    } else {
      valHtml = '<div class="opcua-detail-val opcua-detail-null">null</div>';
    }

    return valHtml +
      '<table class="opcua-detail-meta opcua-detail-timestamps">' +
        '<tr><td class="opcua-detail-label">Source Timestamp</td><td>' + escHtml(r.sourceTimestamp || '\u2014') + '</td></tr>' +
        '<tr><td class="opcua-detail-label">Server Timestamp</td><td>' + escHtml(r.serverTimestamp || '\u2014') + '</td></tr>' +
        '<tr><td class="opcua-detail-label">Status Code</td><td>' + (r.statusCode || 0) + '</td></tr>' +
        '<tr><td class="opcua-detail-label">Type</td><td>' + escHtml(shortType(r.inferredType)) + '</td></tr>' +
      '</table>';
  }

  async function readCurrentNode() {
    if (!_currentNode || _currentNode.nodeClass !== 'Variable') return;

    _currentNode._reading = true;
    _currentNode._readError = null;
    updateValueSection();

    try {
      const result = await NS.ApiClient.read(
        _currentNode.nodeNs,
        _currentNode.nodeId,
        _currentNode.nodeIdType
      );
      _currentNode._readResult = result;
      _currentNode._readError = result.readError || null;
    } catch (err) {
      _currentNode._readError = err.message;
    } finally {
      _currentNode._reading = false;
    }

    updateValueSection();
  }

  function updateValueSection() {
    if (!_container) return;
    const section = _container.querySelector('.opcua-detail-value-section');
    if (section) {
      section.innerHTML = renderValueSection();
    }
  }

  function startAutoRefresh() {
    stopAutoRefresh();
    const cfg = NS.ConfigPanel ? NS.ConfigPanel.getConfig() : {};
    const interval = (cfg.autoRefreshInterval || 5) * 1000;
    _autoRefreshTimer = setInterval(function () {
      if (_currentNode && _currentNode.nodeClass === 'Variable') {
        readCurrentNode();
      }
    }, interval);
  }

  function stopAutoRefresh() {
    if (_autoRefreshTimer) {
      clearInterval(_autoRefreshTimer);
      _autoRefreshTimer = null;
    }
  }

  function clear() {
    stopAutoRefresh();
    _currentNode = null;
    _autoRefreshEnabled = false;
    if (_container) {
      _container.innerHTML =
        '<div class="opcua-detail-empty">Select a node to view details</div>';
    }
  }

  // Helpers
  function escHtml(s) {
    var d = document.createElement('div');
    d.textContent = s;
    return d.innerHTML;
  }

  function nodeIdTypeLabel(t) {
    var m = { 0: 'Numeric', 3: 'String', 4: 'GUID', 5: 'ByteString' };
    return m[t] || 'Numeric';
  }

  function shortType(full) {
    if (!full) return 'Unknown';
    // "OPCUA.Types.StringDataValue" → "String"
    var match = full.match(/\.(\w+)DataValue$/);
    return match ? match[1] : full;
  }

  NS.NodeDetail = {
    createPanel: createPanel,
    showNode: showNode,
    clear: clear,
    stopAutoRefresh: stopAutoRefresh
  };
})();

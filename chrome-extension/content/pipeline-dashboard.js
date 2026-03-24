// pipeline-dashboard.js — Live dashboard showing deployed pipelines with flow visualization
(function () {
  'use strict';

  const NS = (window.__opcuaExt = window.__opcuaExt || {});

  let _container = null;
  let _refreshTimer = null;
  let _pipelines = [];
  let _visible = false;

  function createPanel() {
    if (_container) return _container;
    _container = document.createElement('div');
    _container.className = 'opcua-ext opcua-dashboard';
    renderEmpty();
    return _container;
  }

  function setVisible(vis) {
    _visible = vis;
    if (vis) {
      refresh();
      startAutoRefresh();
    } else {
      stopAutoRefresh();
    }
  }

  function startAutoRefresh() {
    stopAutoRefresh();
    _refreshTimer = setInterval(refresh, 5000);
  }

  function stopAutoRefresh() {
    if (_refreshTimer) {
      clearInterval(_refreshTimer);
      _refreshTimer = null;
    }
  }

  async function refresh() {
    if (!_container) return;
    try {
      _pipelines = await NS.ApiClient.listPipelines();
      console.log('[OPC UA Dashboard] Pipelines response:', JSON.stringify(_pipelines, null, 2));
      render();
    } catch (err) {
      console.error('[OPC UA Dashboard] Error loading pipelines:', err);
      renderError(err.message);
    }
  }

  // ============================================================
  // Rendering
  // ============================================================

  function render() {
    if (!_container) return;

    if (!_pipelines || _pipelines.length === 0) {
      renderEmpty();
      return;
    }

    _container.innerHTML = '';

    // Header
    var header = document.createElement('div');
    header.className = 'opcua-dash-header';
    header.innerHTML =
      '<span class="opcua-dash-title">Data Pipelines</span>' +
      '<span class="opcua-dash-count">' + _pipelines.length + ' pipeline' +
        (_pipelines.length !== 1 ? 's' : '') + '</span>';
    _container.appendChild(header);

    // Pipeline cards
    var list = document.createElement('div');
    list.className = 'opcua-dash-list';

    for (var i = 0; i < _pipelines.length; i++) {
      list.appendChild(renderPipelineCard(_pipelines[i]));
    }

    _container.appendChild(list);
  }

  function renderEmpty() {
    if (!_container) return;
    _container.innerHTML =
      '<div class="opcua-dash-empty">' +
        '<div class="opcua-dash-empty-icon">\uD83D\uDD0C</div>' +
        '<div class="opcua-dash-empty-title">No Pipelines Yet</div>' +
        '<div class="opcua-dash-empty-hint">Use the Pipeline Wizard tab to create<br>your first data pipeline.</div>' +
      '</div>';
  }

  function renderError(msg) {
    if (!_container) return;
    _container.innerHTML =
      '<div class="opcua-dash-empty">' +
        '<div class="opcua-dash-empty-icon">\u26A0\uFE0F</div>' +
        '<div class="opcua-dash-empty-title">Error Loading Pipelines</div>' +
        '<div class="opcua-dash-empty-hint">' + escHtml(msg) + '</div>' +
      '</div>';
  }

  function renderPipelineCard(p) {
    var card = document.createElement('div');
    card.className = 'opcua-dash-card' + (p.running ? ' opcua-dash-card-active' : '');

    // Status bar
    var statusBar = document.createElement('div');
    statusBar.className = 'opcua-dash-status-bar';

    var statusDot = document.createElement('span');
    statusDot.className = 'opcua-dash-dot' + (p.running ? ' opcua-dash-dot-on' : '');
    statusBar.appendChild(statusDot);

    var statusText = document.createElement('span');
    statusText.className = 'opcua-dash-status-text';
    statusText.textContent = p.running ? 'Running' : 'Stopped';
    statusBar.appendChild(statusText);

    var modeBadge = document.createElement('span');
    modeBadge.className = 'opcua-dash-mode';
    modeBadge.textContent = p.mode === 'subscription' ? 'Subscription' : 'Polling';
    statusBar.appendChild(modeBadge);

    var spacer = document.createElement('span');
    spacer.style.flex = '1';
    statusBar.appendChild(spacer);

    // Controls
    var toggleBtn = document.createElement('button');
    toggleBtn.className = 'opcua-btn opcua-btn-secondary opcua-dash-ctrl-btn';
    toggleBtn.textContent = p.running ? '\u23F8 Pause' : '\u25B6 Start';
    toggleBtn.title = p.running ? 'Stop this pipeline' : 'Start this pipeline';
    toggleBtn.addEventListener('click', function () { togglePipeline(p.name); });
    statusBar.appendChild(toggleBtn);

    var deleteBtn = document.createElement('button');
    deleteBtn.className = 'opcua-btn opcua-dash-ctrl-btn opcua-dash-delete-btn';
    deleteBtn.textContent = '\uD83D\uDDD1';
    deleteBtn.title = 'Delete pipeline';
    deleteBtn.addEventListener('click', function () { deletePipeline(p.name); });
    statusBar.appendChild(deleteBtn);

    card.appendChild(statusBar);

    // Flow visualization
    var flow = document.createElement('div');
    flow.className = 'opcua-dash-flow';

    // Nodes box
    var nodesBox = document.createElement('div');
    nodesBox.className = 'opcua-dash-flow-box opcua-dash-flow-nodes';
    var nodeCount = p.nodes ? p.nodes.length : 0;
    var nodeListHTML = '';
    if (p.nodes) {
      var maxShow = 4;
      for (var i = 0; i < Math.min(p.nodes.length, maxShow); i++) {
        nodeListHTML += '<div class="opcua-dash-node-item">\uD83D\uDCCA ' + escHtml(p.nodes[i].property) + '</div>';
      }
      if (p.nodes.length > maxShow) {
        nodeListHTML += '<div class="opcua-dash-node-more">+' + (p.nodes.length - maxShow) + ' more</div>';
      }
    }
    nodesBox.innerHTML =
      '<div class="opcua-dash-flow-label">Nodes</div>' +
      '<div class="opcua-dash-flow-count">' + nodeCount + '</div>' +
      nodeListHTML;
    flow.appendChild(nodesBox);

    // Arrow 1
    var arrow1 = document.createElement('div');
    arrow1.className = 'opcua-dash-flow-arrow' + (p.running ? ' opcua-dash-flow-arrow-active' : '');
    arrow1.innerHTML = '<div class="opcua-dash-flow-arrow-line"></div><div class="opcua-dash-flow-arrow-head">\u25B6</div>';
    if (p.running) {
      var dot1 = document.createElement('div');
      dot1.className = 'opcua-dash-flow-dot';
      dot1.innerHTML = '<span></span>';
      arrow1.appendChild(dot1);
    }
    flow.appendChild(arrow1);

    // Service box
    var svcBox = document.createElement('div');
    svcBox.className = 'opcua-dash-flow-box opcua-dash-flow-service';
    var intervalText = '';
    if (p.mode === 'polling' && p.callInterval) {
      intervalText = 'every ' + p.callInterval + 's';
    } else if (p.mode === 'subscription' && p.publishingInterval) {
      intervalText = p.publishingInterval + 'ms';
    }
    svcBox.innerHTML =
      '<div class="opcua-dash-flow-label">Service</div>' +
      '<div class="opcua-dash-svc-name">' + escHtml(p.name) + '</div>' +
      (intervalText ? '<div class="opcua-dash-svc-interval">' + intervalText + '</div>' : '');
    flow.appendChild(svcBox);

    // Arrow 2
    var arrow2 = document.createElement('div');
    arrow2.className = 'opcua-dash-flow-arrow' + (p.running ? ' opcua-dash-flow-arrow-active' : '');
    arrow2.innerHTML = '<div class="opcua-dash-flow-arrow-line"></div><div class="opcua-dash-flow-arrow-head">\u25B6</div>';
    if (p.running) {
      var dot2 = document.createElement('div');
      dot2.className = 'opcua-dash-flow-dot';
      dot2.innerHTML = '<span></span>';
      arrow2.appendChild(dot2);
    }
    flow.appendChild(arrow2);

    // Table box
    var tableBox = document.createElement('div');
    tableBox.className = 'opcua-dash-flow-box opcua-dash-flow-table';
    tableBox.innerHTML =
      '<div class="opcua-dash-flow-label">Table</div>' +
      '<div class="opcua-dash-table-name">' + escHtml(p.tableName || '') + '</div>' +
      '<div class="opcua-dash-row-count">' + (p.rowCount || 0) + ' rows</div>';
    flow.appendChild(tableBox);

    card.appendChild(flow);

    // Connection info footer
    var footer = document.createElement('div');
    footer.className = 'opcua-dash-card-footer';
    footer.innerHTML = '<span class="opcua-dash-url">\uD83C\uDF10 ' + escHtml(p.url || '') + '</span>';
    card.appendChild(footer);

    return card;
  }

  // ============================================================
  // Actions
  // ============================================================

  async function togglePipeline(name) {
    try {
      await NS.ApiClient.togglePipeline(name);
      await refresh();
    } catch (err) {
      alert('Failed to toggle pipeline: ' + err.message);
    }
  }

  async function deletePipeline(name) {
    if (!confirm('Delete pipeline "' + name + '"?\nThis will remove the service and its DataSource class.')) {
      return;
    }
    try {
      await NS.ApiClient.deletePipeline(name);
      await refresh();
    } catch (err) {
      alert('Failed to delete pipeline: ' + err.message);
    }
  }

  // ============================================================
  // Helpers
  // ============================================================

  function escHtml(s) {
    var d = document.createElement('div');
    d.textContent = s || '';
    return d.innerHTML;
  }

  // ============================================================
  // Export
  // ============================================================

  NS.PipelineDashboard = {
    createPanel: createPanel,
    setVisible: setVisible,
    refresh: refresh
  };
})();

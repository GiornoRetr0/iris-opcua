// content-panel.js — Swaps portal content area with OPC UA browser UI
(function () {
  'use strict';

  const NS = (window.__opcuaExt = window.__opcuaExt || {});

  let _panel = null;
  let _active = false;
  let _originalContent = null;
  let _hiddenElements = [];

  // SVG icon for the settings gear
  const GEAR_SVG = '<svg viewBox="0 0 20 20" width="16" height="16" fill="currentColor">' +
    '<path d="M11.49 3.17c-.38-1.56-2.6-1.56-2.98 0a1.532 1.532 0 01-2.286.948c-1.372-.836-2.942.734-2.106 2.106.54.886.062 2.042-.947 2.287-1.561.379-1.561 2.6 0 2.978a1.532 1.532 0 01.947 2.287c-.836 1.372.734 2.942 2.106 2.106a1.532 1.532 0 012.287.947c.379 1.561 2.6 1.561 2.978 0a1.533 1.533 0 012.287-.947c1.372.836 2.942-.734 2.106-2.106a1.533 1.533 0 01.947-2.287c1.561-.379 1.561-2.6 0-2.978a1.532 1.532 0 01-.947-2.287c.836-1.372-.734-2.942-2.106-2.106a1.532 1.532 0 01-2.287-.947zM10 13a3 3 0 100-6 3 3 0 000 6z"/>' +
    '</svg>';

  function createPanel() {
    if (_panel) return _panel;

    _panel = document.createElement('div');
    _panel.className = 'opcua-ext opcua-panel';
    _panel.id = 'opcua-panel';
    _panel.style.display = 'none';

    // Toolbar
    const toolbar = document.createElement('div');
    toolbar.className = 'opcua-toolbar';

    const title = document.createElement('span');
    title.className = 'opcua-toolbar-title';
    title.textContent = 'OPC UA Address Space';
    toolbar.appendChild(title);

    const statusBadge = document.createElement('span');
    statusBadge.className = 'opcua-toolbar-status';
    statusBadge.id = 'opcua-conn-status';
    statusBadge.textContent = 'Not connected';
    toolbar.appendChild(statusBadge);

    const spacer = document.createElement('span');
    spacer.className = 'opcua-toolbar-spacer';
    toolbar.appendChild(spacer);

    const refreshBtn = document.createElement('button');
    refreshBtn.className = 'opcua-toolbar-btn';
    refreshBtn.title = 'Refresh tree';
    refreshBtn.textContent = '\u21BB';
    refreshBtn.addEventListener('click', function () {
      if (NS.TreeBrowser) NS.TreeBrowser.loadRoot();
    });
    toolbar.appendChild(refreshBtn);

    const gearBtn = document.createElement('button');
    gearBtn.className = 'opcua-toolbar-btn';
    gearBtn.title = 'Settings';
    gearBtn.innerHTML = GEAR_SVG;
    gearBtn.addEventListener('click', function () {
      if (NS.ConfigPanel) NS.ConfigPanel.toggle();
    });
    toolbar.appendChild(gearBtn);

    _panel.appendChild(toolbar);

    // Config panel (overlay)
    const configPanel = NS.ConfigPanel ? NS.ConfigPanel.createPanel() : null;
    if (configPanel) {
      _panel.appendChild(configPanel);
    }

    // Split pane container
    const splitPane = document.createElement('div');
    splitPane.className = 'opcua-split';

    // Left: tree
    const leftPane = document.createElement('div');
    leftPane.className = 'opcua-split-left';
    const treePanel = NS.TreeBrowser ? NS.TreeBrowser.createPanel() : document.createElement('div');
    leftPane.appendChild(treePanel);
    splitPane.appendChild(leftPane);

    // Drag handle
    const handle = document.createElement('div');
    handle.className = 'opcua-split-handle';
    splitPane.appendChild(handle);

    // Right: tabs + content
    const rightPane = document.createElement('div');
    rightPane.className = 'opcua-split-right';

    // Tab bar for right pane
    const tabBar = document.createElement('div');
    tabBar.className = 'opcua-right-tabs';

    const detailTab = document.createElement('button');
    detailTab.className = 'opcua-right-tab opcua-right-tab-active';
    detailTab.dataset.tab = 'detail';
    detailTab.textContent = 'Node Detail';
    tabBar.appendChild(detailTab);

    const wizardTab = document.createElement('button');
    wizardTab.className = 'opcua-right-tab';
    wizardTab.dataset.tab = 'wizard';
    var badgeCount = NS.PipelineWizard ? NS.PipelineWizard.getSelectionCount() : 0;
    wizardTab.innerHTML = 'Pipeline Wizard <span class="opcua-wizard-badge" id="opcua-wizard-badge"' +
      (badgeCount === 0 ? ' style="display:none"' : '') + '>' + badgeCount + '</span>';
    tabBar.appendChild(wizardTab);

    const dashTab = document.createElement('button');
    dashTab.className = 'opcua-right-tab';
    dashTab.dataset.tab = 'dashboard';
    dashTab.textContent = 'Pipelines';
    tabBar.appendChild(dashTab);

    rightPane.appendChild(tabBar);

    // Detail panel content
    const detailContent = document.createElement('div');
    detailContent.className = 'opcua-tab-content';
    const detailPanel = NS.NodeDetail ? NS.NodeDetail.createPanel() : document.createElement('div');
    detailContent.appendChild(detailPanel);
    rightPane.appendChild(detailContent);

    // Wizard panel content
    const wizardContent = document.createElement('div');
    wizardContent.className = 'opcua-tab-content';
    wizardContent.style.display = 'none';
    const wizardPanel = NS.PipelineWizard ? NS.PipelineWizard.createPanel() : document.createElement('div');
    wizardContent.appendChild(wizardPanel);
    rightPane.appendChild(wizardContent);

    // Dashboard panel content
    const dashContent = document.createElement('div');
    dashContent.className = 'opcua-tab-content';
    dashContent.style.display = 'none';
    const dashPanel = NS.PipelineDashboard ? NS.PipelineDashboard.createPanel() : document.createElement('div');
    dashContent.appendChild(dashPanel);
    rightPane.appendChild(dashContent);

    // Tab switching
    var allTabs = [detailTab, wizardTab, dashTab];
    var allContents = { detail: detailContent, wizard: wizardContent, dashboard: dashContent };
    tabBar.addEventListener('click', function (e) {
      var tab = e.target.closest('.opcua-right-tab');
      if (!tab) return;
      var tabName = tab.dataset.tab;
      for (var t = 0; t < allTabs.length; t++) {
        allTabs[t].classList.toggle('opcua-right-tab-active', allTabs[t].dataset.tab === tabName);
      }
      for (var key in allContents) {
        allContents[key].style.display = key === tabName ? '' : 'none';
      }
      // Notify dashboard of visibility
      if (NS.PipelineDashboard) {
        NS.PipelineDashboard.setVisible(tabName === 'dashboard');
      }
    });

    splitPane.appendChild(rightPane);

    _panel.appendChild(splitPane);

    // Split handle drag
    initSplitDrag(handle, leftPane, rightPane, splitPane);

    return _panel;
  }

  function initSplitDrag(handle, left, right, container) {
    let dragging = false;
    let startX, startLeftW;

    handle.addEventListener('mousedown', function (e) {
      e.preventDefault();
      dragging = true;
      startX = e.clientX;
      startLeftW = left.offsetWidth;
      document.body.style.cursor = 'col-resize';
      document.body.style.userSelect = 'none';
    });

    document.addEventListener('mousemove', function (e) {
      if (!dragging) return;
      const dx = e.clientX - startX;
      const newW = Math.max(180, Math.min(startLeftW + dx, container.offsetWidth - 200));
      left.style.width = newW + 'px';
      left.style.flex = 'none';
    });

    document.addEventListener('mouseup', function () {
      if (dragging) {
        dragging = false;
        document.body.style.cursor = '';
        document.body.style.userSelect = '';
      }
    });
  }

  /**
   * Find the main content area in the portal.
   * The portal uses Zen layout — the main content area is typically
   * in a table cell or div after the sidebar.
   */
  function getContentParent() {
    // Strategy: Find the element that contains the main page body.
    // In Zen portals, content is often in a TD next to the selector,
    // or in a specific div. Try several approaches.

    // Approach 1: The parent of #selector's table contains the content area
    var selector = document.getElementById('selector');
    if (selector) {
      // Walk up to the layout table
      var td = selector.closest('td');
      if (td && td.nextElementSibling) {
        return td.nextElementSibling;
      }
    }

    // Approach 2: Look for the standard Zen content area
    var zen = document.getElementById('zen23');
    if (zen) return zen.parentNode;

    // Approach 3: Look for areaBody class
    var body = document.querySelector('.areaBody');
    if (body) return body;

    // Fallback: body
    return document.body;
  }

  function activate() {
    if (_active) return;
    _active = true;

    var parent = getContentParent();

    // Hide existing children
    _hiddenElements = [];
    var children = parent.children;
    for (var i = 0; i < children.length; i++) {
      var child = children[i];
      if (child !== _panel && child.id !== 'opcua-panel') {
        _hiddenElements.push({ el: child, display: child.style.display });
        child.style.display = 'none';
      }
    }

    // Hide sibling TDs to the right (e.g. "System Information" panel)
    // and force the content cell to fill the remaining width
    if (parent.tagName === 'TD') {
      var sibling = parent.nextElementSibling;
      while (sibling) {
        _hiddenElements.push({ el: sibling, display: sibling.style.display });
        sibling.style.display = 'none';
        sibling = sibling.nextElementSibling;
      }
      _hiddenElements.push({ el: parent, prop: 'style.width', val: parent.style.width });
      parent.style.width = '100%';
    }

    // Insert or show our panel
    if (!_panel) createPanel();

    if (!_panel.parentNode) {
      parent.appendChild(_panel);
    }
    _panel.style.display = 'flex';

    // Load tree if server URL is set
    var cfg = NS.ConfigPanel ? NS.ConfigPanel.getConfig() : {};
    if (cfg.serverUrl) {
      updateConnectionStatus();
      if (NS.TreeBrowser) NS.TreeBrowser.loadRoot();
    } else {
      // Show config on first use
      if (NS.ConfigPanel) NS.ConfigPanel.show();
    }
  }

  function deactivate() {
    if (!_active) return;
    _active = false;

    // Hide our panel
    if (_panel) _panel.style.display = 'none';

    // Restore hidden elements and properties
    _hiddenElements.forEach(function (h) {
      if (h.prop === 'style.width') {
        h.el.style.width = h.val;
      } else if (h.prop) {
        h.el[h.prop] = h.val;
      } else {
        h.el.style.display = h.display;
      }
    });
    _hiddenElements = [];

    // Stop auto-refresh
    if (NS.NodeDetail) NS.NodeDetail.stopAutoRefresh();
  }

  function isActive() {
    return _active;
  }

  async function updateConnectionStatus() {
    var badge = document.getElementById('opcua-conn-status');
    if (!badge) return;

    try {
      await NS.ApiClient.ping();
      badge.textContent = 'API Online';
      badge.className = 'opcua-toolbar-status opcua-status-ok';
    } catch (err) {
      badge.textContent = 'API Offline';
      badge.className = 'opcua-toolbar-status opcua-status-err';
    }
  }

  function updateWizardBadge() {
    var badge = document.getElementById('opcua-wizard-badge');
    if (!badge) return;
    var count = NS.PipelineWizard ? NS.PipelineWizard.getSelectionCount() : 0;
    badge.textContent = count;
    badge.style.display = count > 0 ? 'inline-block' : 'none';
  }

  NS.ContentPanel = {
    createPanel: createPanel,
    activate: activate,
    deactivate: deactivate,
    isActive: isActive,
    updateConnectionStatus: updateConnectionStatus,
    updateWizardBadge: updateWizardBadge
  };
})();

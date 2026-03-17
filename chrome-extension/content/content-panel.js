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

    // Tab bar
    const tabBar = document.createElement('div');
    tabBar.className = 'opcua-tabs';

    const tabDetail = document.createElement('button');
    tabDetail.className = 'opcua-tab opcua-tab-active';
    tabDetail.dataset.tab = 'detail';
    tabDetail.textContent = 'Node Detail';
    tabBar.appendChild(tabDetail);

    const tabDAV = document.createElement('button');
    tabDAV.className = 'opcua-tab';
    tabDAV.dataset.tab = 'dav';
    tabDAV.innerHTML = 'Data Access View<span class="opcua-tab-badge opcua-dav-badge" style="display:none;">0</span>';
    tabBar.appendChild(tabDAV);

    rightPane.appendChild(tabBar);

    // Tab content: detail
    const detailContent = document.createElement('div');
    detailContent.className = 'opcua-tab-content';
    detailContent.dataset.tabContent = 'detail';
    const detailPanel = NS.NodeDetail ? NS.NodeDetail.createPanel() : document.createElement('div');
    detailContent.appendChild(detailPanel);
    rightPane.appendChild(detailContent);

    // Tab content: DAV
    const davContent = document.createElement('div');
    davContent.className = 'opcua-tab-content opcua-tab-content-hidden';
    davContent.dataset.tabContent = 'dav';
    const davPanel = NS.DataAccessView ? NS.DataAccessView.createPanel() : document.createElement('div');
    davContent.appendChild(davPanel);
    rightPane.appendChild(davContent);

    // Tab click handler
    tabBar.addEventListener('click', function (e) {
      var tab = e.target.closest('.opcua-tab');
      if (!tab) return;
      switchToTab(tab.dataset.tab);
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

  function switchToTab(tabName) {
    if (!_panel) return;
    // Update tab buttons
    var tabs = _panel.querySelectorAll('.opcua-tab');
    for (var i = 0; i < tabs.length; i++) {
      if (tabs[i].dataset.tab === tabName) {
        tabs[i].classList.add('opcua-tab-active');
      } else {
        tabs[i].classList.remove('opcua-tab-active');
      }
    }
    // Show/hide content
    var contents = _panel.querySelectorAll('.opcua-tab-content');
    for (var j = 0; j < contents.length; j++) {
      if (contents[j].dataset.tabContent === tabName) {
        contents[j].classList.remove('opcua-tab-content-hidden');
      } else {
        contents[j].classList.add('opcua-tab-content-hidden');
      }
    }
    // Notify DAV visibility
    if (NS.DataAccessView) {
      NS.DataAccessView.setVisible(tabName === 'dav');
    }
  }

  function updateDAVBadge() {
    if (!_panel) return;
    var badge = _panel.querySelector('.opcua-dav-badge');
    if (!badge) return;
    var count = NS.DataAccessView ? NS.DataAccessView.getNodeCount() : 0;
    if (count > 0) {
      badge.textContent = count;
      badge.style.display = 'inline-block';
    } else {
      badge.style.display = 'none';
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
    if (NS.DataAccessView) NS.DataAccessView.stopAutoRefresh();
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

  NS.ContentPanel = {
    createPanel: createPanel,
    activate: activate,
    deactivate: deactivate,
    isActive: isActive,
    updateConnectionStatus: updateConnectionStatus,
    switchToTab: switchToTab,
    updateDAVBadge: updateDAVBadge
  };
})();

// tree-browser.js — Lazy-loading OPC UA address space tree
(function () {
  'use strict';

  const NS = (window.__opcuaExt = window.__opcuaExt || {});

  // State: Map keyed by "ns:id:type" → {node, children, expanded, loaded, element}
  let _nodes = new Map();
  let _container = null;
  let _treeEl = null;
  let _selectedKey = null;

  function nodeKey(ns, id, idType) {
    return ns + ':' + id + ':' + (idType || 0);
  }

  function createPanel() {
    if (_container) return _container;

    _container = document.createElement('div');
    _container.className = 'opcua-ext opcua-tree';

    _treeEl = document.createElement('div');
    _treeEl.className = 'opcua-tree-list';
    _container.appendChild(_treeEl);

    return _container;
  }

  /** Initialize tree with root node and load its children */
  async function loadRoot() {
    if (!_treeEl) return;
    _nodes.clear();
    _selectedKey = null;
    _treeEl.innerHTML = '';

    const cfg = NS.ConfigPanel ? NS.ConfigPanel.getConfig() : {};
    const rootNs = cfg.rootNodeNs != null ? cfg.rootNodeNs : 0;
    const rootId = cfg.rootNodeId || '84';

    // Create a synthetic root entry
    const rootNode = {
      displayName: 'Objects',
      nodeNs: rootNs,
      nodeId: rootId,
      nodeIdType: 0,
      nodeCategory: 'folder',
      hasChildren: true
    };

    const key = nodeKey(rootNs, rootId, 0);
    const entry = {
      node: rootNode,
      children: [],
      expanded: false,
      loaded: false,
      element: null,
      depth: 0
    };
    _nodes.set(key, entry);

    const el = renderNode(entry, 0);
    _treeEl.appendChild(el);

    // Auto-expand root
    await toggleNode(key);
  }

  // Node category icons and CSS classes
  var CATEGORY_ICONS = {
    folder:   '\uD83D\uDCC1',  // folder
    object:   '\uD83D\uDCE6',  // package/box
    variable: '\uD83D\uDCCA',  // bar chart (data point)
    property: '\uD83D\uDD27'   // wrench (metadata)
  };

  function renderNode(entry, depth) {
    const n = entry.node;
    const key = nodeKey(n.nodeNs, n.nodeId, n.nodeIdType);
    const cat = n.nodeCategory || 'object';
    const expandable = n.hasChildren !== false;

    const row = document.createElement('div');
    row.className = 'opcua-tree-item opcua-tree-cat-' + cat;
    row.dataset.key = key;
    if (_selectedKey === key) row.classList.add('opcua-tree-selected');

    // Indent
    row.style.paddingLeft = (12 + depth * 18) + 'px';

    // Checkbox for variable nodes (pipeline selection)
    if (cat === 'variable' && NS.PipelineWizard) {
      const cb = document.createElement('input');
      cb.type = 'checkbox';
      cb.className = 'opcua-tree-checkbox';
      cb.checked = NS.PipelineWizard.isNodeSelected(key);
      cb.addEventListener('click', function (e) { e.stopPropagation(); });
      cb.addEventListener('change', function () {
        if (this.checked) {
          NS.PipelineWizard.addNode(n);
        } else {
          NS.PipelineWizard.removeNode(key);
        }
      });
      row.appendChild(cb);
    }

    // Toggle arrow
    const arrow = document.createElement('span');
    arrow.className = 'opcua-tree-arrow';
    if (expandable) {
      arrow.textContent = entry.expanded ? '\u25BE' : '\u25B8';
      arrow.classList.add('opcua-tree-arrow-active');
    } else {
      arrow.textContent = ' ';
    }
    row.appendChild(arrow);

    // Icon — category-based
    const icon = document.createElement('span');
    icon.className = 'opcua-tree-icon';
    icon.textContent = CATEGORY_ICONS[cat] || CATEGORY_ICONS.object;
    row.appendChild(icon);

    // Label
    const label = document.createElement('span');
    label.className = 'opcua-tree-label';
    label.textContent = n.displayName;
    label.title = 'ns=' + n.nodeNs + '; id=' + n.nodeId +
      (n.referenceType ? ' (' + n.referenceType + ')' : '');
    row.appendChild(label);

    // Click: toggle on arrow, select on label
    arrow.addEventListener('click', function (e) {
      e.stopPropagation();
      if (expandable) toggleNode(key);
    });

    row.addEventListener('click', function (e) {
      e.stopPropagation();
      selectNode(key);
    });

    row.addEventListener('dblclick', function (e) {
      e.stopPropagation();
      if (expandable) toggleNode(key);
    });

    entry.element = row;
    entry.depth = depth;

    return row;
  }

  async function toggleNode(key) {
    const entry = _nodes.get(key);
    if (!entry) return;

    if (entry.expanded) {
      // Collapse: remove children DOM
      collapseNode(key);
    } else {
      // Expand: load children if not yet loaded
      if (!entry.loaded) {
        await loadChildren(key);
      }
      expandNode(key);
    }
  }

  async function loadChildren(key) {
    const entry = _nodes.get(key);
    if (!entry) return;
    const n = entry.node;

    // Show loading indicator
    const loadingEl = document.createElement('div');
    loadingEl.className = 'opcua-tree-loading';
    loadingEl.style.paddingLeft = (12 + (entry.depth + 1) * 18) + 'px';
    loadingEl.innerHTML = '<span class="opcua-spinner"></span> Loading...';

    if (entry.element && entry.element.nextSibling) {
      entry.element.parentNode.insertBefore(loadingEl, entry.element.nextSibling);
    } else if (entry.element && entry.element.parentNode) {
      entry.element.parentNode.appendChild(loadingEl);
    }

    try {
      const children = await NS.ApiClient.browse(n.nodeNs, n.nodeId, n.nodeIdType);
      entry.children = Array.isArray(children) ? children : [];
      entry.loaded = true;

      // Register child entries
      entry.children.forEach(function (child) {
        const ck = nodeKey(child.nodeNs, child.nodeId, child.nodeIdType);
        if (!_nodes.has(ck)) {
          _nodes.set(ck, {
            node: child,
            children: [],
            expanded: false,
            loaded: false,
            element: null,
            depth: entry.depth + 1
          });
        }
      });
    } catch (err) {
      entry.children = [];
      entry.loaded = false;

      // Show error inline
      const errEl = document.createElement('div');
      errEl.className = 'opcua-tree-error';
      errEl.style.paddingLeft = (12 + (entry.depth + 1) * 18) + 'px';
      errEl.innerHTML = '<span class="opcua-tree-error-text">' + escHtml(err.message) + '</span> ' +
        '<a href="#" class="opcua-tree-retry">Retry</a>';
      errEl.querySelector('.opcua-tree-retry').addEventListener('click', function (e) {
        e.preventDefault();
        errEl.remove();
        toggleNode(key);
      });

      loadingEl.replaceWith(errEl);
      return;
    }

    loadingEl.remove();
  }

  function expandNode(key) {
    const entry = _nodes.get(key);
    if (!entry || entry.expanded) return;

    entry.expanded = true;

    // Update arrow
    const arrow = entry.element.querySelector('.opcua-tree-arrow');
    if (arrow && arrow.classList.contains('opcua-tree-arrow-active')) {
      arrow.textContent = '\u25BE';
    }

    // Insert child elements after parent
    let insertAfter = entry.element;
    entry.children.forEach(function (child) {
      const ck = nodeKey(child.nodeNs, child.nodeId, child.nodeIdType);
      const childEntry = _nodes.get(ck);
      if (childEntry) {
        const el = renderNode(childEntry, entry.depth + 1);
        insertAfter.parentNode.insertBefore(el, insertAfter.nextSibling);
        insertAfter = el;
      }
    });
  }

  function collapseNode(key) {
    const entry = _nodes.get(key);
    if (!entry || !entry.expanded) return;

    entry.expanded = false;

    // Update arrow
    const arrow = entry.element.querySelector('.opcua-tree-arrow');
    if (arrow && arrow.classList.contains('opcua-tree-arrow-active')) {
      arrow.textContent = '\u25B8';
    }

    // Remove all descendant elements
    removeDescendantElements(key);
  }

  function removeDescendantElements(key) {
    const entry = _nodes.get(key);
    if (!entry) return;

    entry.children.forEach(function (child) {
      const ck = nodeKey(child.nodeNs, child.nodeId, child.nodeIdType);
      const childEntry = _nodes.get(ck);
      if (childEntry) {
        // Recursively collapse
        if (childEntry.expanded) {
          removeDescendantElements(ck);
          childEntry.expanded = false;
        }
        if (childEntry.element && childEntry.element.parentNode) {
          childEntry.element.remove();
          childEntry.element = null;
        }
      }
    });
  }

  function selectNode(key) {
    // Deselect previous
    if (_selectedKey) {
      const prev = _nodes.get(_selectedKey);
      if (prev && prev.element) {
        prev.element.classList.remove('opcua-tree-selected');
      }
    }

    _selectedKey = key;
    const entry = _nodes.get(key);
    if (entry && entry.element) {
      entry.element.classList.add('opcua-tree-selected');
    }

    // Notify detail panel
    if (entry && NS.NodeDetail) {
      NS.NodeDetail.showNode(entry.node);
    }
  }

  function clear() {
    _nodes.clear();
    _selectedKey = null;
    if (_treeEl) _treeEl.innerHTML = '';
  }

  function escHtml(s) {
    var d = document.createElement('div');
    d.textContent = s;
    return d.innerHTML;
  }

  function uncheckNode(key) {
    var entry = _nodes.get(key);
    if (entry && entry.element) {
      var cb = entry.element.querySelector('.opcua-tree-checkbox');
      if (cb) cb.checked = false;
    }
  }

  NS.TreeBrowser = {
    createPanel: createPanel,
    loadRoot: loadRoot,
    clear: clear,
    uncheckNode: uncheckNode
  };
})();

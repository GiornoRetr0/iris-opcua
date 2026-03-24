// pipeline-wizard.js — Multi-step wizard for deploying OPC UA data pipelines
(function () {
  'use strict';

  const NS = (window.__opcuaExt = window.__opcuaExt || {});

  let _container = null;
  let _currentStep = 1;
  let _selectedNodes = new Map(); // key → {node, inferredType}
  let _inferredTypes = new Map(); // key → type string (after read)
  let _config = {};
  let _deployResult = null;

  const STEPS = [
    { num: 1, label: 'Select' },
    { num: 2, label: 'Review' },
    { num: 3, label: 'Configure' },
    { num: 4, label: 'Deploy' }
  ];

  var TYPE_OPTIONS = [
    { value: 'OPCUA.Types.IntegerDataValue', label: 'Integer' },
    { value: 'OPCUA.Types.DoubleDataValue', label: 'Double' },
    { value: 'OPCUA.Types.FloatDataValue', label: 'Float' },
    { value: 'OPCUA.Types.BooleanDataValue', label: 'Boolean' },
    { value: 'OPCUA.Types.StringDataValue', label: 'String' },
    { value: 'OPCUA.Types.TimeStampDataValue', label: 'TimeStamp' },
    { value: 'OPCUA.Types.ArrayDataValue.Integer', label: 'Array (Integer)' },
    { value: 'OPCUA.Types.ArrayDataValue.Double', label: 'Array (Double)' },
    { value: 'OPCUA.Types.ArrayDataValue.String', label: 'Array (String)' },
    { value: 'OPCUA.Types.ArrayDataValue.Boolean', label: 'Array (Boolean)' }
  ];

  function nodeKey(n) {
    return n.nodeNs + ':' + n.nodeId + ':' + (n.nodeIdType || 0);
  }

  // ============================================================
  // Public API
  // ============================================================

  function createPanel() {
    if (_container) return _container;
    _container = document.createElement('div');
    _container.className = 'opcua-ext opcua-wizard';
    renderCurrentStep();
    return _container;
  }

  function addNode(nodeData) {
    var key = nodeKey(nodeData);
    if (!_selectedNodes.has(key)) {
      _selectedNodes.set(key, { node: nodeData, inferredType: '' });
      onSelectionChanged();
    }
  }

  function removeNode(key) {
    _selectedNodes.delete(key);
    _inferredTypes.delete(key);
    onSelectionChanged();
    // Uncheck in tree
    if (NS.TreeBrowser && NS.TreeBrowser.uncheckNode) {
      NS.TreeBrowser.uncheckNode(key);
    }
  }

  function isNodeSelected(key) {
    return _selectedNodes.has(key);
  }

  function getSelectionCount() {
    return _selectedNodes.size;
  }

  function onSelectionChanged() {
    // Update badge
    if (NS.ContentPanel && NS.ContentPanel.updateWizardBadge) {
      NS.ContentPanel.updateWizardBadge();
    }
    // Re-render step 1 count if on step 1
    if (_currentStep === 1) renderCurrentStep();
  }

  // ============================================================
  // Rendering
  // ============================================================

  function renderCurrentStep() {
    if (!_container) return;
    _container.innerHTML = '';

    // Step indicator
    _container.appendChild(renderStepIndicator());

    // Body
    var body = document.createElement('div');
    body.className = 'opcua-wizard-body';

    var content = document.createElement('div');
    content.className = 'opcua-wizard-step-content';

    switch (_currentStep) {
      case 1: renderStep1(content); break;
      case 2: renderStep2(content); break;
      case 3: renderStep3(content); break;
      case 4: renderStep4(content); break;
    }

    body.appendChild(content);
    _container.appendChild(body);

    // Footer
    _container.appendChild(renderFooter());
  }

  function renderStepIndicator() {
    var bar = document.createElement('div');
    bar.className = 'opcua-wizard-steps';

    for (var i = 0; i < STEPS.length; i++) {
      var s = STEPS[i];

      // Circle + label wrapper
      var item = document.createElement('div');
      item.className = 'opcua-wizard-step-item';

      var circle = document.createElement('div');
      circle.className = 'opcua-wizard-step-circle';
      if (s.num < _currentStep) {
        circle.classList.add('completed');
        circle.innerHTML = '\u2713';
      } else if (s.num === _currentStep) {
        circle.classList.add('active');
        circle.textContent = s.num;
      } else {
        circle.textContent = s.num;
      }
      item.appendChild(circle);

      var label = document.createElement('div');
      label.className = 'opcua-wizard-step-label';
      if (s.num < _currentStep) label.classList.add('completed');
      if (s.num === _currentStep) label.classList.add('active');
      label.textContent = s.label;
      item.appendChild(label);

      bar.appendChild(item);

      // Connector line (not after last)
      if (i < STEPS.length - 1) {
        var line = document.createElement('div');
        line.className = 'opcua-wizard-step-line';
        if (s.num < _currentStep) line.classList.add('completed');
        bar.appendChild(line);
      }
    }

    return bar;
  }

  // ============================================================
  // Step 1 — Select Nodes
  // ============================================================

  function renderStep1(container) {
    var count = _selectedNodes.size;

    container.innerHTML =
      '<div class="opcua-wizard-select-msg">' +
        '<div class="opcua-wizard-select-icon">\uD83D\uDCCA</div>' +
        '<div class="opcua-wizard-select-title">Select Data Nodes</div>' +
        '<div class="opcua-wizard-select-hint">' +
          'Use the checkboxes in the tree on the left to select<br>' +
          'the variable nodes you want to monitor and store.' +
        '</div>' +
        '<div class="opcua-wizard-count">' +
          count + ' node' + (count !== 1 ? 's' : '') + ' selected' +
        '</div>' +
      '</div>';
  }

  // ============================================================
  // Step 2 — Review Selection
  // ============================================================

  function renderStep2(container) {
    var count = _selectedNodes.size;
    if (count === 0) {
      container.innerHTML =
        '<div class="opcua-wizard-select-msg">' +
          '<div class="opcua-wizard-select-hint">No nodes selected. Go back and select some.</div>' +
        '</div>';
      return;
    }

    // Progress bar for type inference
    var progressDiv = document.createElement('div');
    progressDiv.className = 'opcua-wizard-infer-progress';
    progressDiv.id = 'opcua-wizard-infer';
    progressDiv.innerHTML =
      '<span class="opcua-spinner"></span>' +
      '<span>Inferring types...</span>' +
      '<div class="opcua-wizard-infer-bar"><div class="opcua-wizard-infer-fill" style="width:0%"></div></div>';
    container.appendChild(progressDiv);

    // Table
    var table = document.createElement('table');
    table.className = 'opcua-wizard-node-table';
    table.innerHTML =
      '<thead><tr>' +
        '<th>Name</th>' +
        '<th>Node ID</th>' +
        '<th>NS</th>' +
        '<th>Type</th>' +
        '<th></th>' +
      '</tr></thead>';

    var tbody = document.createElement('tbody');
    tbody.id = 'opcua-wizard-review-tbody';

    _selectedNodes.forEach(function (entry, key) {
      var row = buildReviewRow(key, entry);
      tbody.appendChild(row);
    });

    table.appendChild(tbody);
    container.appendChild(table);

    // Start type inference
    inferTypes();
  }

  function buildReviewRow(key, entry) {
    var n = entry.node;
    var tr = document.createElement('tr');
    tr.dataset.key = key;

    // Name
    var tdName = document.createElement('td');
    tdName.textContent = n.displayName;
    tr.appendChild(tdName);

    // Node ID
    var tdId = document.createElement('td');
    tdId.className = 'opcua-mono';
    tdId.textContent = n.nodeId;
    tr.appendChild(tdId);

    // Namespace
    var tdNs = document.createElement('td');
    tdNs.textContent = n.nodeNs;
    tr.appendChild(tdNs);

    // Type dropdown
    var tdType = document.createElement('td');
    var sel = document.createElement('select');
    sel.className = 'opcua-wizard-type-select';
    sel.dataset.key = key;
    for (var i = 0; i < TYPE_OPTIONS.length; i++) {
      var opt = document.createElement('option');
      opt.value = TYPE_OPTIONS[i].value;
      opt.textContent = TYPE_OPTIONS[i].label;
      if (entry.inferredType === TYPE_OPTIONS[i].value) opt.selected = true;
      sel.appendChild(opt);
    }
    // Default to String if no type inferred yet
    if (!entry.inferredType) sel.value = 'OPCUA.Types.StringDataValue';
    sel.addEventListener('change', function () {
      var e = _selectedNodes.get(this.dataset.key);
      if (e) e.inferredType = this.value;
    });
    tdType.appendChild(sel);
    tr.appendChild(tdType);

    // Remove button
    var tdRemove = document.createElement('td');
    var btn = document.createElement('button');
    btn.className = 'opcua-wizard-remove-btn';
    btn.textContent = '\u00D7';
    btn.title = 'Remove';
    btn.dataset.key = key;
    btn.addEventListener('click', function () {
      removeNode(this.dataset.key);
      var row = this.closest('tr');
      if (row) row.remove();
    });
    tdRemove.appendChild(btn);
    tr.appendChild(tdRemove);

    return tr;
  }

  async function inferTypes() {
    var entries = Array.from(_selectedNodes.entries());
    var total = entries.length;
    var done = 0;

    for (var i = 0; i < entries.length; i++) {
      var key = entries[i][0];
      var entry = entries[i][1];
      var n = entry.node;

      // Skip if already inferred
      if (_inferredTypes.has(key)) {
        entry.inferredType = _inferredTypes.get(key);
        updateTypeDropdown(key, entry.inferredType);
        done++;
        updateInferProgress(done, total);
        continue;
      }

      try {
        var result = await NS.ApiClient.read(n.nodeNs, n.nodeId, n.nodeIdType);
        var type = (result && result.inferredType) || 'OPCUA.Types.StringDataValue';
        entry.inferredType = type;
        _inferredTypes.set(key, type);
        updateTypeDropdown(key, type);
      } catch (err) {
        entry.inferredType = 'OPCUA.Types.StringDataValue';
      }

      done++;
      updateInferProgress(done, total);
    }

    // Hide progress
    var prog = document.getElementById('opcua-wizard-infer');
    if (prog) prog.style.display = 'none';
  }

  function updateTypeDropdown(key, type) {
    var sel = _container ? _container.querySelector('select[data-key="' + key + '"]') : null;
    if (sel) sel.value = type;
  }

  function updateInferProgress(done, total) {
    var prog = document.getElementById('opcua-wizard-infer');
    if (!prog) return;
    var pct = Math.round((done / total) * 100);
    var fill = prog.querySelector('.opcua-wizard-infer-fill');
    if (fill) fill.style.width = pct + '%';
    if (done >= total) {
      prog.innerHTML = '<span style="color:rgb(0,137,132);">\u2713 Types inferred</span>';
      setTimeout(function () { if (prog.parentNode) prog.style.display = 'none'; }, 800);
    }
  }

  // ============================================================
  // Step 3 — Configure Pipeline
  // ============================================================

  function renderStep3(container) {
    var cfg = NS.ConfigPanel ? NS.ConfigPanel.getConfig() : {};
    var hostHint = '';
    try {
      var url = cfg.serverUrl || '';
      var match = url.match(/:\/\/([^:/]+)/);
      hostHint = match ? match[1].replace(/[^a-zA-Z0-9]/g, '') : '';
    } catch (e) {}
    if (!hostHint) hostHint = 'OPCUAData';
    // Capitalize first letter
    hostHint = hostHint.charAt(0).toUpperCase() + hostHint.slice(1);

    container.innerHTML =
      '<div class="opcua-wizard-form">' +

        // Connection summary
        '<div class="opcua-wizard-section-title">Connection</div>' +
        '<div class="opcua-wizard-conn-summary">' +
          '<strong>Server:</strong> ' + escHtml(cfg.serverUrl || 'Not configured') + '<br>' +
          '<strong>Security:</strong> ' + (cfg.securityMode === 3 ? 'Sign & Encrypt' : 'None') +
        '</div>' +

        // Class settings
        '<div class="opcua-wizard-section-title">DataSource Class</div>' +
        '<div class="opcua-config-group">' +
          '<label>Package</label>' +
          '<input type="text" id="wiz-package" value="Generated" placeholder="e.g. Generated">' +
        '</div>' +
        '<div class="opcua-config-group">' +
          '<label>Class Name</label>' +
          '<input type="text" id="wiz-classname" value="' + escHtml(hostHint) + 'DataSource" placeholder="e.g. PLCDataSource">' +
        '</div>' +
        '<div class="opcua-config-group">' +
          '<label>Data Source Name</label>' +
          '<input type="text" id="wiz-dsname" value="' + escHtml(hostHint) + '" placeholder="e.g. PLCData">' +
        '</div>' +

        // Pipeline mode
        '<div class="opcua-wizard-section-title">Pipeline Mode</div>' +
        '<div class="opcua-config-group">' +
          '<div class="opcua-wizard-radio-group">' +
            '<label><input type="radio" name="wiz-mode" value="polling" checked> Polling</label>' +
            '<label><input type="radio" name="wiz-mode" value="subscription"> Subscription</label>' +
          '</div>' +
          '<div id="wiz-mode-settings" class="opcua-wizard-mode-settings">' +
            '<div class="opcua-config-group">' +
              '<label>Poll Interval (seconds)</label>' +
              '<input type="number" id="wiz-interval" value="5" min="1">' +
            '</div>' +
          '</div>' +
        '</div>' +

        // Deploy options
        '<div class="opcua-wizard-section-title">Deploy</div>' +
        '<div class="opcua-wizard-checkbox-row">' +
          '<input type="checkbox" id="wiz-autostart" checked>' +
          '<label for="wiz-autostart">Start pipeline after deploy</label>' +
        '</div>' +

      '</div>';

    // Wire mode radio change
    var radios = container.querySelectorAll('input[name="wiz-mode"]');
    for (var i = 0; i < radios.length; i++) {
      radios[i].addEventListener('change', function () {
        updateModeSettings(this.value);
      });
    }

  }

  function updateModeSettings(mode) {
    var el = document.getElementById('wiz-mode-settings');
    if (!el) return;

    if (mode === 'subscription') {
      el.innerHTML =
        '<div class="opcua-config-group">' +
          '<label>Publishing Interval (ms)</label>' +
          '<input type="number" id="wiz-pub-interval" value="1000" min="1">' +
        '</div>' +
        '<div class="opcua-config-group">' +
          '<label>Sampling Interval (ms)</label>' +
          '<input type="number" id="wiz-samp-interval" value="0" min="0">' +
        '</div>' +
        '<div class="opcua-config-group">' +
          '<label>Queue Size</label>' +
          '<input type="number" id="wiz-queue-size" value="5" min="1">' +
        '</div>';
    } else {
      el.innerHTML =
        '<div class="opcua-config-group">' +
          '<label>Poll Interval (seconds)</label>' +
          '<input type="number" id="wiz-interval" value="5" min="1">' +
        '</div>';
    }
  }

  function gatherConfig() {
    var pkg = (document.getElementById('wiz-package') || {}).value || '';
    var cls = (document.getElementById('wiz-classname') || {}).value || '';
    var dsName = (document.getElementById('wiz-dsname') || {}).value || '';
    var autostart = (document.getElementById('wiz-autostart') || {}).checked !== false;

    var modeRadio = document.querySelector('input[name="wiz-mode"]:checked');
    var mode = modeRadio ? modeRadio.value : 'polling';

    var className = pkg ? pkg + '.' + cls : cls;

    var config = {
      className: className,
      dataSourceName: dsName || cls,
      mode: mode,
      enableOnDeploy: autostart
    };

    if (mode === 'polling') {
      config.callInterval = +((document.getElementById('wiz-interval') || {}).value || 5);
    } else {
      config.publishingInterval = +((document.getElementById('wiz-pub-interval') || {}).value || 1000);
      config.samplingInterval = +((document.getElementById('wiz-samp-interval') || {}).value || 0);
      config.queueSize = +((document.getElementById('wiz-queue-size') || {}).value || 5);
    }

    return config;
  }

  // ============================================================
  // Step 4 — Deploy
  // ============================================================

  function renderStep4(container) {
    if (_deployResult) {
      renderDeployResult(container);
      return;
    }

    container.innerHTML =
      '<div class="opcua-wizard-deploy-status">' +
        '<div class="opcua-wizard-deploy-spinner"></div>' +
        '<div class="opcua-wizard-deploy-msg">Generating classes and starting production...</div>' +
      '</div>';

    // Fire deploy
    doDeploy();
  }

  async function doDeploy() {
    try {
      // Build nodes array
      var nodes = [];
      _selectedNodes.forEach(function (entry) {
        var n = entry.node;
        nodes.push({
          nodeNs: n.nodeNs,
          nodeId: String(n.nodeId),
          nodeIdType: n.nodeIdType,
          displayName: n.displayName,
          inferredType: entry.inferredType || 'OPCUA.Types.StringDataValue'
        });
      });

      var params = Object.assign({ nodes: nodes }, _config);

      _deployResult = await NS.ApiClient.deploy(params);
    } catch (err) {
      _deployResult = { error: err.message, deployed: false, compiled: false, started: false };
    }

    // Re-render step 4 with result
    var body = _container ? _container.querySelector('.opcua-wizard-body') : null;
    if (body) {
      var content = document.createElement('div');
      content.className = 'opcua-wizard-step-content';
      renderDeployResult(content);
      body.innerHTML = '';
      body.appendChild(content);
    }
    // Update footer (hide back button on result)
    var footer = _container ? _container.querySelector('.opcua-wizard-footer') : null;
    if (footer) footer.replaceWith(renderFooter());
  }

  function renderDeployResult(container) {
    var r = _deployResult;
    if (!r) return;

    if (r.error && !r.compiled) {
      container.innerHTML =
        '<div class="opcua-wizard-error">' +
          '<div class="opcua-wizard-error-icon">\u26A0\uFE0F</div>' +
          '<div class="opcua-wizard-error-title">Deployment Failed</div>' +
          '<div class="opcua-wizard-error-msg">' + escHtml(r.error) + '</div>' +
        '</div>';
    } else if (r.compiled && r.error) {
      // Compiled but not started
      container.innerHTML =
        '<div class="opcua-wizard-success">' +
          '<div class="opcua-wizard-success-icon">\u2705</div>' +
          '<div class="opcua-wizard-success-title">Classes Deployed</div>' +
          '<dl class="opcua-wizard-success-detail">' +
            '<dt>DataSource Class</dt><dd>' + escHtml(r.dataSourceClass || '') + '</dd>' +
            '<dt>Production Class</dt><dd>' + escHtml(r.productionClass || '') + '</dd>' +
            '<dt>SQL Table</dt><dd>' + escHtml(r.tableName || '') + '</dd>' +
          '</dl>' +
        '</div>' +
        '<div class="opcua-wizard-error" style="margin-top:8px;">' +
          '<div class="opcua-wizard-error-title" style="font-size:13px;">Production Not Started</div>' +
          '<div class="opcua-wizard-error-msg">' + escHtml(r.error) + '</div>' +
        '</div>';
    } else {
      container.innerHTML =
        '<div class="opcua-wizard-success">' +
          '<div class="opcua-wizard-success-icon">\uD83D\uDE80</div>' +
          '<div class="opcua-wizard-success-title">Pipeline Running!</div>' +
          '<dl class="opcua-wizard-success-detail">' +
            '<dt>DataSource Class</dt><dd>' + escHtml(r.dataSourceClass || '') + '</dd>' +
            '<dt>Production Class</dt><dd>' + escHtml(r.productionClass || '') + '</dd>' +
            '<dt>SQL Table</dt><dd>' + escHtml(r.tableName || '') + '</dd>' +
            '<dt>Service</dt><dd>' + escHtml(r.serviceItemName || '') + '</dd>' +
            '<dt>Status</dt><dd style="color:#155724;font-weight:bold;">Active</dd>' +
          '</dl>' +
        '</div>';
    }
  }

  // ============================================================
  // Footer
  // ============================================================

  function renderFooter() {
    var footer = document.createElement('div');
    footer.className = 'opcua-wizard-footer';

    var left = document.createElement('div');
    var right = document.createElement('div');
    right.className = 'opcua-wizard-footer-right';

    if (_currentStep > 1 && _currentStep < 4) {
      var backBtn = document.createElement('button');
      backBtn.className = 'opcua-btn opcua-btn-secondary';
      backBtn.textContent = '\u2190 Back';
      backBtn.addEventListener('click', function () {
        _currentStep--;
        renderCurrentStep();
      });
      left.appendChild(backBtn);
    }

    if (_currentStep === 4 && _deployResult) {
      var newBtn = document.createElement('button');
      newBtn.className = 'opcua-btn opcua-btn-secondary';
      newBtn.textContent = 'New Pipeline';
      newBtn.addEventListener('click', function () {
        _selectedNodes.clear();
        _inferredTypes.clear();
        _config = {};
        _deployResult = null;
        _currentStep = 1;
        onSelectionChanged();
        renderCurrentStep();
      });
      left.appendChild(newBtn);
    }

    if (_currentStep === 1) {
      var nextBtn = document.createElement('button');
      nextBtn.className = 'opcua-btn opcua-btn-primary';
      nextBtn.textContent = 'Review Selection \u2192';
      nextBtn.disabled = _selectedNodes.size === 0;
      nextBtn.addEventListener('click', function () {
        _currentStep = 2;
        renderCurrentStep();
      });
      right.appendChild(nextBtn);
    } else if (_currentStep === 2) {
      var nextBtn2 = document.createElement('button');
      nextBtn2.className = 'opcua-btn opcua-btn-primary';
      nextBtn2.textContent = 'Configure \u2192';
      nextBtn2.disabled = _selectedNodes.size === 0;
      nextBtn2.addEventListener('click', function () {
        _currentStep = 3;
        renderCurrentStep();
      });
      right.appendChild(nextBtn2);
    } else if (_currentStep === 3) {
      var deployBtn = document.createElement('button');
      deployBtn.className = 'opcua-btn opcua-btn-success';
      deployBtn.textContent = '\uD83D\uDE80 Deploy Pipeline';
      deployBtn.addEventListener('click', function () {
        _config = gatherConfig();
        if (!_config.className) { alert('Please enter a class name.'); return; }
        _deployResult = null;
        _currentStep = 4;
        renderCurrentStep();
      });
      right.appendChild(deployBtn);
    }

    footer.appendChild(left);
    footer.appendChild(right);
    return footer;
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

  NS.PipelineWizard = {
    createPanel: createPanel,
    addNode: addNode,
    removeNode: removeNode,
    isNodeSelected: isNodeSelected,
    getSelectionCount: getSelectionCount
  };
})();

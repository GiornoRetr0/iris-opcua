// sidebar-injector.js — Injects "OPC UA" nav button into portal sidebar
(function () {
  'use strict';

  const NS = (window.__opcuaExt = window.__opcuaExt || {});

  // Inline SVG data URI for the nav icon (teal network/nodes icon)
  const ICON_SVG = 'data:image/svg+xml,' + encodeURIComponent(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" fill="none">' +
      '<circle cx="16" cy="8" r="4" fill="#008984"/>' +
      '<circle cx="8" cy="24" r="4" fill="#008984"/>' +
      '<circle cx="24" cy="24" r="4" fill="#008984"/>' +
      '<line x1="16" y1="12" x2="8" y2="20" stroke="#008984" stroke-width="2"/>' +
      '<line x1="16" y1="12" x2="24" y2="20" stroke="#008984" stroke-width="2"/>' +
    '</svg>'
  );

  let _injected = false;

  function inject() {
    if (_injected) return;
    // Remove stale element from previous extension load
    var stale = document.getElementById('cat_OPCUA');
    if (stale) stale.remove();

    var selector = document.getElementById('selector');
    if (!selector) return;

    // Build the nav item matching portal's exact structure
    var outer = document.createElement('div');
    outer.id = 'cat_OPCUA';
    outer.className = 'selectorOuter';

    var inner = document.createElement('div');
    inner.className = 'selectorInner';

    var link = document.createElement('a');
    link.href = 'javascript:void(0)';
    link.style.textDecoration = 'none';

    var table = document.createElement('table');
    table.setAttribute('border', '0');
    table.setAttribute('cellspacing', '0');
    table.setAttribute('cellpadding', '0');

    var tr = document.createElement('tr');

    // Icon cell
    var tdIcon = document.createElement('td');
    var img = document.createElement('img');
    img.className = 'selectorInnerIMG';
    img.src = ICON_SVG;
    img.style.width = '22px';
    img.style.height = '22px';
    img.style.verticalAlign = 'middle';
    tdIcon.appendChild(img);
    tr.appendChild(tdIcon);

    // Text cell
    var tdText = document.createElement('td');
    tdText.className = 'selectorInnerTD';
    var nobr = document.createElement('nobr');
    nobr.textContent = 'OPC UA';
    tdText.appendChild(nobr);
    tr.appendChild(tdText);

    table.appendChild(tr);
    link.appendChild(table);
    inner.appendChild(link);
    outer.appendChild(inner);

    // Insert after last nav item (typically #cat_SYSADM)
    selector.appendChild(outer);

    // Version marker for debugging
    outer.dataset.extVersion = '4';

    // Click handler for OPC UA nav item
    outer.addEventListener('click', function (e) {
      e.preventDefault();
      e.stopPropagation();

      // Deselect all other nav items.
      // Zen uses 'selectorOuterSelected' as a REPLACEMENT class (not a modifier),
      // so we must query both class names to find all items.
      var allItems = selector.querySelectorAll('.selectorOuter, .selectorOuterSelected');
      allItems.forEach(function (el) {
        if (el.id !== 'cat_OPCUA') {
          el.className = 'selectorOuter';
        }
      });

      // Select ours
      outer.className = 'selectorOuter selectorOuterSelected';

      // Activate content panel
      if (NS.ContentPanel) NS.ContentPanel.activate();
    });

    // Detect when Zen selects a different nav item by observing class changes.
    // Zen replaces the entire className: 'selectorOuter' ↔ 'selectorOuterSelected'.
    // We observe ALL direct children of #selector for class attribute mutations.
    var observer = new MutationObserver(function (mutations) {
      for (var i = 0; i < mutations.length; i++) {
        var m = mutations[i];
        if (m.type !== 'attributes' || m.attributeName !== 'class') continue;
        var target = m.target;
        if (target.id === 'cat_OPCUA') continue;
        // Check if a native nav item became selected
        if (target.className === 'selectorOuterSelected') {
          outer.className = 'selectorOuter';
          if (NS.ContentPanel) NS.ContentPanel.deactivate();
          return;
        }
      }
    });

    observer.observe(selector, { attributes: true, attributeFilter: ['class'], subtree: true });

    _injected = true;
  }

  function isInjected() {
    return _injected;
  }

  NS.SidebarInjector = {
    inject: inject,
    isInjected: isInjected
  };
})();

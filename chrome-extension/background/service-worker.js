// service-worker.js — Relay storage changes to content script tabs
chrome.storage.onChanged.addListener(function (changes, areaName) {
  if (areaName !== 'local') return;

  // Check if any changed key is a per-instance config key
  var configChanged = Object.keys(changes).some(function (key) {
    return key.indexOf('opcuaExtConfig::') === 0;
  });
  if (!configChanged) return;

  // Notify all tabs running the content script (any portal page)
  chrome.tabs.query({
    url: [
      'http://*/*/csp/sys/*',
      'https://*/*/csp/sys/*',
      'http://*/csp/sys/*',
      'https://*/csp/sys/*'
    ]
  }, function (tabs) {
    tabs.forEach(function (tab) {
      chrome.tabs.sendMessage(tab.id, {
        type: 'opcuaExtConfigChanged'
      }).catch(function () {
        // Tab may not have content script — ignore
      });
    });
  });
});

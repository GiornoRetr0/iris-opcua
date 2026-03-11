// service-worker.js — Relay storage changes to content script tabs
chrome.storage.onChanged.addListener(function (changes, areaName) {
  if (areaName !== 'local') return;
  if (!changes.opcuaExtConfig) return;

  // Notify all tabs running the content script
  chrome.tabs.query({ url: 'http://localhost/*/csp/sys/*' }, function (tabs) {
    tabs.forEach(function (tab) {
      chrome.tabs.sendMessage(tab.id, {
        type: 'opcuaExtConfigChanged',
        config: changes.opcuaExtConfig.newValue
      }).catch(function () {
        // Tab may not have content script — ignore
      });
    });
  });
});

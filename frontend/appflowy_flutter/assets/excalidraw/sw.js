/*
 * PonyNotes serves Excalidraw from a localhost asset server inside WebView.
 * Disable Workbox precaching so packaged builds do not keep stale global caches.
 */
self.addEventListener("install", () => {
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(self.registration.unregister().catch(() => undefined));
});

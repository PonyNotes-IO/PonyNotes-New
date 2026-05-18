/*
 * Legacy CRA service worker endpoint kept for old registrations.
 * It unregisters itself because desktop WebView should load only from the
 * in-process localhost asset server and HTTP cache headers.
 */
self.addEventListener("install", () => {
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(self.registration.unregister().catch(() => undefined));
});

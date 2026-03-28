/**
 * Shared Sentry initialization and error capture.
 * Used by both app.js and landing.js bundles.
 */

import * as Sentry from "@sentry/browser";

let initialized = false;

export function initSentry() {
  if (initialized) return;

  const sentryDsn = document.querySelector("meta[name='sentry-dsn']")?.getAttribute("content");
  if (!sentryDsn) return;

  Sentry.init({
    dsn: sentryDsn,
    environment: window.location.hostname === "localhost" ? "development" : "production",
    enabled: window.location.hostname !== "localhost",
    ignoreErrors: [
      "ResizeObserver loop",
      "Non-Error promise rejection",
      "WebSocket connection",
      "transport was disconnected",
    ],
  });

  initialized = true;
}

export function captureException(error, context) {
  if (context) {
    Sentry.withScope((scope) => {
      scope.setContext("details", context);
      Sentry.captureException(error);
    });
  } else {
    Sentry.captureException(error);
  }
}

export { Sentry };

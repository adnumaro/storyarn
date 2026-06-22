const eventPropertyAllowlist = new Map([
  [
    "asset uploaded",
    new Set([
      "asset_type",
      "content_type",
      "created_variant",
      "project_id",
      "purpose",
      "size_bucket",
    ]),
  ],
  ["flow player completed", new Set(["step_count", "choices_made"])],
  ["flow player started", new Set(["project_id"])],
  ["page viewed", new Set(["route_family"])],
  ["project created", new Set(["project_id", "workspace_id"])],
  ["project exported", new Set(["format", "asset_mode", "section_count"])],
  ["project imported", new Set(["has_conflicts"])],
  ["user logged in", new Set(["auth_method"])],
  ["user signed up", new Set(["auth_method"])],
  ["waitlist joined", new Set()],
  ["workspace created", new Set(["workspace_id"])],
]);

const routeFamilies = [
  [(pathname) => pathname === "/", "public_home"],
  [(pathname) => pathname === "/privacy" || pathname === "/terms", "legal"],
  [(pathname) => pathname.startsWith("/docs"), "docs"],
  [(pathname) => pathname.startsWith("/users/log-in"), "login"],
  [(pathname) => pathname.startsWith("/users/register"), "registration"],
  [(pathname) => pathname.startsWith("/users/settings"), "account_settings"],
  [
    (pathname) => pathname.includes("/settings/version-control"),
    "project_version_control_settings",
  ],
  [(pathname) => pathname.includes("/settings/export-import"), "project_export_import"],
  [(pathname) => pathname.includes("/settings"), "project_settings"],
  [(pathname) => pathname.includes("/localization"), "localization"],
  [(pathname) => pathname.includes("/assets"), "assets"],
  [(pathname) => pathname.includes("/flows/") && pathname.endsWith("/play"), "flow_player"],
  [
    (pathname) => pathname.includes("/scenes/") && pathname.endsWith("/explore"),
    "scene_exploration",
  ],
  [(pathname) => pathname.includes("/compare/"), "version_compare"],
  [(pathname) => pathname.includes("/versions/") && pathname.endsWith("/viewer"), "version_viewer"],
  [(pathname) => pathname.includes("/sheets"), "sheets"],
  [(pathname) => pathname.includes("/flows"), "flows"],
  [(pathname) => pathname.includes("/scenes"), "scenes"],
  [(pathname) => pathname.includes("/projects"), "project_dashboard"],
  [(pathname) => pathname.startsWith("/workspaces"), "workspace"],
];

const privateAutoProperties = new Set([
  "$current_url",
  "$host",
  "$initial_current_url",
  "$initial_host",
  "$initial_pathname",
  "$initial_referrer",
  "$initial_referring_domain",
  "$pathname",
  "$prev_pageview_pathname",
  "$referrer",
  "$referring_domain",
  "$session_entry_host",
  "$session_entry_pathname",
  "$session_entry_referrer",
  "$session_entry_referring_domain",
  "$session_entry_url",
]);

const COOKIE_CONSENT_KEY = "storyarn:cookie-consent:v1";
const COOKIE_CONSENT_VERSION = 1;
const COOKIE_CONSENT_MAX_AGE_MS = 730 * 24 * 60 * 60 * 1000;

let initialized = false;
let initializing = false;
let lastPageviewKey = null;
let posthog = null;
let posthogLoadPromise = null;

export function initPostHog() {
  if (initialized || initializing) return;
  if (!hasAnalyticsConsent()) return;

  const config = readConfig();
  if (!config) return;

  initializing = true;

  loadPostHog()
    .then((loadedPosthog) => {
      if (!hasAnalyticsConsent()) return;

      posthog = loadedPosthog;
      initialized = true;

      posthog.init(config.apiKey, {
        ...postHogInitOptions(config),
        loaded: () => {
          posthog.opt_in_capturing?.();
          identifyCurrentUser();
          capturePageview();
        },
      });

      window.addEventListener("phx:page-loading-stop", capturePageview);
      window.addEventListener("phx:analytics", handleAnalyticsEvent);
    })
    .finally(() => {
      initializing = false;
    });
}

async function loadPostHog() {
  posthogLoadPromise ||= Promise.all([
    import("posthog-js/dist/exception-autocapture"),
    import("posthog-js/dist/module.no-external"),
  ]).then(([, module]) => module.default || module.posthog);

  return posthogLoadPromise;
}

export function capture(eventName, properties = {}) {
  if (!initialized || !posthog || typeof eventName !== "string" || eventName.length === 0) return;
  if (!hasAnalyticsConsent()) return;
  if (!eventPropertyAllowlist.has(eventName)) return;
  if (posthog.has_opted_out_capturing?.()) return;

  posthog.capture(eventName, sanitizeProperties(eventName, properties));
}

export function capturePageview() {
  const routeFamily = routeFamilyForPath(window.location.pathname);
  const pageviewKey = pageviewKeyForPath(window.location.pathname);

  if (pageviewKey === lastPageviewKey) return;

  lastPageviewKey = pageviewKey;
  capture("page viewed", { route_family: routeFamily });
}

export function identifyCurrentUser() {
  if (!posthog) return;

  const distinctId = readMeta("posthog-user-id");
  if (!distinctId) return;

  posthog.identify(distinctId, personProperties());
}

function handleAnalyticsEvent(event) {
  const detail = event.detail || {};
  capture(detail.event, detail.properties);
}

function readConfig() {
  if (readMeta("posthog-enabled") !== "true") return null;

  const apiKey = readMeta("posthog-key");
  const host = readMeta("posthog-host");

  if (!apiKey || !host) return null;

  return {
    apiKey,
    errorTrackingEnabled: readMeta("posthog-error-tracking-enabled") === "true",
    host,
  };
}

export function postHogConsentRequired() {
  return readConfig() !== null;
}

export function readCookieConsent() {
  try {
    const rawConsent = window.localStorage.getItem(COOKIE_CONSENT_KEY);
    if (!rawConsent) return null;

    const consent = JSON.parse(rawConsent);
    if (consent?.version !== COOKIE_CONSENT_VERSION) return null;
    if (typeof consent.analytics !== "boolean") return null;
    if (consentExpired(consent)) return null;

    return consent;
  } catch {
    return null;
  }
}

export function hasAnalyticsConsent() {
  return readCookieConsent()?.analytics === true;
}

export function saveCookieConsent({ analytics }) {
  const decidedAt = new Date();
  const consent = {
    analytics: Boolean(analytics),
    decidedAt: decidedAt.toISOString(),
    expiresAt: new Date(decidedAt.getTime() + COOKIE_CONSENT_MAX_AGE_MS).toISOString(),
    version: COOKIE_CONSENT_VERSION,
  };

  try {
    window.localStorage.setItem(COOKIE_CONSENT_KEY, JSON.stringify(consent));
  } catch {
    return consent;
  }

  if (consent.analytics) {
    enablePostHogCapture();
  } else {
    disablePostHogCapture();
  }

  window.dispatchEvent(new CustomEvent("storyarn:cookie-consent-updated", { detail: consent }));

  return consent;
}

export function openCookiePreferences() {
  window.dispatchEvent(new CustomEvent("storyarn:open-cookie-settings"));
}

function enablePostHogCapture() {
  if (initialized && posthog) {
    posthog.opt_in_capturing?.();
    capturePageview();
  } else {
    initPostHog();
  }
}

function disablePostHogCapture() {
  if (!initialized || !posthog) return;

  posthog.opt_out_capturing?.();
}

function consentExpired(consent) {
  if (typeof consent.expiresAt === "string") {
    return Date.parse(consent.expiresAt) <= Date.now();
  }

  if (typeof consent.decidedAt === "string") {
    return Date.parse(consent.decidedAt) + COOKIE_CONSENT_MAX_AGE_MS <= Date.now();
  }

  return true;
}

function readMeta(name) {
  return document.querySelector(`meta[name="${name}"]`)?.getAttribute("content") || null;
}

function personProperties() {
  const properties = {};
  const locale = readMeta("posthog-user-locale");
  const superAdmin = readMeta("posthog-user-super-admin");

  if (locale) properties.locale = locale;
  if (superAdmin) properties.is_super_admin = superAdmin === "true";

  return properties;
}

export function sanitizeProperties(eventName, properties) {
  if (!properties || typeof properties !== "object" || Array.isArray(properties)) return {};

  const propertyAllowlist = eventPropertyAllowlist.get(eventName);
  if (!propertyAllowlist) return {};

  return Object.entries(properties).reduce((safeProperties, [key, value]) => {
    if (propertyAllowlist.has(key) && isAllowedValue(value)) {
      safeProperties[key] = value;
    }

    return safeProperties;
  }, {});
}

export function scrubPostHogEvent(data) {
  scrubProperties(data?.properties);
  scrubProperties(data?.$set);
  scrubProperties(data?.$set_once);
  scrubProperties(data?.properties?.$set);
  scrubProperties(data?.properties?.$set_once);

  return data;
}

function scrubProperties(properties) {
  if (!properties || typeof properties !== "object") return;

  for (const key of privateAutoProperties) {
    delete properties[key];
  }
}

function isAllowedValue(value) {
  return value === null || ["boolean", "number", "string"].includes(typeof value);
}

export function routeFamilyForPath(pathname) {
  const match = routeFamilies.find(([matches]) => matches(pathname));
  return match?.[1] || "other";
}

export function pageviewKeyForPath(pathname) {
  return pathname || "/";
}

export function postHogInitOptions(config) {
  return {
    api_host: config.host,
    autocapture: false,
    capture_exceptions: config.errorTrackingEnabled
      ? {
          capture_console_errors: false,
          capture_unhandled_errors: true,
          capture_unhandled_rejections: true,
        }
      : false,
    capture_pageleave: false,
    capture_pageview: false,
    save_campaign_params: false,
    save_referrer: false,
    disable_scroll_properties: true,
    disable_surveys: true,
    disable_external_dependency_loading: true,
    disable_session_recording: true,
    cookie_expiration: 365,
    persistence: "localStorage+cookie",
    advanced_disable_decide: true,
    advanced_disable_feature_flags: true,
    advanced_disable_flags: true,
    person_profiles: "identified_only",
    before_send: scrubPostHogEvent,
  };
}

export function resetPostHogForTest() {
  initialized = false;
  initializing = false;
  lastPageviewKey = null;
  posthog = null;
  posthogLoadPromise = null;
}

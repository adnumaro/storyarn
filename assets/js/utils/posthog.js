import "posthog-js/dist/exception-autocapture";
import posthog from "posthog-js/dist/module.no-external";

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
  [(pathname) => pathname === "/landing-v2", "public_home_v2"],
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

let initialized = false;
let lastPageviewKey = null;

export function initPostHog() {
  if (initialized) return;

  const config = readConfig();
  if (!config) return;

  initialized = true;

  posthog.init(config.apiKey, {
    ...postHogInitOptions(config),
    loaded: () => {
      identifyCurrentUser();
      capturePageview();
    },
  });

  window.addEventListener("phx:page-loading-stop", capturePageview);
  window.addEventListener("phx:analytics", handleAnalyticsEvent);
}

export function capture(eventName, properties = {}) {
  if (!initialized || typeof eventName !== "string" || eventName.length === 0) return;
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
    advanced_disable_decide: true,
    advanced_disable_feature_flags: true,
    advanced_disable_flags: true,
    person_profiles: "identified_only",
    before_send: scrubPostHogEvent,
  };
}

export function resetPostHogForTest() {
  initialized = false;
  lastPageviewKey = null;
}

import { beforeEach, describe, expect, it } from "vitest";
import {
  hasAnalyticsConsent,
  pageviewKeyForPath,
  postHogInitOptions,
  readCookieConsent,
  routeFamilyForPath,
  saveCookieConsent,
  sanitizeProperties,
  scrubPostHogEvent,
} from "../../../js/utils/posthog.js";

const cookieConsentKey = "storyarn:cookie-consent:v1";

describe("PostHog frontend utility", () => {
  beforeEach(() => {
    localStorage.clear();
  });

  it("enables browser error autocapture only when configured", () => {
    expect(
      postHogInitOptions({
        errorTrackingEnabled: true,
        host: "https://eu.i.posthog.com",
      }).capture_exceptions,
    ).toEqual({
      capture_console_errors: false,
      capture_unhandled_errors: true,
      capture_unhandled_rejections: true,
    });

    expect(
      postHogInitOptions({
        errorTrackingEnabled: false,
        host: "https://eu.i.posthog.com",
      }).capture_exceptions,
    ).toBe(false);

    expect(
      postHogInitOptions({
        errorTrackingEnabled: false,
        host: "https://eu.i.posthog.com",
      }),
    ).toMatchObject({
      cookie_expiration: 365,
      persistence: "localStorage+cookie",
    });
  });

  it("scrubs PostHog URL and referrer auto-properties before sending events", () => {
    const event = scrubPostHogEvent({
      properties: {
        $current_url: "https://storyarn.test/workspaces/private-workspace",
        $pathname: "/workspaces/private-workspace",
        $referrer: "https://example.com/private",
        route_family: "workspace",
      },
      $set_once: {
        $initial_current_url: "https://storyarn.test/workspaces/private-workspace",
      },
    });

    expect(event.properties).toEqual({ route_family: "workspace" });
    expect(event.$set_once).toEqual({});
  });

  it("keeps analytics properties on the explicit allowlist", () => {
    expect(
      sanitizeProperties("custom event", {
        route_family: "sheets",
        sheet_id: 42,
      }),
    ).toEqual({});

    expect(
      sanitizeProperties("page viewed", {
        email: "owner@example.com",
        route_family: "sheets",
        sheet_id: 42,
        url: "/workspaces/private-workspace",
      }),
    ).toEqual({ route_family: "sheets" });
  });

  it("uses path only as a private dedupe key so same-family navigation still counts", () => {
    expect(routeFamilyForPath("/")).toBe("public_home");
    expect(routeFamilyForPath("/privacy")).toBe("legal");
    expect(routeFamilyForPath("/terms")).toBe("legal");
    expect(routeFamilyForPath("/blog/test-branching-dialogue-before-export")).toBe("blog");
    expect(routeFamilyForPath("/workspaces/ws/projects/project/sheets/8")).toBe("sheets");
    expect(routeFamilyForPath("/workspaces/ws/projects/project/sheets/9")).toBe("sheets");
    expect(routeFamilyForPath("/workspaces/ws/projects/project/flows/1/play")).toBe("flow_player");
    expect(routeFamilyForPath("/workspaces/ws/projects/project/scenes/1/explore")).toBe(
      "scene_exploration",
    );
    expect(routeFamilyForPath("/workspaces/ws/projects/project/settings/version-control")).toBe(
      "project_version_control_settings",
    );
    expect(pageviewKeyForPath("/workspaces/ws/projects/project/sheets/8")).not.toBe(
      pageviewKeyForPath("/workspaces/ws/projects/project/sheets/9"),
    );
  });

  it("persists analytics consent decisions", () => {
    expect(readCookieConsent()).toBeNull();
    expect(hasAnalyticsConsent()).toBe(false);

    const accepted = saveCookieConsent({ analytics: true });

    expect(accepted.analytics).toBe(true);
    expect(readCookieConsent()).toMatchObject({ analytics: true, version: 1 });
    expect(hasAnalyticsConsent()).toBe(true);

    const rejected = saveCookieConsent({ analytics: false });

    expect(rejected.analytics).toBe(false);
    expect(readCookieConsent()).toMatchObject({ analytics: false, version: 1 });
    expect(hasAnalyticsConsent()).toBe(false);
  });

  it("ignores expired analytics consent decisions", () => {
    localStorage.setItem(
      cookieConsentKey,
      JSON.stringify({
        analytics: true,
        decidedAt: "2024-01-01T00:00:00.000Z",
        expiresAt: "2024-01-02T00:00:00.000Z",
        version: 1,
      }),
    );

    expect(readCookieConsent()).toBeNull();
    expect(hasAnalyticsConsent()).toBe(false);
  });
});

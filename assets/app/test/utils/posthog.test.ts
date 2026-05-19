import { describe, expect, it } from "vitest";
import {
  pageviewKeyForPath,
  postHogInitOptions,
  routeFamilyForPath,
  sanitizeProperties,
  scrubPostHogEvent,
} from "../../../js/utils/posthog.js";

describe("PostHog frontend utility", () => {
  it("enables browser error autocapture only when configured", () => {
    expect(
      postHogInitOptions({
        errorTrackingEnabled: true,
        host: "https://us.i.posthog.com",
      }).capture_exceptions,
    ).toEqual({
      capture_console_errors: false,
      capture_unhandled_errors: true,
      capture_unhandled_rejections: true,
    });

    expect(
      postHogInitOptions({
        errorTrackingEnabled: false,
        host: "https://us.i.posthog.com",
      }).capture_exceptions,
    ).toBe(false);
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
    expect(routeFamilyForPath("/landing-v2")).toBe("public_home_v2");
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
});

import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import VersionViewerError from "../../../live/versioning/viewer/VersionViewerError.vue";

type Reason = "not_found" | "integrity" | "unreadable";

function mountError(reason: Reason) {
  return mount(VersionViewerError, { props: { reason } });
}

describe("VersionViewerError", () => {
  // The test i18n setup returns the key itself when a translation is missing,
  // so asserting on real copy is what proves the locale entries exist.
  it.each<[Reason, string]>([
    ["not_found", "Version not found"],
    ["integrity", "This version failed its integrity check"],
    ["unreadable", "Couldn't load this version"],
  ])("renders translated copy for %s", (reason, title) => {
    const wrapper = mountError(reason);
    const text = wrapper.text();

    expect(text).toContain(title);
    expect(text).not.toContain("common.version_viewer_error");
  });

  it("explains why a snapshot that fails integrity is not shown", () => {
    const text = mountError("integrity").text();

    expect(text).toContain("does not match");
    expect(text).toContain("will not be shown");
  });

  it("gives each reason its own icon", () => {
    const icons = (["not_found", "integrity", "unreadable"] as Reason[]).map((reason) =>
      mountError(reason).find("svg").html(),
    );

    expect(new Set(icons).size).toBe(icons.length);
  });
});

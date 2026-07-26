import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import VersionViewerError from "../../../live/versioning/viewer/VersionViewerError.vue";

type Reason = "not_found" | "unverified_legacy" | "integrity" | "unreadable";

function mountError(reason: Reason) {
  return mount(VersionViewerError, { props: { reason } });
}

describe("VersionViewerError", () => {
  // The test i18n setup returns the key itself when a translation is missing,
  // so asserting on real copy is what proves the locale entries exist.
  it.each<[Reason, string]>([
    ["not_found", "Version not found"],
    ["unverified_legacy", "This version can't be opened"],
    ["integrity", "This version failed its integrity check"],
    ["unreadable", "Couldn't load this version"],
  ])("renders translated copy for %s", (reason, title) => {
    const wrapper = mountError(reason);
    const text = wrapper.text();

    expect(text).toContain(title);
    expect(text).not.toContain("common.version_viewer_error");
  });

  it("explains why a pre-checksum snapshot stays in the history but cannot be opened", () => {
    const text = mountError("unverified_legacy").text();

    expect(text).toContain("integrity checksums");
    expect(text).toContain("can't be viewed or restored");
  });

  it("gives each reason its own icon", () => {
    const icons = (["not_found", "unverified_legacy", "integrity", "unreadable"] as Reason[]).map(
      (reason) => mountError(reason).find("svg").html(),
    );

    expect(new Set(icons).size).toBe(icons.length);
  });
});

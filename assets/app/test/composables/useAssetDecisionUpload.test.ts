import { describe, expect, it } from "vitest";
import { useAssetDecisionUpload } from "@shared/composables/useAssetDecisionUpload";

describe("useAssetDecisionUpload", () => {
  it("keeps state isolated between consumers", () => {
    const first = useAssetDecisionUpload();
    const second = useAssetDecisionUpload();

    first.progress.value = 75;
    first.error.value = "first upload failed";

    expect(second.progress.value).toBe(0);
    expect(second.error.value).toBeNull();
  });
});

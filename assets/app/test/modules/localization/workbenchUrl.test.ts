import { describe, expect, it } from "vitest";
import { workbenchUrl } from "../../../modules/localization/navigation/workbenchUrl";

describe("workbenchUrl", () => {
  it("returns the bare workbench when nothing is filtered", () => {
    expect(workbenchUrl("/l/texts/ca")).toBe("/l/texts/ca");
    expect(workbenchUrl("/l/texts/ca", { status: "", stale: false })).toBe("/l/texts/ca");
  });

  it("encodes the filters the LiveView reads from the URL", () => {
    expect(
      workbenchUrl("/l/texts/ca", {
        status: "review",
        sourceType: "block",
        voStatus: "needed",
        speaker: 7,
        stale: true,
        search: "ropes & sails",
      }),
    ).toBe(
      "/l/texts/ca?status=review&source_type=block&vo_status=needed&speaker=7&stale=1&search=ropes+%26+sails",
    );
  });

  it("keeps the selected string in the path", () => {
    expect(workbenchUrl("/l/texts/ca", { status: "pending" }, 42)).toBe(
      "/l/texts/ca/42?status=pending",
    );
  });
});

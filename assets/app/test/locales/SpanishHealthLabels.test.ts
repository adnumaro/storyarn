import { describe, expect, it } from "vitest";
import scenes from "../../locales/es/scenes.json";

describe("Spanish health labels", () => {
  it("translates the ambient flow issue type without leaking the English domain term", () => {
    expect(scenes.scenes.health.issue_types.stale_ambient_flow_reference).toBe(
      "Referencia de flujo ambiental inexistente",
    );
  });
});

import { describe, expect, it } from "vitest";

import {
  buildConnectionRemovalPayload,
  matchesConnectionRemoval,
} from "@modules/flows/editor/services/connectionIdentity";

describe("flow connection identity", () => {
  const first = {
    id: "rete-first",
    sourceOutput: "response-first",
    targetInput: "input",
  };
  const second = {
    id: "rete-second",
    sourceOutput: "response-second",
    targetInput: "input",
  };

  it("includes the persisted id and both pins in canvas delete events", () => {
    expect(buildConnectionRemovalPayload(first, 10, 20, 101)).toEqual({
      id: 101,
      source_node_id: 10,
      source_pin: "response-first",
      target_node_id: 20,
      target_pin: "input",
    });
  });

  it("selects exactly one parallel connection by persisted id", () => {
    const payload = buildConnectionRemovalPayload(second, 10, 20, 102);

    expect(matchesConnectionRemoval(first, payload, 101)).toBe(false);
    expect(matchesConnectionRemoval(second, payload, 102)).toBe(true);
  });

  it("uses the exact pin pair before a persisted id reaches the client", () => {
    const payload = buildConnectionRemovalPayload(second, 10, 20);

    expect(matchesConnectionRemoval(first, payload)).toBe(false);
    expect(matchesConnectionRemoval(second, payload)).toBe(true);
  });
});

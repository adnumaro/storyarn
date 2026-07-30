import { describe, expect, it } from "vitest";
import {
  ADVANCED_SEARCH_HELP_SYMBOL,
  advancedSearchDefinition,
  advancedSearchPrefixes,
  routeAdvancedSearch,
  type AdvancedSearchMode,
  type AdvancedSearchPrefixSymbol,
  type AdvancedSearchTrigger,
} from "@shared/command-palette/advancedSearch";

describe("advanced command-palette search", () => {
  it("declares every searchable prefix once with its execution policy", () => {
    const policies = advancedSearchPrefixes.map(
      ({ symbol, mode, trigger, minimumLength, cost }) => ({
        symbol,
        mode,
        trigger,
        minimumLength,
        cost,
      }),
    );

    expect(policies).toEqual([
      {
        symbol: "$",
        mode: "variables",
        trigger: "debounced",
        minimumLength: 1,
        cost: "low",
      },
      {
        symbol: "#",
        mode: "sheets",
        trigger: "debounced",
        minimumLength: 1,
        cost: "low",
      },
      {
        symbol: ">",
        mode: "flows",
        trigger: "debounced",
        minimumLength: 1,
        cost: "low",
      },
      {
        symbol: "@",
        mode: "scenes",
        trigger: "debounced",
        minimumLength: 1,
        cost: "low",
      },
      {
        symbol: "*",
        mode: "all",
        trigger: "submit",
        minimumLength: 3,
        cost: "high",
      },
    ]);
    expect(new Set(advancedSearchPrefixes.map(({ symbol }) => symbol)).size).toBe(
      advancedSearchPrefixes.length,
    );
  });

  it.each(["", "help", "foo.bar", "foo@bar.com", "chapter one", " $health"])(
    "keeps ordinary input %j on the normal path",
    (input) => {
      expect(routeAdvancedSearch(input)).toEqual({ kind: "normal" });
    },
  );

  it("routes the help prefix without issuing a search", () => {
    expect(ADVANCED_SEARCH_HELP_SYMBOL).toBe("?");
    expect(routeAdvancedSearch("?")).toEqual({ kind: "help", query: "" });
    expect(routeAdvancedSearch("?variables")).toEqual({
      kind: "help",
      query: "variables",
    });
  });

  it.each(advancedSearchPrefixes)(
    "shows contextual help for a bare $symbol prefix",
    (definition) => {
      expect(routeAdvancedSearch(definition.symbol)).toEqual({
        kind: "prefix-help",
        definition,
      });
    },
  );

  it.each<
    [
      input: string,
      symbol: AdvancedSearchPrefixSymbol,
      mode: AdvancedSearchMode,
      trigger: AdvancedSearchTrigger,
      query: string,
    ]
  >([
    ["$health", "$", "variables", "debounced", "health"],
    ["$health != 0", "$", "variables", "debounced", "health != 0"],
    ["$health += 11", "$", "variables", "debounced", "health += 11"],
    ["#main-characters.?k", "#", "sheets", "debounced", "main-characters.?k"],
    [">chapter-one.?boss", ">", "flows", "debounced", "chapter-one.?boss"],
    ["@world-map.?castle", "@", "scenes", "debounced", "world-map.?castle"],
    ["*ancient tome", "*", "all", "submit", "ancient tome"],
  ])("routes %s to its closed search mode", (input, symbol, mode, trigger, query) => {
    expect(routeAdvancedSearch(input)).toMatchObject({
      kind: "search",
      definition: { symbol, mode, trigger },
      query,
      ready: true,
    });
  });

  it("does not interpret variable operators as leading search prefixes", () => {
    expect(routeAdvancedSearch("$health > 0")).toMatchObject({
      kind: "search",
      definition: { mode: "variables" },
      query: "health > 0",
    });
  });

  it("marks full-project search ready only at its declared minimum length", () => {
    expect(routeAdvancedSearch("*a")).toMatchObject({
      kind: "search",
      definition: { mode: "all", trigger: "submit" },
      query: "a",
      ready: false,
    });
    expect(routeAdvancedSearch("*ab")).toMatchObject({
      kind: "search",
      query: "ab",
      ready: false,
    });
    expect(routeAdvancedSearch("*abc")).toMatchObject({
      kind: "search",
      query: "abc",
      ready: true,
    });
  });

  it("preserves the unparsed query body exactly for the server", () => {
    expect(routeAdvancedSearch("$  health != 0  ")).toMatchObject({
      kind: "search",
      query: "  health != 0  ",
      ready: true,
    });
  });

  it("resolves definitions only for known searchable symbols", () => {
    expect(advancedSearchDefinition("$")?.mode).toBe("variables");
    expect(advancedSearchDefinition("*")?.trigger).toBe("submit");
    expect(advancedSearchDefinition("?")).toBeUndefined();
    expect(advancedSearchDefinition("x")).toBeUndefined();
  });
});

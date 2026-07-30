export type AdvancedSearchPrefixSymbol = "$" | "#" | ">" | "@" | "*";
export type AdvancedSearchMode = "variables" | "sheets" | "flows" | "scenes" | "all";
export type AdvancedSearchTrigger = "debounced" | "submit";
export type AdvancedSearchCost = "low" | "high";

export interface AdvancedSearchPrefixDefinition {
  symbol: AdvancedSearchPrefixSymbol;
  mode: AdvancedSearchMode;
  trigger: AdvancedSearchTrigger;
  minimumLength: number;
  cost: AdvancedSearchCost;
  labelKey: string;
  descriptionKey: string;
  examples: readonly string[];
}

export interface AdvancedSearchVariableOperatorDefinition {
  symbol: "~" | "!~";
  example: string;
  labelKey: string;
  descriptionKey: string;
}

export type AdvancedSearchRoute =
  | { kind: "normal" }
  | { kind: "help"; query: string }
  | { kind: "prefix-help"; definition: AdvancedSearchPrefixDefinition }
  | {
      kind: "search";
      definition: AdvancedSearchPrefixDefinition;
      query: string;
      ready: boolean;
    };

export const ADVANCED_SEARCH_HELP_SYMBOL = "?" as const;

export const advancedSearchVariableOperators = [
  {
    symbol: "~",
    example: "$faction ~ clav",
    labelKey: "palette.advanced_search.variable_operators.contains.label",
    descriptionKey: "palette.advanced_search.variable_operators.contains.description",
  },
  {
    symbol: "!~",
    example: "$faction !~ clav",
    labelKey: "palette.advanced_search.variable_operators.not_contains.label",
    descriptionKey: "palette.advanced_search.variable_operators.not_contains.description",
  },
] as const satisfies readonly AdvancedSearchVariableOperatorDefinition[];

/**
 * The single client-side catalog for advanced-search discovery and routing.
 *
 * Parsing the query body remains server-owned. The palette only recognizes
 * an exact first-character prefix, removes it, and applies the execution
 * policy declared here.
 */
export const advancedSearchPrefixes = [
  {
    symbol: "$",
    mode: "variables",
    trigger: "debounced",
    minimumLength: 1,
    cost: "low",
    labelKey: "palette.advanced_search.prefixes.variables.label",
    descriptionKey: "palette.advanced_search.prefixes.variables.description",
    examples: ["$health", "$health != 0", "$faction ~ clav", "$faction !~ clav"],
  },
  {
    symbol: "#",
    mode: "sheets",
    trigger: "debounced",
    minimumLength: 1,
    cost: "low",
    labelKey: "palette.advanced_search.prefixes.sheets.label",
    descriptionKey: "palette.advanced_search.prefixes.sheets.description",
    examples: ["#main-characters", "#main-characters.", "#main-characters.?k"],
  },
  {
    symbol: ">",
    mode: "flows",
    trigger: "debounced",
    minimumLength: 1,
    cost: "low",
    labelKey: "palette.advanced_search.prefixes.flows.label",
    descriptionKey: "palette.advanced_search.prefixes.flows.description",
    examples: [">chapter-one", ">chapter-one.?boss"],
  },
  {
    symbol: "@",
    mode: "scenes",
    trigger: "debounced",
    minimumLength: 1,
    cost: "low",
    labelKey: "palette.advanced_search.prefixes.scenes.label",
    descriptionKey: "palette.advanced_search.prefixes.scenes.description",
    examples: ["@world-map", "@world-map.?castle"],
  },
  {
    symbol: "*",
    mode: "all",
    trigger: "submit",
    minimumLength: 3,
    cost: "high",
    labelKey: "palette.advanced_search.prefixes.all.label",
    descriptionKey: "palette.advanced_search.prefixes.all.description",
    examples: ["*ancient tome"],
  },
] as const satisfies readonly AdvancedSearchPrefixDefinition[];

const definitionsBySymbol = new Map<AdvancedSearchPrefixSymbol, AdvancedSearchPrefixDefinition>(
  advancedSearchPrefixes.map((definition) => [definition.symbol, definition]),
);

export function advancedSearchDefinition(
  symbol: string,
): AdvancedSearchPrefixDefinition | undefined {
  return definitionsBySymbol.get(symbol as AdvancedSearchPrefixSymbol);
}

/**
 * Routes an unmodified palette input.
 *
 * Advanced mode is deliberately strict: a prefix must be the first
 * character. This keeps dotted shortcuts, emails, natural-language commands
 * and inputs with leading whitespace on the normal navigation path.
 */
export function routeAdvancedSearch(input: string): AdvancedSearchRoute {
  const firstCharacter = input.charAt(0);

  if (firstCharacter === ADVANCED_SEARCH_HELP_SYMBOL) {
    return { kind: "help", query: input.slice(1) };
  }

  const definition = advancedSearchDefinition(firstCharacter);
  if (!definition) return { kind: "normal" };

  const query = input.slice(1);
  if (query.trim() === "") {
    return { kind: "prefix-help", definition };
  }

  return {
    kind: "search",
    definition,
    query,
    ready: query.trim().length >= definition.minimumLength,
  };
}

export type OperationSerializedValue = string | number | boolean | null | Record<string, unknown>;

export type OperationDomain = "navigation" | "references" | "actions";
export type OperationLatency = "instant" | "interactive" | "deferred";
export type OperationAuthorization = "view" | "edit_content" | "contextual";
export type OperationResultType = "navigation" | "lookup" | "mutation" | "command";
export type OperationParameterType =
  | "destination"
  | "entity_type"
  | "project"
  | "entity"
  | "flow"
  | "variable"
  | "command"
  | "view";
export type OperationCompletionSource =
  | "navigation"
  | "editable_projects"
  | "deletable_entities"
  | "reference_entities"
  | "flows"
  | "sheet_variables"
  | "entity_types"
  | "commands"
  | "views";
export type OperationCompletionMode = "server" | "client";

export type OperationPhrasePart =
  | { kind: "text"; textKey: string }
  | { kind: "parameter"; parameterId: string };

export interface OperationParameterDefinition {
  id: string;
  type: OperationParameterType;
  completionSource: OperationCompletionSource;
  completionMode: OperationCompletionMode;
  required: boolean;
  labelKey: string;
}

export interface OperationHelp {
  labelKey: string;
  descriptionKey: string;
  exampleKey: string;
  pattern: string | null;
}

/**
 * Serializable projection of the server-owned operation registry.
 *
 * It deliberately carries no callback, component or authorization result.
 * Execution and authorization remain server-side; the palette only renders
 * this descriptor and sends the selected operation/parameter values back.
 */
export interface OperationDefinition {
  id: string;
  domain: OperationDomain;
  parameters: OperationParameterDefinition[];
  latency: OperationLatency;
  authorization: OperationAuthorization;
  resultType: OperationResultType;
  phrase: OperationPhrasePart[];
  help: OperationHelp;
}

export interface OperationValue {
  id: string;
  value: OperationSerializedValue;
  label: string;
  context?: string;
  meta?: Record<string, unknown>;
}

export type OperationValues = Readonly<Record<string, OperationValue | null | undefined>>;

export type OperationErrors = Readonly<Record<string, string | null | undefined>>;

export function operationParameter(
  definition: OperationDefinition,
  parameterId: string | null | undefined,
): OperationParameterDefinition | undefined {
  if (!parameterId) return undefined;
  return definition.parameters.find((parameter) => parameter.id === parameterId);
}

export function nextOperationParameterId(
  definition: OperationDefinition,
  parameterId: string,
): string | null {
  const index = definition.parameters.findIndex((parameter) => parameter.id === parameterId);
  return index >= 0 ? (definition.parameters[index + 1]?.id ?? null) : null;
}

export function previousOperationParameterId(
  definition: OperationDefinition,
  parameterId: string,
): string | null {
  const index = definition.parameters.findIndex((parameter) => parameter.id === parameterId);
  return index > 0 ? (definition.parameters[index - 1]?.id ?? null) : null;
}

export function firstMissingRequiredParameterId(
  definition: OperationDefinition,
  values: OperationValues,
): string | null {
  return (
    definition.parameters.find(
      (parameter) => parameter.required && !operationValuePresent(values[parameter.id]),
    )?.id ?? null
  );
}

export function operationReady(
  definition: OperationDefinition,
  values: OperationValues,
  errors: OperationErrors = {},
): boolean {
  return (
    firstMissingRequiredParameterId(definition, values) === null &&
    definition.parameters.every((parameter) => !errors[parameter.id])
  );
}

export function operationSearchText(
  definition: OperationDefinition,
  resolve: (key: string) => string,
): string {
  const terms = [
    resolve(definition.help.labelKey),
    resolve(definition.help.descriptionKey),
    resolve(definition.help.exampleKey),
    definition.help.pattern,
    ...definition.parameters.map((parameter) => resolve(parameter.labelKey)),
  ];

  return [...new Set(terms.filter((term): term is string => !!term?.trim()))].join(" ");
}

function operationValuePresent(value: OperationValue | null | undefined): value is OperationValue {
  return value !== null && value !== undefined && value.id.trim().length > 0;
}

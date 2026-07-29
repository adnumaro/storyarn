defmodule Storyarn.CommandPalette.Definition do
  @moduledoc """
  Validated, immutable metadata for one command-palette operation.

  Definitions are product contracts, not executable callbacks. The registry
  serializes them for the guided palette while execution remains in the
  authorized domain boundaries that already own each capability.
  """

  @domains [:navigation, :references, :actions]
  @parameter_types [:destination, :entity_type, :project, :entity, :flow, :variable, :command, :view]
  @completion_sources [
    :navigation,
    :editable_projects,
    :deletable_entities,
    :reference_entities,
    :flows,
    :sheet_variables,
    :entity_types,
    :commands,
    :views
  ]
  @completion_modes [:server, :client]
  @latencies [:instant, :interactive, :deferred]
  @authorizations [:view, :edit_content, :contextual]
  @result_types [:navigation, :lookup, :mutation, :command]
  @id_format ~r/^[a-z][a-z0-9_]*$/

  @enforce_keys [
    :id,
    :domain,
    :parameters,
    :latency,
    :authorization,
    :result_type,
    :requires_project,
    :phrase,
    :help
  ]
  defstruct [
    :id,
    :domain,
    :parameters,
    :latency,
    :authorization,
    :result_type,
    :requires_project,
    :phrase,
    :help
  ]

  @type domain :: :navigation | :references | :actions

  @type parameter_type ::
          :destination | :entity_type | :project | :entity | :flow | :variable | :command | :view

  @type completion_source ::
          :navigation
          | :editable_projects
          | :deletable_entities
          | :reference_entities
          | :flows
          | :sheet_variables
          | :entity_types
          | :commands
          | :views

  @type completion_mode :: :server | :client

  @type parameter :: %{
          required(:id) => String.t(),
          required(:type) => parameter_type(),
          required(:completion_source) => completion_source(),
          required(:completion_mode) => completion_mode(),
          required(:required) => boolean(),
          required(:label_key) => String.t()
        }

  @type phrase_token ::
          %{required(:kind) => :text, required(:text_key) => String.t()}
          | %{required(:kind) => :parameter, required(:parameter_id) => String.t()}

  @type help :: %{
          required(:label_key) => String.t(),
          required(:description_key) => String.t(),
          required(:example_key) => String.t(),
          required(:pattern) => String.t() | nil
        }

  @type t :: %__MODULE__{
          id: String.t(),
          domain: domain(),
          parameters: [parameter()],
          latency: :instant | :interactive | :deferred,
          authorization: :view | :edit_content | :contextual,
          result_type: :navigation | :lookup | :mutation | :command,
          requires_project: boolean(),
          phrase: [phrase_token()],
          help: help()
        }

  @doc "Builds a definition and raises when its contract is incomplete or invalid."
  @spec new!(map()) :: t()
  def new!(attrs) when is_map(attrs) do
    __MODULE__
    |> struct!(attrs)
    |> validate!()
  end

  @doc "Validates a definition and returns it unchanged."
  @spec validate!(t()) :: t()
  def validate!(%__MODULE__{} = definition) do
    errors = validation_errors(definition)

    if errors == [] do
      definition
    else
      raise ArgumentError,
            "invalid command-palette operation #{inspect(definition.id)}: " <>
              Enum.join(errors, ", ")
    end
  end

  @doc "Returns the values accepted by each closed registry enum."
  @spec enum_values(atom()) :: [atom()]
  def enum_values(:domain), do: @domains
  def enum_values(:parameter_type), do: @parameter_types
  def enum_values(:completion_source), do: @completion_sources
  def enum_values(:completion_mode), do: @completion_modes
  def enum_values(:latency), do: @latencies
  def enum_values(:authorization), do: @authorizations
  def enum_values(:result_type), do: @result_types

  @doc "Returns the hard latency budget for classes that promise one."
  @spec latency_budget_ms(atom()) :: pos_integer() | nil
  def latency_budget_ms(:instant), do: 150
  def latency_budget_ms(latency) when latency in @latencies, do: nil

  @doc "Serializes a definition to the camel-cased LiveVue catalog contract."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = definition) do
    %{
      id: definition.id,
      domain: Atom.to_string(definition.domain),
      parameters: Enum.map(definition.parameters, &serialize_parameter/1),
      latency: Atom.to_string(definition.latency),
      authorization: Atom.to_string(definition.authorization),
      resultType: Atom.to_string(definition.result_type),
      requiresProject: definition.requires_project,
      phrase: Enum.map(definition.phrase, &serialize_phrase_token/1),
      help: serialize_help(definition.help)
    }
  end

  defp validation_errors(definition) do
    parameter_ids = Enum.map(definition.parameters, & &1.id)
    phrase_parameter_ids = phrase_parameter_ids(definition.phrase)

    []
    |> require(valid_id?(definition.id), "invalid id")
    |> require(definition.domain in @domains, "invalid domain")
    |> require(valid_parameters?(definition.parameters), "invalid parameters")
    |> require(Enum.uniq(parameter_ids) == parameter_ids, "duplicate parameter id")
    |> require(valid_phrase?(definition.phrase), "invalid phrase")
    |> require(
      Enum.sort(phrase_parameter_ids) == Enum.sort(parameter_ids),
      "phrase parameters do not match definition"
    )
    |> require(definition.latency in @latencies, "invalid latency")
    |> require(definition.authorization in @authorizations, "invalid authorization")
    |> require(definition.result_type in @result_types, "invalid result type")
    |> require(is_boolean(definition.requires_project), "invalid requires_project")
    |> require(valid_help?(definition.help), "invalid help")
    |> Enum.reverse()
  end

  defp valid_parameters?(parameters) when is_list(parameters) and parameters != [] do
    Enum.all?(parameters, fn
      %{
        id: id,
        type: type,
        completion_source: completion_source,
        completion_mode: completion_mode,
        required: required,
        label_key: label_key
      }
      when is_boolean(required) ->
        valid_id?(id) and type in @parameter_types and
          completion_source in @completion_sources and completion_mode in @completion_modes and
          non_empty_string?(label_key)

      _other ->
        false
    end)
  end

  defp valid_parameters?(_parameters), do: false

  defp valid_phrase?(phrase) when is_list(phrase) and phrase != [] do
    Enum.all?(phrase, fn
      %{kind: :text, text_key: text_key} -> non_empty_string?(text_key)
      %{kind: :parameter, parameter_id: parameter_id} -> valid_id?(parameter_id)
      _other -> false
    end)
  end

  defp valid_phrase?(_phrase), do: false

  defp phrase_parameter_ids(phrase) when is_list(phrase) do
    Enum.flat_map(phrase, fn
      %{kind: :parameter, parameter_id: parameter_id} -> [parameter_id]
      _other -> []
    end)
  end

  defp phrase_parameter_ids(_phrase), do: []

  defp valid_help?(%{label_key: label_key, description_key: description_key, example_key: example_key, pattern: pattern}) do
    non_empty_string?(label_key) and non_empty_string?(description_key) and
      non_empty_string?(example_key) and (is_nil(pattern) or non_empty_string?(pattern))
  end

  defp valid_help?(_help), do: false

  defp valid_id?(value), do: is_binary(value) and Regex.match?(@id_format, value)
  defp non_empty_string?(value), do: is_binary(value) and String.trim(value) != ""

  defp require(errors, true, _error), do: errors
  defp require(errors, false, error), do: [error | errors]

  defp serialize_parameter(parameter) do
    %{
      id: parameter.id,
      type: Atom.to_string(parameter.type),
      completionSource: Atom.to_string(parameter.completion_source),
      completionMode: Atom.to_string(parameter.completion_mode),
      required: parameter.required,
      labelKey: parameter.label_key
    }
  end

  defp serialize_phrase_token(%{kind: :text, text_key: text_key}) do
    %{kind: "text", textKey: text_key}
  end

  defp serialize_phrase_token(%{kind: :parameter, parameter_id: parameter_id}) do
    %{kind: "parameter", parameterId: parameter_id}
  end

  defp serialize_help(help) do
    %{
      labelKey: help.label_key,
      descriptionKey: help.description_key,
      exampleKey: help.example_key,
      pattern: help.pattern
    }
  end
end

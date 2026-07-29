defmodule Storyarn.CommandPalette.Registry do
  @moduledoc """
  Single source of truth for the deterministic operations delivered by
  Slice 7.1a.1.

  Entries land only alongside their authorized backend; declaring an
  unavailable operation early would make generated help lie.
  """

  alias Storyarn.CommandPalette.Definition

  @definitions [
    Definition.new!(%{
      id: "goto",
      domain: :navigation,
      parameters: [
        %{
          id: "destination",
          type: :destination,
          completion_source: :navigation,
          completion_mode: :server,
          required: true,
          label_key: "palette.operations.goto.parameters.destination"
        }
      ],
      latency: :instant,
      authorization: :view,
      result_type: :navigation,
      phrase: [
        %{kind: :text, text_key: "palette.operations.goto.phrase.prefix"},
        %{kind: :parameter, parameter_id: "destination"}
      ],
      help: %{
        label_key: "palette.operations.goto.label",
        description_key: "palette.operations.goto.description",
        example_key: "palette.operations.goto.example",
        pattern: nil
      }
    }),
    Definition.new!(%{
      id: "variable_definition",
      domain: :references,
      parameters: [
        %{
          id: "variable",
          type: :variable,
          completion_source: :sheet_variables,
          completion_mode: :server,
          required: true,
          label_key: "palette.operations.variable_definition.parameters.variable"
        }
      ],
      latency: :instant,
      authorization: :view,
      result_type: :lookup,
      phrase: [
        %{kind: :text, text_key: "palette.operations.variable_definition.phrase.prefix"},
        %{kind: :parameter, parameter_id: "variable"}
      ],
      help: %{
        label_key: "palette.operations.variable_definition.label",
        description_key: "palette.operations.variable_definition.description",
        example_key: "palette.operations.variable_definition.example",
        pattern: "mc.jaime.health"
      }
    }),
    Definition.new!(%{
      id: "variable_usages",
      domain: :references,
      parameters: [
        %{
          id: "variable",
          type: :variable,
          completion_source: :sheet_variables,
          completion_mode: :server,
          required: true,
          label_key: "palette.operations.variable_usages.parameters.variable"
        }
      ],
      latency: :instant,
      authorization: :view,
      result_type: :lookup,
      phrase: [
        %{kind: :text, text_key: "palette.operations.variable_usages.phrase.prefix"},
        %{kind: :parameter, parameter_id: "variable"}
      ],
      help: %{
        label_key: "palette.operations.variable_usages.label",
        description_key: "palette.operations.variable_usages.description",
        example_key: "palette.operations.variable_usages.example",
        pattern: nil
      }
    }),
    Definition.new!(%{
      id: "entity_usages",
      domain: :references,
      parameters: [
        %{
          id: "entity",
          type: :entity,
          completion_source: :reference_entities,
          completion_mode: :server,
          required: true,
          label_key: "palette.operations.entity_usages.parameters.entity"
        }
      ],
      latency: :instant,
      authorization: :view,
      result_type: :lookup,
      phrase: [
        %{kind: :text, text_key: "palette.operations.entity_usages.phrase.prefix"},
        %{kind: :parameter, parameter_id: "entity"}
      ],
      help: %{
        label_key: "palette.operations.entity_usages.label",
        description_key: "palette.operations.entity_usages.description",
        example_key: "palette.operations.entity_usages.example",
        pattern: nil
      }
    }),
    Definition.new!(%{
      id: "flow_callers",
      domain: :references,
      parameters: [
        %{
          id: "flow",
          type: :flow,
          completion_source: :flows,
          completion_mode: :server,
          required: true,
          label_key: "palette.operations.flow_callers.parameters.flow"
        }
      ],
      latency: :instant,
      authorization: :view,
      result_type: :lookup,
      phrase: [
        %{kind: :text, text_key: "palette.operations.flow_callers.phrase.prefix"},
        %{kind: :parameter, parameter_id: "flow"}
      ],
      help: %{
        label_key: "palette.operations.flow_callers.label",
        description_key: "palette.operations.flow_callers.description",
        example_key: "palette.operations.flow_callers.example",
        pattern: nil
      }
    }),
    Definition.new!(%{
      id: "create",
      domain: :actions,
      parameters: [
        %{
          id: "entity_type",
          type: :entity_type,
          completion_source: :entity_types,
          completion_mode: :client,
          required: true,
          label_key: "palette.operations.create.parameters.entity_type"
        },
        %{
          id: "project",
          type: :project,
          completion_source: :editable_projects,
          completion_mode: :client,
          required: true,
          label_key: "palette.operations.create.parameters.project"
        }
      ],
      latency: :interactive,
      authorization: :edit_content,
      result_type: :mutation,
      phrase: [
        %{kind: :text, text_key: "palette.operations.create.phrase.prefix"},
        %{kind: :parameter, parameter_id: "entity_type"},
        %{kind: :text, text_key: "palette.operations.create.phrase.between"},
        %{kind: :parameter, parameter_id: "project"}
      ],
      help: %{
        label_key: "palette.operations.create.label",
        description_key: "palette.operations.create.description",
        example_key: "palette.operations.create.example",
        pattern: nil
      }
    }),
    Definition.new!(%{
      id: "delete",
      domain: :actions,
      parameters: [
        %{
          id: "entity",
          type: :entity,
          completion_source: :deletable_entities,
          completion_mode: :server,
          required: true,
          label_key: "palette.operations.delete.parameters.entity"
        }
      ],
      latency: :interactive,
      authorization: :edit_content,
      result_type: :mutation,
      phrase: [
        %{kind: :text, text_key: "palette.operations.delete.phrase.prefix"},
        %{kind: :parameter, parameter_id: "entity"}
      ],
      help: %{
        label_key: "palette.operations.delete.label",
        description_key: "palette.operations.delete.description",
        example_key: "palette.operations.delete.example",
        pattern: nil
      }
    }),
    Definition.new!(%{
      id: "run_command",
      domain: :actions,
      parameters: [
        %{
          id: "command",
          type: :command,
          completion_source: :commands,
          completion_mode: :client,
          required: true,
          label_key: "palette.operations.run_command.parameters.command"
        }
      ],
      latency: :instant,
      authorization: :contextual,
      result_type: :command,
      phrase: [
        %{kind: :text, text_key: "palette.operations.run_command.phrase.prefix"},
        %{kind: :parameter, parameter_id: "command"}
      ],
      help: %{
        label_key: "palette.operations.run_command.label",
        description_key: "palette.operations.run_command.description",
        example_key: "palette.operations.run_command.example",
        pattern: nil
      }
    }),
    Definition.new!(%{
      id: "open_view",
      domain: :actions,
      parameters: [
        %{
          id: "destination",
          type: :view,
          completion_source: :views,
          completion_mode: :client,
          required: true,
          label_key: "palette.operations.open_view.parameters.destination"
        }
      ],
      latency: :instant,
      authorization: :contextual,
      result_type: :navigation,
      phrase: [
        %{kind: :text, text_key: "palette.operations.open_view.phrase.prefix"},
        %{kind: :parameter, parameter_id: "destination"}
      ],
      help: %{
        label_key: "palette.operations.open_view.label",
        description_key: "palette.operations.open_view.description",
        example_key: "palette.operations.open_view.example",
        pattern: nil
      }
    })
  ]

  @definitions_by_id Map.new(@definitions, &{&1.id, &1})

  if map_size(@definitions_by_id) != length(@definitions) do
    raise "duplicate command-palette operation id"
  end

  @doc "Returns every registered definition in stable help order."
  @spec all() :: [Definition.t()]
  def all, do: @definitions

  @doc "Looks up one operation without converting client input to atoms."
  @spec fetch(String.t()) :: {:ok, Definition.t()} | :error
  def fetch(id) when is_binary(id), do: Map.fetch(@definitions_by_id, id)
  def fetch(_id), do: :error

  @doc "Looks up a parameter within a registered operation."
  @spec fetch_parameter(String.t(), String.t()) :: {:ok, Definition.parameter()} | :error
  def fetch_parameter(operation_id, parameter_id) when is_binary(operation_id) and is_binary(parameter_id) do
    with {:ok, definition} <- fetch(operation_id),
         %{} = parameter <- Enum.find(definition.parameters, &(&1.id == parameter_id)) do
      {:ok, parameter}
    else
      _missing -> :error
    end
  end

  def fetch_parameter(_operation_id, _parameter_id), do: :error

  @doc "Returns the JSON-safe generated-help catalog for LiveVue."
  @spec catalog() :: [map()]
  def catalog, do: Enum.map(@definitions, &Definition.to_map/1)
end

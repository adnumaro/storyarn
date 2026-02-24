defmodule Storyarn.Exports do
  @moduledoc """
  The Exports context.

  Handles project export in multiple formats: Storyarn JSON (native, lossless),
  Ink, Yarn Spinner, Unity, Godot, Unreal, and articy:draft XML.

  This module serves as a facade, delegating to specialized submodules:
  - `DataCollector` - Loads project data for export
  - `SerializerRegistry` - Resolves format atoms to serializer modules
  - `Validator` - Pre-export validation and health checks
  - `Serializers.StoryarnJSON` - Native JSON format (lossless round-trip)
  """

  alias Storyarn.Exports.{DataCollector, ExportOptions, SerializerRegistry, Validator}

  @doc """
  Export a project to the specified format.

  ## Authorization

  Caller MUST verify the current user has at least viewer role on the project
  before calling this function. The Exports context does not enforce
  authorization — that responsibility belongs to the LiveView layer.

  ## Returns

  `{:ok, output}` where output is a binary or list of `{filename, content}` tuples,
  or `{:error, reason}`.

  ## Options

  See `Storyarn.Exports.ExportOptions` for all available options.

  ## Examples

      iex> Exports.export_project(project, %{format: :storyarn})
      {:ok, "{...json...}"}

      iex> Exports.export_project(project, %{format: :ink})
      {:ok, [{"story.ink", "..."}, {"metadata.json", "..."}]}

  """
  def export_project(project, opts \\ %{}) do
    with {:ok, options} <- ExportOptions.new(opts),
         {:ok, options} <- maybe_validate(project, options),
         {:ok, serializer} <- SerializerRegistry.get(options.format) do
      project_data = DataCollector.collect(project.id, options)
      serializer.serialize(project_data, options)
    end
  end

  @doc """
  Validate a project for export without actually exporting.

  Returns a `%ValidationResult{}` with errors, warnings, and info items.
  """
  defdelegate validate_project(project_id, opts \\ %{}), to: Validator, as: :validate_project

  @doc """
  Count entities in a project for progress estimation.
  """
  defdelegate count_entities(project_id, opts), to: DataCollector, as: :count_entities

  @doc """
  List available export formats with their labels.
  """
  defdelegate list_formats(), to: SerializerRegistry, as: :list

  defp maybe_validate(project, %ExportOptions{validate_before_export: true} = options) do
    case Validator.validate_project(project.id, options) do
      %{status: :errors} = result -> {:error, {:validation_failed, result}}
      _result -> {:ok, options}
    end
  end

  defp maybe_validate(_project, options), do: {:ok, options}
end

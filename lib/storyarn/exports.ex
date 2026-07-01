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

  alias Storyarn.Exports.DataCollector
  alias Storyarn.Exports.ExportOptions
  alias Storyarn.Exports.SerializerRegistry
  alias Storyarn.Exports.SizeGuard
  alias Storyarn.Exports.Validator
  alias Storyarn.Exports.Validator.ValidationResult

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
         :ok <- SizeGuard.ensure_within_limit(project.id, options),
         {:ok, options, preloaded} <- maybe_validate(project, options),
         {:ok, serializer} <- SerializerRegistry.get(options.format) do
      project_data = DataCollector.collect(project.id, options, preloaded)
      serializer.serialize(project_data, options)
    end
  end

  @doc """
  Validate a project for export without actually exporting.

  Returns a `%ValidationResult{}` with errors, warnings, and info items.
  """
  def validate_project(project_id, opts \\ %{})

  def validate_project(project_id, %ExportOptions{} = options) do
    case SizeGuard.ensure_within_limit(project_id, options) do
      :ok -> Validator.validate_project(project_id, options)
      {:error, {:export_too_large, details}} -> export_too_large_validation_result(project_id, details)
    end
  end

  def validate_project(project_id, opts) when is_map(opts) do
    case ExportOptions.new(opts) do
      {:ok, options} -> validate_project(project_id, options)
      {:error, _reason} -> Validator.validate_project(project_id, opts)
    end
  end

  def validate_project(project_id, _opts) do
    validate_project(project_id, %ExportOptions{format: :storyarn})
  end

  @doc """
  Count entities in a project for progress estimation.
  """
  defdelegate count_entities(project_id, opts), to: DataCollector, as: :count_entities

  @doc """
  List all formats with display metadata (label, extension, supported sections).
  """
  defdelegate list_formats_with_metadata(), to: SerializerRegistry, as: :list_with_metadata

  @doc """
  Get the serializer module for a given format atom.
  """
  defdelegate get_serializer(format), to: SerializerRegistry, as: :get

  @doc """
  Return the list of valid export format atoms.
  """
  defdelegate valid_export_formats(), to: ExportOptions, as: :valid_formats

  defp maybe_validate(project, %ExportOptions{validate_before_export: true} = options) do
    {result, preloaded} = Validator.validate_with_data(project.id, options)

    case result do
      %{status: :errors} -> {:error, {:validation_failed, result}}
      _result -> {:ok, options, preloaded}
    end
  end

  defp maybe_validate(_project, options), do: {:ok, options, %{}}

  defp export_too_large_validation_result(project_id, details) do
    %ValidationResult{
      status: :errors,
      errors: [
        %{
          level: :error,
          rule: :export_too_large,
          message: "Export is too large to validate safely",
          violations: details.violations
        }
      ],
      statistics: %{
        project_id: project_id,
        total_findings: 1,
        error_count: 1,
        warning_count: 0,
        info_count: 0
      }
    }
  end
end

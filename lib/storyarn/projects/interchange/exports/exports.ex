defmodule Storyarn.Projects.Exports do
  @moduledoc """
  Project-owned export capability.

  Handles project export in engine formats: Ink, Yarn Spinner, Unity, Godot,
  Unreal, and articy:draft XML. There is no native round-trip format.

  This internal facade delegates to specialized submodules:
  - `DataCollector` - Loads project data for export
  - `SerializerRegistry` - Resolves format atoms to serializer modules
  - `Validator` - Pre-export validation and health checks
  - `Serializers.*` - One module per engine format
  """

  alias Storyarn.Projects.Exports.DataCollector
  alias Storyarn.Projects.Exports.ExportOptions
  alias Storyarn.Projects.Exports.SerializerRegistry
  alias Storyarn.Projects.Exports.SizeGuard
  alias Storyarn.Projects.Exports.Validator
  alias Storyarn.Projects.Exports.Validator.ValidationResult
  alias Storyarn.Projects.Memberships
  alias Storyarn.Projects.Project

  require Logger

  @doc """
  Export a project to the specified format.

  ## Authorization

  This is the lower-level Project serializer entrypoint and does not authorize
  a user. Presentation and other external adapters MUST call
  `Storyarn.Projects.prepare_project_export/3`; that public use case repeats
  authorization and currently requires `:edit_content`.

  Direct calls are reserved for trusted Project-owned workflows that already
  hold the relevant authority, plus serializer tests. Authorization never
  belongs to a LiveView alone.

  ## Returns

  `{:ok, output}` where output is a binary or list of `{filename, content}` tuples,
  or `{:error, reason}`.

  ## Options

  See `Storyarn.Projects.Exports.ExportOptions` for all available options.

  ## Examples

      iex> Exports.export_project(project, %{format: :yarn})
      {:ok, [{"story.yarn", "..."}, {"metadata.json", "..."}]}

      iex> Exports.export_project(project, %{format: :ink})
      {:ok, [{"story.ink", "..."}, {"metadata.json", "..."}]}

  """
  def export_project(project, opts \\ %{})

  def export_project(project, %ExportOptions{} = options) do
    do_export_project(project, options)
  end

  def export_project(project, opts) when is_map(opts) do
    with {:ok, options} <- ExportOptions.new(opts) do
      do_export_project(project, options)
    end
  end

  defp do_export_project(project, options) do
    with :ok <- SizeGuard.ensure_within_limit(project.id, options),
         {:ok, options, preloaded} <- maybe_validate(project, options),
         {:ok, serializer} <- SerializerRegistry.get(options.format) do
      project_data = DataCollector.collect(project.id, options, preloaded)
      serialize_safely(serializer, project_data, options)
    end
  end

  @doc """
  Builds the transport-neutral download contract for an authorized project export.

  The presentation layer receives data and metadata, never the serializer
  module that implements the export format. Authorization is deliberately
  repeated here so callers cannot turn the lower-level serializer API into an
  unscoped project export.
  """
  @spec prepare_download(map(), Project.t(), map()) ::
          {:ok,
           %{
             required(:delivery) => :single | :archive,
             required(:content_type) => String.t(),
             required(:extension) => String.t(),
             required(:format) => atom(),
             optional(:body) => binary(),
             optional(:entries) => [{String.t(), iodata()}]
           }}
          | {:error, term()}
  def prepare_download(%{user: _} = scope, %Project{} = project, opts) when is_map(opts) do
    with {:ok, _project, _membership} <- Memberships.authorize(scope, project.id, :edit_content),
         {:ok, options} <- ExportOptions.new(opts),
         {:ok, serializer} <- SerializerRegistry.get(options.format),
         {:ok, output} <- export_project(project, options) do
      {:ok, download_contract(output, options.format, serializer)}
    end
  end

  def prepare_download(_scope, _project, _opts), do: {:error, :unauthorized}

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
      {:error, reason} -> invalid_options_validation_result(project_id, reason)
    end
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

  defp download_contract(output, format, serializer) when is_binary(output) do
    %{
      delivery: :single,
      body: output,
      content_type: serializer.content_type(),
      extension: serializer.file_extension(),
      format: format
    }
  end

  defp download_contract(entries, format, _serializer) when is_list(entries) do
    %{
      delivery: :archive,
      entries: entries,
      content_type: "application/zip",
      extension: "zip",
      format: format
    }
  end

  defp maybe_validate(project, %ExportOptions{validate_before_export: true} = options) do
    {result, preloaded} = Validator.validate_with_data(project.id, options)

    case result do
      %{status: :errors} -> {:error, {:validation_failed, result}}
      _result -> {:ok, options, preloaded}
    end
  end

  defp maybe_validate(_project, options), do: {:ok, options, %{}}

  defp serialize_safely(serializer, project_data, options) do
    serializer.serialize(project_data, options)
  rescue
    error ->
      Logger.error(
        "Export serializer #{inspect(serializer)} failed for #{options.format} with #{inspect(error.__struct__)}"
      )

      {:error, :serialization_failed}
  end

  # Options that do not parse are reported, not guessed at. This used to fall
  # through to the now-deleted native JSON format — so a caller that omitted or
  # misspelled the format silently got a validation pass for a different format
  # than the one it was about to export as.
  defp invalid_options_validation_result(project_id, reason) do
    %ValidationResult{
      status: :errors,
      errors: [
        %{
          level: :error,
          rule: :invalid_export_options,
          message: "Export options are invalid: #{inspect(reason)}"
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

defmodule Storyarn.Projects.Imports.Telemetry do
  @moduledoc """
  Import telemetry metadata and stop events.

  Every map built here is content-free by construction: format, source kind,
  parser version, status and an error code, and nothing that came out of the
  uploaded file. Filenames are reduced to an extension before they are ever
  read, so a metadata map cannot carry what the user named their script.
  """

  alias Storyarn.Projects.Imports.Error
  alias Storyarn.Projects.Imports.FormatRegistry

  def source_metadata(filename) do
    case FormatRegistry.source_for(filename) do
      {:ok, %{format: format, source_kind: source_kind}} ->
        %{
          format: Atom.to_string(format),
          source_kind: Atom.to_string(source_kind),
          parser_version: "unknown"
        }

      {:error, :unsupported_import_format} ->
        %{format: "unknown", source_kind: "file", parser_version: "unknown"}
    end
  end

  def plan_metadata(plan, status, error_code) do
    %{
      format: to_string(plan.format),
      source_kind: to_string(plan.source_kind),
      parser_version: plan.parser_version,
      status: status,
      error_code: error_code
    }
  end

  def attempt_metadata(attempt, status, error_code) do
    %{
      format: attempt.format,
      source_kind: attempt.source_kind,
      parser_version: attempt.parser_version,
      import_mode: attempt.import_mode,
      status: status,
      error_code: error_code
    }
  end

  def emit_snapshot_transition(attempt, state) when state in ["awaiting_snapshot", "ready"] do
    :telemetry.execute(
      [:storyarn, :import, :snapshot, :transition],
      %{count: 1},
      %{
        format: attempt.format,
        source_kind: attempt.source_kind,
        parser_version: attempt.parser_version,
        import_mode: attempt.import_mode,
        state: state
      }
    )
  end

  def report_prepare_error(reason, metadata, started_at) do
    {code, _message, _permanent?} = Error.classify(reason, Map.get(metadata, :format))
    Error.report(Map.merge(metadata, %{phase: "prepare", error_code: code, exception_module: "none"}))
    emit_stop(:prepare, started_at, Map.merge(metadata, %{status: "failed", error_code: code}))
  end

  def report_exception(phase, metadata, exception, started_at) do
    error_metadata = %{
      format: Map.get(metadata, :format, "unknown"),
      parser_version: Map.get(metadata, :parser_version, "unknown"),
      phase: to_string(phase),
      error_code: "exception",
      exception_module: inspect(exception.__struct__)
    }

    Error.report(error_metadata)
    emit_stop(phase, started_at, Map.merge(metadata, %{status: "failed", error_code: "exception"}))
  end

  def emit_stop(phase, started_at, metadata) do
    :telemetry.execute(
      [:storyarn, :import, phase, :stop],
      %{count: 1, duration: System.monotonic_time() - started_at},
      metadata
    )
  end
end

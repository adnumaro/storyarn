defmodule Storyarn.Projects.Imports.Error do
  @moduledoc false

  alias Storyarn.Projects.Imports.ErrorDeduplicator
  alias Storyarn.Projects.Imports.FormatRegistry

  @permanent_codes MapSet.new(~w(
    archive_entry_too_large
    archive_expansion_ratio_exceeded
    archive_too_large
    archive_too_many_entries
    duplicate_archive_entry
    entity_limits_exceeded
    file_too_large
    import_plan_has_errors
    import_plan_too_large
    import_expired
    import_project_replacement_failed
    import_replace_not_eligible
    import_review_too_large
    invalid_archive
    invalid_archive_entry
    invalid_archive_path
    invalid_json
    invalid_json_structure
    invalid_import_review
    invalid_import_mode
    invalid_import_snapshot_identity
    invalid_import_snapshot_request
    invalid_text_encoding
    nested_archive_not_allowed
    not_found
    ownership_invariant_violation
    pre_import_snapshot_capacity_unavailable
    pre_import_snapshot_unavailable
    pre_import_snapshot_verification_failed
    project_already_has_main_flow
    project_changed_since_import_snapshot
    replace_import_confirmation_required
    stale_import_mode
    unauthorized
    unsupported_archive_entry
    unsupported_import_format
  ))

  @spec classify(term(), atom() | String.t() | nil) :: {String.t(), String.t(), boolean()}
  def classify(reason, format \\ nil) do
    code = safe_code(reason)

    permanent? =
      MapSet.member?(@permanent_codes, code) or
        FormatRegistry.permanent_error_code?(format, code)

    message =
      if permanent?,
        do: "The import file could not be processed.",
        else: "The import could not be completed. It may be retried automatically."

    {code, message, permanent?}
  end

  @spec report(map()) :: :ok
  def report(metadata) do
    safe_metadata = %{
      format: Map.get(metadata, :format, "unknown"),
      parser_version: Map.get(metadata, :parser_version, "unknown"),
      import_mode: safe_import_mode(Map.get(metadata, :import_mode)),
      phase: Map.get(metadata, :phase, "unknown"),
      error_code: Map.get(metadata, :error_code, "unexpected_error"),
      exception_module: Map.get(metadata, :exception_module, "none")
    }

    safe_metadata
    |> reportable?()
    |> maybe_emit(safe_metadata)

    :ok
  end

  # Error reporting must never replace the error that the import pipeline is
  # already handling. If the bounded cache is restarting, unavailable, or
  # unresponsive, prefer one duplicate metric over losing the signal.
  defp reportable?(safe_metadata) do
    case ErrorDeduplicator.record(safe_metadata) do
      false -> false
      _fresh_or_unexpected -> true
    end
  rescue
    _exception -> true
  catch
    :exit, _reason -> true
    _kind, _reason -> true
  end

  defp maybe_emit(true, safe_metadata) do
    :telemetry.execute([:storyarn, :import, :error], %{count: 1}, safe_metadata)
  rescue
    _exception -> :ok
  catch
    _kind, _reason -> :ok
  end

  defp maybe_emit(false, _safe_metadata), do: :ok

  defp safe_import_mode(mode) when mode in ["additive", "replace_project"], do: mode
  defp safe_import_mode(_mode), do: "unknown"

  defp safe_code(reason) when is_atom(reason), do: to_string(reason)
  defp safe_code({reason, _details}) when is_atom(reason), do: to_string(reason)
  defp safe_code({reason, _one, _two}) when is_atom(reason), do: to_string(reason)
  defp safe_code(_reason), do: "unexpected_error"
end

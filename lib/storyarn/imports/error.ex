defmodule Storyarn.Imports.Error do
  @moduledoc false

  alias Storyarn.Imports.ErrorDeduplicator

  @permanent_codes ~w(
    archive_entry_too_large
    archive_expansion_ratio_exceeded
    archive_missing_yarn_files
    archive_too_large
    archive_too_many_entries
    duplicate_archive_entry
    duplicate_yarn_node_title
    empty_yarn_project
    file_too_large
    import_plan_has_errors
    invalid_archive
    invalid_archive_entry
    invalid_archive_path
    invalid_yarn_command
    invalid_json
    invalid_json_structure
    invalid_text_encoding
    missing_yarn_body_end
    missing_yarn_body_start
    missing_yarn_endif
    nested_archive_not_allowed
    not_found
    unauthorized
    unsupported_archive_entry
    unsupported_import_format
    yarn_document_limit_exceeded
    yarn_statement_limit_exceeded
  )

  @spec classify(term()) :: {String.t(), String.t(), boolean()}
  def classify(reason) do
    code = safe_code(reason)

    message =
      if code in Enum.map(@permanent_codes, &to_string/1),
        do: "The import file could not be processed.",
        else: "The import could not be completed. It may be retried automatically."

    {code, message, code in Enum.map(@permanent_codes, &to_string/1)}
  end

  @spec report(map()) :: :ok
  def report(metadata) do
    safe_metadata = %{
      format: Map.get(metadata, :format, "unknown"),
      parser_version: Map.get(metadata, :parser_version, "unknown"),
      phase: Map.get(metadata, :phase, "unknown"),
      error_code: Map.get(metadata, :error_code, "unexpected_error"),
      exception_module: Map.get(metadata, :exception_module, "none")
    }

    if ErrorDeduplicator.record(safe_metadata) do
      :telemetry.execute([:storyarn, :import, :error], %{count: 1}, safe_metadata)
    end

    :ok
  end

  defp safe_code(reason) when is_atom(reason), do: to_string(reason)
  defp safe_code({reason, _details}) when is_atom(reason), do: to_string(reason)
  defp safe_code({reason, _one, _two}) when is_atom(reason), do: to_string(reason)
  defp safe_code(_reason), do: "unexpected_error"
end

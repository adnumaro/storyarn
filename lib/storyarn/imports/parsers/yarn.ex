defmodule Storyarn.Imports.Parsers.Yarn do
  @moduledoc """
  Parser for the supported semantic subset of Yarn Spinner 2.x/3.x projects.

  The supported semantic core includes node headers, dialogue, options,
  conditionals, declarations, assignments, jumps, detours, returns, and stops.
  Unknown side-effect commands are retained as annotated nodes and reported as
  warnings. Unsupported state or control-flow semantics are errors so an import
  can never silently weaken narrative logic.
  """

  @behaviour Storyarn.Imports.Parser

  alias Storyarn.Imports.ImportPlan
  alias Storyarn.Imports.Parsers.Yarn.Document
  alias Storyarn.Imports.Parsers.Yarn.Normalizer
  alias Storyarn.Imports.SourceBundle

  @parser_version "3"
  @max_documents 500
  @max_statements_per_document 5_000
  @max_total_statements 100_000
  @max_total_source_lines 125_000
  @max_line_bytes 100_000
  @max_issues 1_000

  @impl true
  def format, do: :yarn

  @impl true
  def parser_version, do: @parser_version

  @impl true
  def parse(%SourceBundle{} = bundle) do
    with files when files != [] <- SourceBundle.yarn_files(bundle),
         {:ok, documents, document_issues} <-
           Document.parse_files(files,
             max_documents: @max_documents,
             max_statements_per_document: @max_statements_per_document,
             max_total_statements: @max_total_statements,
             max_total_source_lines: @max_total_source_lines,
             max_line_bytes: @max_line_bytes
           ),
         false <- documents == [],
         {:ok, data, normalization_issues, metadata} <- Normalizer.normalize(documents) do
      issues = limit_issues(document_issues ++ normalization_issues)
      metadata = issue_metadata(metadata, issues)

      plan = %ImportPlan{
        format: format(),
        parser_version: parser_version(),
        source_kind: bundle.kind,
        data: data,
        issues: issues,
        metadata: metadata
      }

      {:ok, plan}
    else
      [] -> {:error, :archive_missing_yarn_files}
      true -> {:error, :empty_yarn_project}
      {:error, reason} -> {:error, reason}
    end
  end

  defp limit_issues(issues) do
    {errors, warnings} = Enum.split_with(issues, &(&1.severity == :error))
    Enum.take(errors ++ warnings, @max_issues)
  end

  defp issue_metadata(metadata, issues) do
    metadata
    |> Map.put(:warning_count, Enum.count(issues, &(&1.severity == :warning)))
    |> Map.put(:error_count, Enum.count(issues, &(&1.severity == :error)))
  end
end

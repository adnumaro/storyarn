defmodule Storyarn.Projects.Imports.Parsers.Yarn do
  @moduledoc """
  Parser for the supported semantic subset of Yarn Spinner 2.x/3.x projects.

  The supported semantic core includes node headers, dialogue, options,
  conditionals, declarations, assignments, jumps, detours, returns, and stops.
  Unknown side-effect commands are retained as annotated nodes and reported as
  warnings. Unsupported state or control-flow semantics are errors so an import
  can never silently weaken narrative logic.
  """

  @behaviour Storyarn.Projects.Imports.Parser

  alias Storyarn.Projects.Imports.ImportPlan
  alias Storyarn.Projects.Imports.Parsers.Yarn.Document
  alias Storyarn.Projects.Imports.Parsers.Yarn.Normalizer
  alias Storyarn.Projects.Imports.Parsers.Yarn.SourceProfile
  alias Storyarn.Projects.Imports.SourceBundle

  @parser_version "5"
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
  defdelegate open_source(filename, binary), to: SourceProfile, as: :open

  @impl true
  def parse(%SourceBundle{} = bundle) do
    with files when files != [] <- SourceProfile.yarn_files(bundle),
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
      all_issues = document_issues ++ normalization_issues
      issues = limit_issues(all_issues)
      metadata = issue_metadata(metadata, all_issues, issues)
      data = put_compatibility_review(data, all_issues)

      plan = %ImportPlan{
        format: format(),
        parser_version: parser_version(),
        source_kind: bundle.kind,
        replace_eligible: SourceProfile.replace_eligible?(bundle),
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

  defp issue_metadata(metadata, all_issues, retained_issues) do
    counts_by_code =
      all_issues
      |> Enum.frequencies_by(& &1.code)
      |> Enum.sort()
      |> Map.new()

    metadata
    |> Map.put(:warning_count, Enum.count(all_issues, &(&1.severity == :warning)))
    |> Map.put(:error_count, Enum.count(all_issues, &(&1.severity == :error)))
    |> Map.put(:issue_count, length(all_issues))
    |> Map.put(:issues_truncated, length(retained_issues) < length(all_issues))
    |> Map.put(:issue_counts_by_code, counts_by_code)
  end

  defp put_compatibility_review(%{"import_review" => review} = data, issues) when is_map(review) do
    warning_counts_by_code =
      issues
      |> Enum.filter(&(&1.severity == :warning))
      |> Enum.frequencies_by(&Atom.to_string(&1.code))
      |> Enum.sort()
      |> Map.new()

    warning_count = Enum.sum(Map.values(warning_counts_by_code))

    review =
      review
      |> Map.put("compatibility_warning_count", warning_count)
      |> Map.put("compatibility_warning_counts_by_code", warning_counts_by_code)
      |> Map.update(
        "requires_acknowledgement",
        warning_count > 0,
        &(&1 or warning_count > 0)
      )

    Map.put(data, "import_review", review)
  end
end

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
  @max_issues 1_000

  @impl true
  def format, do: :yarn

  @impl true
  def parser_version, do: @parser_version

  @impl true
  def parse(%SourceBundle{} = bundle) do
    with files when files != [] <- SourceBundle.yarn_files(bundle),
         {:ok, documents, document_issues} <- Document.parse_files(files),
         false <- documents == [],
         :ok <- validate_document_limits(documents),
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

  defp validate_document_limits(documents) when length(documents) > @max_documents,
    do: {:error, :yarn_document_limit_exceeded}

  defp validate_document_limits(documents) do
    statement_counts = Enum.map(documents, &count_items(&1.body))

    cond do
      Enum.any?(statement_counts, &(&1 > @max_statements_per_document)) ->
        {:error, :yarn_statement_limit_exceeded}

      Enum.sum(statement_counts) > @max_total_statements ->
        {:error, :yarn_statement_limit_exceeded}

      true ->
        :ok
    end
  end

  defp count_items(items) do
    Enum.reduce(items, 0, fn
      {:options, options, _meta}, count ->
        count + 1 + Enum.sum(Enum.map(options, &count_items(&1.body)))

      {:if, branches, else_body, _meta}, count ->
        branch_count = Enum.sum(Enum.map(branches, &count_items(&1.body)))
        count + 1 + branch_count + count_items(else_body)

      _item, count ->
        count + 1
    end)
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

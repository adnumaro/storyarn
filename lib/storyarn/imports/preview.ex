defmodule Storyarn.Imports.Preview do
  @moduledoc """
  What an import would do, without doing any of it.

  The preview is built from the complete `ImportPlan`, never from its data map
  alone: blocking parser issues live on the plan, and accepting the bare map
  would let a caller preview a file whose issues were silently dropped.
  """

  alias Storyarn.Imports.ImportPlan
  alias Storyarn.Imports.Materializer

  @doc """
  Preview what an import would do without executing it.

  Requires the complete `ImportPlan` so blocking parser issues cannot be
  discarded by passing only its native data map.

  Returns a preview struct with entity counts and detected conflicts.
  """
  def preview(project_id, %ImportPlan{data: parsed_data} = plan) do
    if ImportPlan.error?(plan) do
      {:error, :import_plan_has_errors}
    else
      case Materializer.preview(project_id, parsed_data) do
        {:ok, preview} ->
          {:ok, Map.put(preview, :issue_summary, import_issue_summary(plan))}

        error ->
          error
      end
    end
  end

  def preview(_project_id, parsed_data) when is_map(parsed_data), do: {:error, :import_plan_required}

  defp import_issue_summary(%ImportPlan{metadata: metadata}) do
    %{
      warning_count: non_negative_metadata_count(metadata, :warning_count),
      error_count: non_negative_metadata_count(metadata, :error_count),
      issue_count: non_negative_metadata_count(metadata, :issue_count),
      issues_truncated: Map.get(metadata, :issues_truncated) == true,
      counts_by_code:
        metadata
        |> Map.get(:issue_counts_by_code, %{})
        |> Enum.filter(fn {code, count} ->
          (is_atom(code) or is_binary(code)) and is_integer(count) and count > 0
        end)
        |> Map.new(fn {code, count} -> {to_string(code), count} end)
    }
  end

  defp non_negative_metadata_count(metadata, key) do
    case Map.get(metadata, key, 0) do
      count when is_integer(count) and count >= 0 -> count
      _invalid -> 0
    end
  end
end

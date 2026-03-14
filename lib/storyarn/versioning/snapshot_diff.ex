defmodule Storyarn.Versioning.SnapshotDiff do
  @moduledoc """
  Central orchestrator for snapshot comparison.

  Delegates entity-specific diffing to builder modules and wraps
  their output into a structured result with stats and formatting.
  """

  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Versioning.{SnapshotBuilder, VersionCrud}

  @type change :: SnapshotBuilder.change()

  @type diff_result :: %{
          changes: [change()],
          stats: %{
            added: non_neg_integer(),
            modified: non_neg_integer(),
            removed: non_neg_integer()
          },
          has_changes: boolean()
        }

  @doc """
  Compares two snapshots and returns a structured diff result.

  Delegates to the appropriate builder's `diff_snapshots/2` and wraps
  the result with computed stats.
  """
  @spec diff(String.t(), map(), map()) :: diff_result()
  def diff(entity_type, old_snapshot, new_snapshot) do
    builder = VersionCrud.get_builder!(entity_type)
    changes = builder.diff_snapshots(old_snapshot, new_snapshot)
    wrap_result(changes)
  end

  @doc """
  Returns true if two snapshots have any differences.

  Uses a quick top-level field comparison first, only falling back to the
  full diff when the cheap check can't determine the answer.
  """
  @spec has_changes?(String.t(), map(), map()) :: boolean()
  def has_changes?(_entity_type, old_snapshot, new_snapshot)
      when old_snapshot == new_snapshot,
      do: false

  def has_changes?(entity_type, old_snapshot, new_snapshot) do
    diff(entity_type, old_snapshot, new_snapshot).has_changes
  end

  @doc """
  Converts a diff result or change list into a human-readable summary string.

  Accepts either a `diff_result` map or a raw `[change()]` list.
  """
  @spec format_summary(diff_result() | [change()]) :: String.t()
  def format_summary(%{changes: changes}), do: format_summary(changes)

  def format_summary([]), do: gettext("No changes detected")

  def format_summary(changes) when is_list(changes) do
    freqs = Enum.frequencies_by(changes, & &1.detail)

    changes
    |> Enum.uniq_by(& &1.detail)
    |> Enum.map_join(", ", fn change ->
      case Map.get(freqs, change.detail, 1) do
        1 -> change.detail
        n -> "#{change.detail} (×#{n})"
      end
    end)
  end

  defp wrap_result(changes) do
    stats =
      Enum.reduce(changes, %{added: 0, modified: 0, removed: 0}, fn change, acc ->
        Map.update!(acc, change.action, &(&1 + 1))
      end)

    %{changes: changes, stats: stats, has_changes: changes != []}
  end
end

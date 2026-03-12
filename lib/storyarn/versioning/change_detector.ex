defmodule Storyarn.Versioning.ChangeDetector do
  @moduledoc "Detects whether a project has changes since its last snapshot."

  import Ecto.Query

  alias Storyarn.Flows.Flow
  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Versioning.ProjectSnapshot

  @doc """
  Returns true if any entity was modified since the last project snapshot.
  """
  @spec project_changed_since_last_snapshot?(integer()) :: boolean()
  def project_changed_since_last_snapshot?(project_id) do
    case last_snapshot_time(project_id) do
      nil -> true
      last_time -> any_entity_modified_after?(project_id, last_time)
    end
  end

  @doc """
  Returns true if a manual snapshot was created within the given hours.
  """
  @spec recent_manual_snapshot?(integer(), pos_integer()) :: boolean()
  def recent_manual_snapshot?(project_id, hours \\ 6) do
    cutoff = DateTime.add(TimeHelpers.now(), -hours * 3600, :second)

    from(s in ProjectSnapshot,
      where: s.project_id == ^project_id and s.is_auto == false and s.inserted_at > ^cutoff
    )
    |> Repo.exists?()
  end

  defp last_snapshot_time(project_id) do
    from(s in ProjectSnapshot,
      where: s.project_id == ^project_id,
      select: max(s.inserted_at)
    )
    |> Repo.one()
  end

  defp any_entity_modified_after?(project_id, since) do
    Enum.any?([Sheet, Flow, Scene], fn schema ->
      from(e in schema,
        where:
          e.project_id == ^project_id and
            is_nil(e.deleted_at) and
            e.updated_at > ^since
      )
      |> Repo.exists?()
    end)
  end
end

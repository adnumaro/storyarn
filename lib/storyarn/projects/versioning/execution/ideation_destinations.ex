defmodule Storyarn.Projects.Versioning.IdeationDestinations do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Persistence.FlowRecord
  alias Storyarn.Projects.Persistence.LocalizedTextRecord
  alias Storyarn.Projects.Persistence.SceneRecord
  alias Storyarn.Projects.Persistence.SheetRecord
  alias Storyarn.Repo

  @max_id 9_223_372_036_854_775_807
  @max_targets 100_000
  @types ~w(sheet flow scene asset localization)

  # A sealed recovery read, not an application target-discovery API. Its caller
  # owns the authorized Project transaction and exclusive capture lock.
  def identities(project_id, targets)
      when is_integer(project_id) and project_id > 0 and project_id <= @max_id and is_list(targets) and
             length(targets) <= @max_targets do
    cond do
      not Repo.in_transaction?() -> {:error, :ideation_recovery_transaction_required}
      not Enum.all?(targets, &valid_target?/1) -> {:error, :invalid_ideation_recovery}
      true -> {:ok, capture_identities(project_id, targets)}
    end
  end

  def identities(_, _), do: {:error, :invalid_ideation_recovery}

  defp capture_identities(project_id, targets) do
    targets
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {type, ids} ->
      identities =
        ids
        |> Enum.uniq()
        |> Enum.chunk_every(1000)
        |> Enum.flat_map(fn chunk ->
          # Deleted rows retain their identity for exact undo; only missing or
          # replaced generations must be detached from the captured reference.
          type
          |> schema()
          |> where([row], row.project_id == ^project_id and row.id in ^chunk)
          |> select([row], {row.id, row.inserted_at})
          |> Repo.all()
        end)
        |> Map.new(fn {id, inserted_at} -> {id, "created:" <> DateTime.to_iso8601(inserted_at)} end)

      {type, identities}
    end)
  end

  defp valid_target?({type, id}), do: type in @types and is_integer(id) and id > 0 and id <= @max_id
  defp valid_target?(_), do: false
  defp schema("sheet"), do: SheetRecord
  defp schema("flow"), do: FlowRecord
  defp schema("scene"), do: SceneRecord
  defp schema("asset"), do: Asset
  defp schema("localization"), do: LocalizedTextRecord

  # Only the exact materialization receipts establish correspondence. A matching
  # title, shortcut or localization source tuple does not establish identity.
  def build(project_id, id_maps, asset_ids) do
    %{
      "sheet" => destinations(SheetRecord, project_id, Map.get(id_maps, :sheet, %{})),
      "flow" => destinations(FlowRecord, project_id, Map.get(id_maps, :flow, %{})),
      "scene" => destinations(SceneRecord, project_id, Map.get(id_maps, :scene, %{})),
      "asset" => destinations(Asset, project_id, asset_ids),
      # Canonical localization inventories retain source tuples, not row IDs.
      # Preserve history but detach instead of guessing a new translation row.
      "localization" => %{}
    }
  end

  defp destinations(_schema, _project_id, ids) when map_size(ids) == 0, do: %{}

  defp destinations(schema, project_id, ids) do
    target_ids = Map.values(ids)

    # Tombstones in an exact materialization receipt retain identity too. Their
    # ordinary target reader hides them until an authorized restore revives them.
    identities =
      schema
      |> where([row], row.project_id == ^project_id and row.id in ^target_ids)
      |> select([row], {row.id, row.inserted_at})
      |> Repo.all()
      |> Map.new(fn {id, inserted_at} ->
        {id, %{id: id, identity: "created:" <> DateTime.to_iso8601(inserted_at)}}
      end)

    for {source_id, target_id} <- ids, target = identities[target_id], into: %{}, do: {source_id, target}
  end
end

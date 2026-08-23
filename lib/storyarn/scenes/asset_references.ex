defmodule Storyarn.Scenes.AssetReferences do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Scenes.ProjectReferenceIntegrity
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Scenes.SceneZone

  @spec lock_active_for_restore(pos_integer(), keyword()) :: :ok | {:error, term()}
  def lock_active_for_restore(project_id, owner_ids)
      when is_integer(project_id) and project_id > 0 and is_list(owner_ids) do
    with {:ok, scene_ids} <- normalize_owner_ids(owner_ids),
         {:ok, _asset_ids} <-
           ProjectReferenceIntegrity.lock_active_references(
             project_id,
             reference_specs(scene_ids)
           ) do
      :ok
    end
  end

  def lock_active_for_restore(_project_id, _owner_ids), do: {:error, :invalid_asset_restore_owners}

  defp normalize_owner_ids(owner_ids) do
    if Keyword.keyword?(owner_ids) and Keyword.keys(owner_ids) -- [:scene_ids] == [] do
      ids = owner_ids |> Keyword.get(:scene_ids, []) |> List.wrap() |> Enum.uniq()

      if Enum.all?(ids, &(is_integer(&1) and &1 > 0)),
        do: {:ok, ids},
        else: {:error, :invalid_asset_restore_owners}
    else
      {:error, :invalid_asset_restore_owners}
    end
  end

  defp reference_specs([]), do: []

  defp reference_specs(scene_ids) do
    backgrounds =
      Repo.all(
        from scene in Scene,
          where: scene.id in ^scene_ids,
          select: {scene.id, scene.background_asset_id}
      )

    pins =
      Repo.all(
        from pin in ScenePin,
          where: pin.scene_id in ^scene_ids,
          select: {pin.id, pin.icon_asset_id}
      )

    zones =
      Repo.all(
        from zone in SceneZone,
          where: zone.scene_id in ^scene_ids,
          select: {zone.id, zone.label_icon_asset_id}
      )

    Enum.map(backgrounds, fn {scene_id, asset_id} ->
      {:asset, {:scene, scene_id, :background_asset_id}, asset_id}
    end) ++
      Enum.map(pins, fn {pin_id, asset_id} ->
        {:asset, {:scene_pin, pin_id, :icon_asset_id}, asset_id}
      end) ++
      Enum.map(zones, fn {zone_id, asset_id} ->
        {:asset, {:scene_zone, zone_id, :label_icon_asset_id}, asset_id}
      end)
  end
end

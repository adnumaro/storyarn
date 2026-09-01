defmodule Storyarn.Projects.Assets.AssetFamily do
  @moduledoc "Pure graph traversal for intrinsic original, web, and profile-variant asset families."

  alias Storyarn.Projects.Assets.Asset

  @spec component_ids([Asset.t()], [pos_integer()]) :: MapSet.t(pos_integer())
  def component_ids(assets, root_ids) when is_list(assets) and is_list(root_ids) do
    known_ids = MapSet.new(assets, & &1.id)

    adjacency =
      Enum.reduce(assets, Map.new(assets, &{&1.id, MapSet.new()}), fn asset, graph ->
        asset.metadata
        |> metadata_reference_ids()
        |> Enum.filter(&MapSet.member?(known_ids, &1))
        |> Enum.reduce(graph, fn referenced_id, graph ->
          graph
          |> Map.update!(asset.id, &MapSet.put(&1, referenced_id))
          |> Map.update!(referenced_id, &MapSet.put(&1, asset.id))
        end)
      end)

    walk_component(adjacency, MapSet.new(root_ids), root_ids)
  end

  defp walk_component(_adjacency, visited, []), do: visited

  defp walk_component(adjacency, visited, [id | rest]) do
    unseen = adjacency |> Map.get(id, MapSet.new()) |> MapSet.difference(visited)
    walk_component(adjacency, MapSet.union(visited, unseen), rest ++ MapSet.to_list(unseen))
  end

  defp metadata_reference_ids(metadata) when is_map(metadata) do
    case Asset.family_reference_ids(metadata) do
      {:ok, ids} -> Enum.uniq(ids)
      :error -> []
    end
  end

  defp metadata_reference_ids(_metadata), do: []
end

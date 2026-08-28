defmodule Storyarn.Scenes.Editor.Rules.Tree do
  @moduledoc false

  def build_tree_from_flat_list(scenes) do
    scenes
    |> Enum.group_by(& &1.parent_id)
    |> build_subtree(nil)
  end

  defp build_subtree(grouped, parent_id) do
    Enum.map(Map.get(grouped, parent_id, []), fn scene ->
      Map.put(scene, :children, build_subtree(grouped, scene.id))
    end)
  end
end

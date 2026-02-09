defmodule StoryarnWeb.Components.Sidebar.TreeHelpers do
  @moduledoc """
  Shared helper functions for sidebar tree components (sheets, flows, screenplays).
  """

  @doc "Returns true if the item has non-empty children."
  def has_children?(item) do
    case Map.get(item, :children) do
      nil -> false
      [] -> false
      children when is_list(children) -> true
      _ -> false
    end
  end

  @doc "Returns true if selected_id matches any item or descendant in the list."
  def has_selected_recursive?(items, selected_id) when is_binary(selected_id) do
    Enum.any?(items, fn item ->
      to_string(item.id) == selected_id or
        has_selected_recursive?(Map.get(item, :children, []), selected_id)
    end)
  end

  def has_selected_recursive?(_items, _selected_id), do: false
end

defmodule Storyarn.Screenplays.ElementGrouping do
  @moduledoc """
  Computes dialogue groups and logical element groups from adjacency.

  Dialogue groups are computed dynamically — no stored `group_id` (Edge Case F).
  This module provides O(n) single-pass algorithms over element lists.
  """

  alias Storyarn.Screenplays.ScreenplayElement

  @dialogue_group_types ScreenplayElement.dialogue_group_types()
  @non_mappeable_types ScreenplayElement.non_mappeable_types()

  @doc """
  Computes dialogue groups from element adjacency.

  Returns a list of `{element, group_id}` tuples where `group_id` is a
  generated string for elements in a dialogue group, or `nil` otherwise.

  Rules:
  - `character` starts a new group
  - `parenthetical` continues current group if preceded by `character` or `dialogue`
  - `dialogue` continues current group if preceded by `character` or `parenthetical`
  - Any other type breaks the current group (group_id = nil)
  """
  def compute_dialogue_groups([]), do: []

  def compute_dialogue_groups(elements) when is_list(elements) do
    {result, _state} =
      Enum.map_reduce(elements, %{group_id: nil, prev_type: nil}, fn element, state ->
        case compute_group_transition(element.type, state.prev_type, state.group_id) do
          {:new_group, group_id} ->
            {{element, group_id}, %{group_id: group_id, prev_type: element.type}}

          {:continue, group_id} ->
            {{element, group_id}, %{group_id: group_id, prev_type: element.type}}

          :break ->
            {{element, nil}, %{group_id: nil, prev_type: element.type}}
        end
      end)

    result
  end

  @doc """
  Groups consecutive elements into logical units for flow mapping.

  Returns a list of maps with the following shape:
  - `type` — atom: `:dialogue_group`, `:scene_heading`, `:action`, etc.
  - `elements` — list of elements in the group
  - `group_id` — string for dialogue groups, `nil` otherwise

  Grouping rules:
  - Consecutive character + parenthetical? + dialogue → `:dialogue_group`
  - Response after a dialogue group → attached to that group
  - Orphan response (no preceding dialogue group) → standalone `:response`
  - note, section, page_break, title_page → `:non_mappeable`
  - All other types → standalone group matching their type as atom
  """
  def group_elements([]), do: []

  def group_elements(elements) when is_list(elements) do
    annotated = compute_dialogue_groups(elements)

    annotated
    |> Enum.chunk_while(
      nil,
      fn {element, group_id}, acc ->
        chunk_element({element, group_id}, acc)
      end,
      fn
        nil -> {:cont, nil}
        acc -> {:cont, acc, nil}
      end
    )
    |> attach_responses()
  end

  # --- compute_dialogue_groups helpers ---

  defp compute_group_transition("character", _prev_type, _prev_group_id) do
    {:new_group, generate_group_id()}
  end

  defp compute_group_transition("parenthetical", prev_type, group_id)
       when prev_type in ["character", "dialogue"] and not is_nil(group_id) do
    {:continue, group_id}
  end

  defp compute_group_transition("dialogue", prev_type, group_id)
       when prev_type in ["character", "parenthetical"] and not is_nil(group_id) do
    {:continue, group_id}
  end

  defp compute_group_transition(type, _prev_type, _prev_group_id)
       when type in @dialogue_group_types do
    # Orphan dialogue/parenthetical without proper predecessor
    :break
  end

  defp compute_group_transition(_type, _prev_type, _prev_group_id) do
    :break
  end

  # --- group_elements helpers ---

  defp chunk_element({element, group_id}, nil) do
    {:cont, build_group(element, group_id)}
  end

  defp chunk_element({element, group_id}, acc) do
    if not is_nil(group_id) and group_id == acc.group_id do
      {:cont, %{acc | elements: acc.elements ++ [element]}}
    else
      {:cont, acc, build_group(element, group_id)}
    end
  end

  defp build_group(element, group_id) when not is_nil(group_id) do
    %{type: :dialogue_group, elements: [element], group_id: group_id}
  end

  defp build_group(element, nil) do
    type = classify_element_type(element.type)
    %{type: type, elements: [element], group_id: nil}
  end

  defp classify_element_type(type) when type in @non_mappeable_types, do: :non_mappeable
  # Safe: input is validated against a fixed allowlist in ScreenplayElement.create_changeset
  defp classify_element_type(type), do: String.to_atom(type)

  defp attach_responses(groups) do
    {result, _} =
      Enum.map_reduce(groups, nil, fn group, prev ->
        case group do
          %{type: :response} when not is_nil(prev) and prev.type == :dialogue_group ->
            merged = %{prev | elements: prev.elements ++ group.elements}
            {merged, merged}

          _ ->
            {group, group}
        end
      end)

    # Deduplicate: when a response merges into the preceding dialogue_group,
    # both the original group and the merged version are emitted. We need
    # to collapse them so only the merged version remains.
    deduplicate_merged(result)
  end

  defp deduplicate_merged([]), do: []

  defp deduplicate_merged(groups) do
    groups
    |> Enum.chunk_every(2, 1, [:end])
    |> Enum.flat_map(fn
      [current, next] when is_map(next) ->
        if current.type == :dialogue_group and next.type == :dialogue_group and
             current.group_id == next.group_id do
          # This group was merged into next — skip it
          []
        else
          [current]
        end

      [current, :end] ->
        [current]
    end)
  end

  defp generate_group_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end

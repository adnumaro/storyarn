defmodule Storyarn.Screenplays.ReverseNodeMapping do
  @moduledoc """
  Pure functions that convert flow nodes into screenplay element attribute maps.

  Used by `FlowSync.sync_from_flow/1` to determine what elements to create/update.
  Exact inverse of `NodeMapping.group_to_node_attrs/2`.
  No side effects — all functions are deterministic and database-free.
  """

  alias Storyarn.Flows
  alias Storyarn.Flows.FlowNode

  @doc """
  Converts a single flow node into a list of element attr maps.

  Each attr map has: `type`, `content`, `data`, and `source_node_id`.
  A dialogue node may expand into 2-4 elements (character, parenthetical, dialogue, response).
  Returns an empty list for non-mappeable types (e.g. subflow).
  """
  @spec node_to_element_attrs(FlowNode.t()) :: [map()]
  def node_to_element_attrs(%FlowNode{} = node) do
    map_node(node)
  end

  @doc """
  Converts an ordered list of flow nodes into a flat list of element attr maps.

  Expands each node via `node_to_element_attrs/1` and concatenates results.
  """
  @spec nodes_to_element_attrs([FlowNode.t()]) :: [map()]
  def nodes_to_element_attrs(nodes) when is_list(nodes) do
    Enum.flat_map(nodes, &node_to_element_attrs/1)
  end

  # ---------------------------------------------------------------------------
  # Node type dispatch
  # ---------------------------------------------------------------------------

  defp map_node(%FlowNode{type: "entry"} = node), do: map_entry(node)
  defp map_node(%FlowNode{type: "scene"} = node), do: map_scene(node)
  defp map_node(%FlowNode{type: "dialogue"} = node), do: map_dialogue(node)
  defp map_node(%FlowNode{type: "condition"} = node), do: map_condition(node)
  defp map_node(%FlowNode{type: "instruction"} = node), do: map_instruction(node)
  defp map_node(%FlowNode{type: "exit"} = node), do: map_exit(node)
  defp map_node(%FlowNode{type: "hub"} = node), do: map_hub(node)
  defp map_node(%FlowNode{type: "jump"} = node), do: map_jump(node)
  defp map_node(%FlowNode{type: "subflow"}), do: []
  defp map_node(%FlowNode{}), do: []

  # ---------------------------------------------------------------------------
  # Entry → scene_heading
  # ---------------------------------------------------------------------------

  defp map_entry(%FlowNode{id: id}) do
    [%{type: "scene_heading", content: "INT. - DAY", data: nil, source_node_id: id}]
  end

  # ---------------------------------------------------------------------------
  # Scene → scene_heading (reconstructed from data)
  # ---------------------------------------------------------------------------

  defp map_scene(%FlowNode{id: id, data: data}) do
    [
      %{
        type: "scene_heading",
        content: reconstruct_scene_heading(data || %{}),
        data: nil,
        source_node_id: id
      }
    ]
  end

  defp reconstruct_scene_heading(data) do
    prefix =
      case data["int_ext"] do
        "ext" -> "EXT."
        _ -> "INT."
      end

    desc = data["description"] || ""
    time = data["time_of_day"]

    if time && time != "",
      do: "#{prefix} #{desc} - #{time}",
      else: "#{prefix} #{desc}"
  end

  # ---------------------------------------------------------------------------
  # Dialogue → character + parenthetical? + dialogue + response?
  # (or action if action-style)
  # ---------------------------------------------------------------------------

  defp map_dialogue(%FlowNode{id: id, data: data}) do
    data = data || %{}

    if data["dual_dialogue"] do
      map_dual_dialogue_reverse(id, data)
    else
      text = data["text"] || ""
      stage_directions = data["stage_directions"] || ""
      menu_text = data["menu_text"] || ""
      responses = data["responses"] || []
      speaker_sheet_id = data["speaker_sheet_id"]

      if action_style?(text, stage_directions, menu_text, responses) do
        [%{type: "action", content: stage_directions, data: nil, source_node_id: id}]
      else
        build_dialogue_elements(
          id,
          text,
          stage_directions,
          menu_text,
          responses,
          speaker_sheet_id
        )
      end
    end
  end

  defp action_style?(text, stage_directions, menu_text, responses) do
    text == "" and stage_directions != "" and responses == [] and menu_text == ""
  end

  defp build_dialogue_elements(id, text, stage_directions, menu_text, responses, speaker_sheet_id) do
    character_name = if menu_text != "", do: menu_text, else: "CHARACTER"

    character_data =
      if speaker_sheet_id, do: %{"sheet_id" => speaker_sheet_id}, else: nil

    elements = [
      %{type: "character", content: character_name, data: character_data, source_node_id: id}
    ]

    elements =
      if stage_directions != "",
        do:
          elements ++
            [%{type: "parenthetical", content: stage_directions, data: nil, source_node_id: id}],
        else: elements

    elements = elements ++ [%{type: "dialogue", content: text, data: nil, source_node_id: id}]

    if responses != [],
      do: elements ++ [map_response_element(id, responses)],
      else: elements
  end

  defp map_response_element(node_id, responses) do
    choices =
      Enum.map(responses, fn r ->
        %{
          "id" => r["id"],
          "text" => r["text"] || "",
          "condition" => deserialize_condition(r["condition"]),
          "instruction" => deserialize_instruction(r["instruction"]),
          "linked_screenplay_id" => r["linked_screenplay_id"]
        }
      end)

    %{type: "response", content: nil, data: %{"choices" => choices}, source_node_id: node_id}
  end

  # ---------------------------------------------------------------------------
  # Condition → conditional
  # ---------------------------------------------------------------------------

  defp map_condition(%FlowNode{id: id, data: data}) do
    condition = (data || %{})["condition"] || %{"logic" => "all", "rules" => []}

    [%{type: "conditional", content: nil, data: %{"condition" => condition}, source_node_id: id}]
  end

  # ---------------------------------------------------------------------------
  # Instruction → instruction
  # ---------------------------------------------------------------------------

  defp map_instruction(%FlowNode{id: id, data: data}) do
    assignments = (data || %{})["assignments"] || []

    [
      %{
        type: "instruction",
        content: nil,
        data: %{"assignments" => assignments},
        source_node_id: id
      }
    ]
  end

  # ---------------------------------------------------------------------------
  # Exit → transition
  # ---------------------------------------------------------------------------

  defp map_exit(%FlowNode{id: id, data: data}) do
    label = (data || %{})["label"] || ""

    [%{type: "transition", content: label, data: nil, source_node_id: id}]
  end

  # ---------------------------------------------------------------------------
  # Hub → hub_marker
  # ---------------------------------------------------------------------------

  defp map_hub(%FlowNode{id: id, data: data}) do
    data = data || %{}

    [
      %{
        type: "hub_marker",
        content: data["label"] || "",
        data: %{"hub_node_id" => data["hub_id"] || "", "color" => data["color"] || "#8b5cf6"},
        source_node_id: id
      }
    ]
  end

  # ---------------------------------------------------------------------------
  # Jump → jump_marker
  # ---------------------------------------------------------------------------

  defp map_jump(%FlowNode{id: id, data: data}) do
    [
      %{
        type: "jump_marker",
        content: nil,
        data: %{"target_hub_id" => (data || %{})["target_hub_id"] || ""},
        source_node_id: id
      }
    ]
  end

  # ---------------------------------------------------------------------------
  # Dual dialogue reverse mapping
  # ---------------------------------------------------------------------------

  defp map_dual_dialogue_reverse(id, data) do
    dual = data["dual_dialogue"] || %{}

    [
      %{
        type: "dual_dialogue",
        content: "",
        data: %{
          "left" => %{
            "character" => data["menu_text"] || "",
            "parenthetical" => non_empty_or_nil(data["stage_directions"]),
            "dialogue" => data["text"] || ""
          },
          "right" => %{
            "character" => dual["menu_text"] || "",
            "parenthetical" => non_empty_or_nil(dual["stage_directions"]),
            "dialogue" => dual["text"] || ""
          }
        },
        source_node_id: id
      }
    ]
  end

  defp non_empty_or_nil(nil), do: nil
  defp non_empty_or_nil(""), do: nil
  defp non_empty_or_nil(s), do: s

  # ---------------------------------------------------------------------------
  # Deserialization helpers
  # ---------------------------------------------------------------------------

  defp deserialize_condition(nil), do: nil
  defp deserialize_condition(condition) when is_map(condition), do: condition

  defp deserialize_condition(condition) when is_binary(condition),
    do: Flows.condition_parse(condition)

  defp deserialize_instruction(nil), do: nil
  defp deserialize_instruction(assignments) when is_list(assignments), do: assignments

  defp deserialize_instruction(instruction) when is_binary(instruction) do
    case Jason.decode(instruction) do
      {:ok, decoded} -> decoded
      {:error, _} -> nil
    end
  end
end

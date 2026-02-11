defmodule Storyarn.Screenplays.NodeMapping do
  @moduledoc """
  Pure functions that convert screenplay element groups into flow node attribute maps.

  Used by `FlowSync.sync_to_flow/1` to determine what nodes to create/update.
  No side effects — all functions are deterministic and database-free.
  """

  alias Storyarn.Flows.Condition

  @doc """
  Converts a list of element groups into a list of node attr maps.

  Skips non-mappeable groups and dual_dialogue (returns only mappeable entries).
  The first `scene_heading` group maps to an `entry` node; subsequent ones to `scene` nodes.
  """
  def groups_to_node_attrs(groups, opts \\ []) when is_list(groups) do
    offset = if Keyword.get(opts, :child_page, false), do: 1, else: 0

    groups
    |> Enum.with_index(offset)
    |> Enum.flat_map(fn {group, index} ->
      case group_to_node_attrs(group, index) do
        nil -> []
        attrs -> [attrs]
      end
    end)
  end

  @doc """
  Converts a single element group into a node attr map, or `nil` if non-mappeable.

  The `index` is the group's position in the full list (0-based).
  The first scene_heading (index 0 among scene_heading groups) maps to entry.
  """
  def group_to_node_attrs(group, index \\ 0)

  def group_to_node_attrs(%{type: :dialogue_group, elements: elements}, _index) do
    map_dialogue_group(elements)
  end

  def group_to_node_attrs(%{type: :scene_heading, elements: [element]}, index) do
    map_scene_heading(element, index)
  end

  def group_to_node_attrs(%{type: :action, elements: [element]}, _index) do
    map_action(element)
  end

  def group_to_node_attrs(%{type: :conditional, elements: [element]}, _index) do
    map_conditional(element)
  end

  def group_to_node_attrs(%{type: :instruction, elements: [element]}, _index) do
    map_instruction(element)
  end

  def group_to_node_attrs(%{type: :response, elements: [element]}, _index) do
    map_response_orphan(element)
  end

  def group_to_node_attrs(%{type: :transition, elements: [element]}, _index) do
    map_transition(element)
  end

  def group_to_node_attrs(%{type: :hub_marker, elements: [element]}, _index) do
    map_hub_marker(element)
  end

  def group_to_node_attrs(%{type: :jump_marker, elements: [element]}, _index) do
    map_jump_marker(element)
  end

  def group_to_node_attrs(%{type: :non_mappeable}, _index), do: nil
  def group_to_node_attrs(%{type: :dual_dialogue}, _index), do: nil
  def group_to_node_attrs(_group, _index), do: nil

  # ---------------------------------------------------------------------------
  # Private mapping functions
  # ---------------------------------------------------------------------------

  defp map_dialogue_group(elements) do
    character = Enum.find(elements, &(&1.type == "character"))
    parenthetical = Enum.find(elements, &(&1.type == "parenthetical"))
    dialogue = Enum.find(elements, &(&1.type == "dialogue"))
    response = Enum.find(elements, &(&1.type == "response"))

    data = %{
      "speaker_sheet_id" => nil,
      "text" => (dialogue && dialogue.content) || "",
      "stage_directions" => (parenthetical && parenthetical.content) || "",
      "menu_text" => (character && character.content) || "",
      "audio_asset_id" => nil,
      "technical_id" => "",
      "localization_id" => "",
      "input_condition" => "",
      "output_instruction" => "",
      "responses" => map_responses(response)
    }

    %{
      type: "dialogue",
      data: data,
      element_ids: Enum.map(elements, & &1.id),
      source: "screenplay_sync"
    }
  end

  defp map_scene_heading(element, 0) do
    %{
      type: "entry",
      data: %{},
      element_ids: [element.id],
      source: "screenplay_sync"
    }
  end

  defp map_scene_heading(element, _index) do
    parsed = parse_scene_heading(element.content || "")

    %{
      type: "scene",
      data: %{
        "location_sheet_id" => nil,
        "int_ext" => parsed.int_ext,
        "sub_location" => "",
        "time_of_day" => parsed.time_of_day,
        "description" => parsed.description,
        "technical_id" => ""
      },
      element_ids: [element.id],
      source: "screenplay_sync"
    }
  end

  defp map_action(element) do
    %{
      type: "dialogue",
      data: %{
        "speaker_sheet_id" => nil,
        "text" => "",
        "stage_directions" => element.content || "",
        "menu_text" => "",
        "audio_asset_id" => nil,
        "technical_id" => "",
        "localization_id" => "",
        "input_condition" => "",
        "output_instruction" => "",
        "responses" => []
      },
      element_ids: [element.id],
      source: "screenplay_sync"
    }
  end

  defp map_conditional(element) do
    condition = element.data["condition"] || %{"logic" => "all", "rules" => []}

    %{
      type: "condition",
      data: %{
        "condition" => condition,
        "switch_mode" => false
      },
      element_ids: [element.id],
      source: "screenplay_sync"
    }
  end

  defp map_instruction(element) do
    assignments = element.data["assignments"] || []

    %{
      type: "instruction",
      data: %{
        "assignments" => assignments,
        "description" => ""
      },
      element_ids: [element.id],
      source: "screenplay_sync"
    }
  end

  defp map_response_orphan(element) do
    %{
      type: "dialogue",
      data: %{
        "speaker_sheet_id" => nil,
        "text" => "",
        "stage_directions" => "",
        "menu_text" => "",
        "audio_asset_id" => nil,
        "technical_id" => "",
        "localization_id" => "",
        "input_condition" => "",
        "output_instruction" => "",
        "responses" => map_responses(element)
      },
      element_ids: [element.id],
      source: "screenplay_sync"
    }
  end

  defp map_transition(element) do
    %{
      type: "exit",
      data: %{
        "label" => element.content || "",
        "technical_id" => "",
        "outcome_tags" => [],
        "outcome_color" => "#22c55e",
        "exit_mode" => "terminal",
        "referenced_flow_id" => nil
      },
      element_ids: [element.id],
      source: "screenplay_sync"
    }
  end

  defp map_hub_marker(element) do
    %{
      type: "hub",
      data: %{
        "hub_id" => element.data["hub_node_id"] || "",
        "label" => element.content || "",
        "color" => element.data["color"] || "#8b5cf6"
      },
      element_ids: [element.id],
      source: "screenplay_sync"
    }
  end

  defp map_jump_marker(element) do
    %{
      type: "jump",
      data: %{
        "target_hub_id" => element.data["target_hub_id"] || ""
      },
      element_ids: [element.id],
      source: "screenplay_sync"
    }
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp map_responses(nil), do: []

  defp map_responses(%{data: data}) do
    (data["choices"] || [])
    |> Enum.map(fn choice ->
      %{
        "id" => choice["id"],
        "text" => choice["text"] || "",
        "condition" => serialize_condition(choice["condition"]),
        "instruction" => serialize_instruction(choice["instruction"]),
        "linked_screenplay_id" => choice["linked_screenplay_id"]
      }
    end)
  end

  defp serialize_condition(nil), do: nil
  defp serialize_condition(condition) when is_map(condition), do: Condition.to_json(condition)
  defp serialize_condition(condition) when is_binary(condition), do: condition

  defp serialize_instruction(nil), do: nil
  defp serialize_instruction(assignments) when is_list(assignments), do: Jason.encode!(assignments)
  defp serialize_instruction(instruction) when is_binary(instruction), do: instruction

  defp parse_scene_heading(content) do
    {int_ext, rest} =
      cond do
        String.match?(content, ~r/^INT\.?\s*\/\s*EXT\.?\s*/i) ->
          {"int", String.replace(content, ~r/^INT\.?\s*\/\s*EXT\.?\s*/i, "")}

        String.match?(content, ~r/^EXT\.?\s*/i) ->
          {"ext", String.replace(content, ~r/^EXT\.?\s*/i, "")}

        String.match?(content, ~r/^INT\.?\s*/i) ->
          {"int", String.replace(content, ~r/^INT\.?\s*/i, "")}

        true ->
          {"int", content}
      end

    {description, time_of_day} =
      case String.split(rest, ~r/\s+-\s+/, parts: 2) do
        [desc, time] -> {String.trim(desc), String.trim(time)}
        [desc] -> {String.trim(desc), ""}
      end

    %{int_ext: int_ext, description: description, time_of_day: time_of_day}
  end
end

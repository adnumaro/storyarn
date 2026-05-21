defmodule StoryarnWeb.SheetLive.Helpers.ReferencesDataHelpers do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias Storyarn.Flows
  alias Storyarn.Scenes
  alias Storyarn.Sheets

  def load_references_data(socket) do
    %{sheet: sheet, project: project, blocks: own_blocks, inherited_groups: inherited_groups} =
      socket.assigns

    all_blocks = Enum.flat_map(inherited_groups, & &1.blocks) ++ own_blocks

    variable_usage = build_variable_usage(all_blocks, sheet, project.id)
    backlinks = build_backlinks(sheet.id, project.id)
    scene_appearances = build_scene_appearances(sheet.id)

    assign(socket, :references_data, %{
      variable_usage: variable_usage,
      backlinks: backlinks,
      scene_appearances: scene_appearances
    })
  end

  defp build_variable_usage(all_blocks, sheet, project_id) do
    all_blocks
    |> Enum.filter(&variable_block?/1)
    |> Enum.map(fn block ->
      usage = Flows.check_stale_references(block.id, project_id)
      reads = Enum.filter(usage, &(&1.kind == "read"))
      writes = Enum.filter(usage, &(&1.kind == "write"))

      %{
        blockId: block.id,
        label: get_in(block.config, ["label"]) || block.variable_name,
        shortcut: "#{sheet.shortcut}.#{block.variable_name}",
        type: block.type,
        reads: Enum.map(reads, &serialize_usage_ref(&1, sheet, block)),
        writes: Enum.map(writes, &serialize_usage_ref(&1, sheet, block))
      }
    end)
    |> Enum.filter(fn v -> v.reads != [] || v.writes != [] end)
  end

  defp serialize_usage_ref(%{source_type: "scene_zone"} = ref, _sheet, _block) do
    %{
      sourceType: "scene_zone",
      sceneId: ref.scene_id,
      sceneName: ref.scene_name,
      zoneName: ref.zone_name,
      detail: format_zone_ref_detail(ref),
      stale: ref[:stale] || false
    }
  end

  defp serialize_usage_ref(ref, sheet, block) do
    %{
      sourceType: "flow_node",
      flowId: ref.flow_id,
      flowName: ref.flow_name,
      nodeId: ref.node_id,
      nodeType: ref.node_type,
      detail: format_ref_detail(ref, sheet, block),
      stale: ref[:stale] || false
    }
  end

  defp build_backlinks(sheet_id, project_id) do
    "sheet"
    |> Sheets.get_backlinks_with_sources(sheet_id, project_id)
    |> Enum.map(fn backlink ->
      si = backlink.source_info

      %{
        id: backlink.id,
        sourceId: backlink.source_id,
        sourceInfo: serialize_source_info(si),
        date: Calendar.strftime(backlink.inserted_at, "%b %d")
      }
    end)
  end

  defp serialize_source_info(%{type: :sheet} = si) do
    %{
      type: "sheet",
      name: si.sheet_name,
      shortcut: si[:sheet_shortcut],
      sheetId: si.sheet_id,
      contextType: si.block_type,
      contextLabel: si[:block_label]
    }
  end

  defp serialize_source_info(%{type: :flow} = si) do
    %{
      type: "flow",
      name: si.flow_name,
      shortcut: si[:flow_shortcut],
      flowId: si.flow_id,
      contextType: si[:node_type],
      contextLabel: nil
    }
  end

  defp serialize_source_info(%{type: :screenplay} = si) do
    %{
      type: "screenplay",
      name: si.screenplay_name,
      shortcut: nil,
      screenplayId: si.screenplay_id,
      contextType: si[:element_type],
      contextLabel: nil
    }
  end

  defp serialize_source_info(%{type: :scene} = si) do
    %{
      type: "scene",
      name: si.scene_name,
      shortcut: nil,
      sceneId: si.scene_id,
      contextType: si[:element_type],
      contextLabel: si[:element_label]
    }
  end

  defp build_scene_appearances(sheet_id) do
    %{zones: zones, pins: pins} = Scenes.get_elements_for_target("sheet", sheet_id)

    zone_items =
      Enum.map(zones, fn zone ->
        %{
          elementType: "zone",
          elementName: zone.name,
          sceneId: zone.scene.id,
          sceneName: zone.scene.name
        }
      end)

    pin_items =
      Enum.map(pins, fn pin ->
        %{
          elementType: "pin",
          elementName: pin.label,
          sceneId: pin.scene.id,
          sceneName: pin.scene.name
        }
      end)

    zone_items ++ pin_items
  end

  defp variable_block?(%{variable_name: nil}), do: false
  defp variable_block?(%{variable_name: ""}), do: false
  defp variable_block?(%{is_constant: true}), do: false
  defp variable_block?(%{type: "reference"}), do: false
  defp variable_block?(%{deleted_at: d}) when not is_nil(d), do: false
  defp variable_block?(_), do: true

  defp format_zone_ref_detail(ref) when ref.kind == "write" do
    assignments = (ref.zone_action_data || %{})["assignments"] || []

    matching =
      Enum.find(assignments, fn a ->
        a["sheet"] == ref.source_sheet and a["variable"] == ref.source_variable
      end)

    if matching, do: format_assignment_detail(matching)
  end

  defp format_zone_ref_detail(_ref), do: nil

  defp format_ref_detail(ref, _sheet, _block) when ref.kind == "write" do
    assignments = ref.node_data["assignments"] || []

    matching =
      Enum.find(assignments, fn a ->
        a["sheet"] == ref.source_sheet and a["variable"] == ref.source_variable
      end)

    if matching, do: format_assignment_detail(matching)
  end

  defp format_ref_detail(_ref, _sheet, _block), do: nil

  defp format_assignment_detail(%{"operator" => "set", "value" => v, "value_type" => "literal"}) when is_binary(v),
    do: "= #{v}"

  defp format_assignment_detail(%{"operator" => "add", "value" => v, "value_type" => "literal"}) when is_binary(v),
    do: "+= #{v}"

  defp format_assignment_detail(%{"operator" => "subtract", "value" => v, "value_type" => "literal"}) when is_binary(v),
    do: "-= #{v}"

  defp format_assignment_detail(%{"operator" => "set_true"}), do: "= true"
  defp format_assignment_detail(%{"operator" => "set_false"}), do: "= false"
  defp format_assignment_detail(%{"operator" => "toggle"}), do: "toggle"
  defp format_assignment_detail(%{"operator" => "clear"}), do: "clear"

  defp format_assignment_detail(%{"operator" => op, "value_type" => "variable_ref", "value_sheet" => vp, "value" => v})
       when is_binary(vp) and is_binary(v) do
    op_label =
      case op do
        "set" -> "="
        "add" -> "+="
        "subtract" -> "-="
        _ -> "="
      end

    "#{op_label} #{vp}.#{v}"
  end

  defp format_assignment_detail(_), do: nil
end

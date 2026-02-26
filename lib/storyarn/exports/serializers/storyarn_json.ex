defmodule Storyarn.Exports.Serializers.StoryarnJSON do
  @moduledoc """
  Native Storyarn JSON serializer.

  Produces a full-fidelity JSON export that preserves all project data
  for backup, migration, or external processing. Round-trip lossless:
  export → import = identical project data.
  """

  @behaviour Storyarn.Exports.Serializer

  alias Storyarn.Exports.ExportOptions
  alias Storyarn.Shared.TimeHelpers

  @impl true
  def content_type, do: "application/json"

  @impl true
  def file_extension, do: "json"

  @impl true
  def format_label, do: "Storyarn JSON"

  @impl true
  def supported_sections, do: [:sheets, :flows, :scenes, :screenplays, :localization, :assets]

  @impl true
  def serialize(project_data, %ExportOptions{} = opts) do
    result =
      %{
        "storyarn_version" => "1.0.0",
        "export_version" => opts.version,
        "exported_at" => DateTime.to_iso8601(TimeHelpers.now())
      }
      |> put_project(project_data.project)
      |> maybe_put_section("sheets", project_data.sheets, opts, :sheets, &serialize_sheets/1)
      |> maybe_put_section("flows", project_data.flows, opts, :flows, &serialize_flows/1)
      |> maybe_put_section("scenes", project_data.scenes, opts, :scenes, &serialize_scenes/1)
      |> maybe_put_section(
        "screenplays",
        project_data.screenplays,
        opts,
        :screenplays,
        &serialize_screenplays/1
      )
      |> maybe_put_section(
        "localization",
        project_data.localization,
        opts,
        :localization,
        &serialize_localization/1
      )
      |> maybe_put_section("assets", project_data.assets, opts, :assets, fn assets ->
        serialize_assets(assets, opts)
      end)
      |> put_metadata(project_data)

    json_opts = if opts.pretty_print, do: [pretty: true], else: []
    {:ok, Jason.encode!(result, json_opts)}
  end

  @impl true
  def serialize_to_file(_data, _file_path, _options, _callbacks) do
    # Streaming serialization planned for Phase E
    {:error, :not_implemented}
  end

  # -- Project --

  defp put_project(result, project) do
    Map.put(result, "project", %{
      "id" => to_string(project.id),
      "name" => project.name,
      "slug" => project.slug,
      "description" => project.description,
      "settings" => project.settings || %{}
    })
  end

  # -- Sheets --

  defp serialize_sheets(sheets) do
    Enum.map(sheets, &serialize_sheet/1)
  end

  defp serialize_sheet(sheet) do
    %{
      "id" => to_string(sheet.id),
      "shortcut" => sheet.shortcut,
      "name" => sheet.name,
      "description" => sheet.description,
      "color" => sheet.color,
      "parent_id" => maybe_to_string(sheet.parent_id),
      "position" => sheet.position,
      "avatar_asset_id" => maybe_to_string(sheet.avatar_asset_id),
      "banner_asset_id" => maybe_to_string(sheet.banner_asset_id),
      "hidden_inherited_block_ids" =>
        Enum.map(sheet.hidden_inherited_block_ids || [], &to_string/1),
      "current_version_id" => maybe_to_string(sheet.current_version_id),
      "blocks" => Enum.map(sheet.blocks, &serialize_block/1)
    }
  end

  defp serialize_block(block) do
    base = %{
      "id" => to_string(block.id),
      "type" => block.type,
      "position" => block.position,
      "config" => block.config || %{},
      "value" => block.value || %{},
      "is_constant" => block.is_constant,
      "variable_name" => block.variable_name,
      "scope" => block.scope,
      "required" => block.required,
      "detached" => block.detached,
      "inherited_from_block_id" => maybe_to_string(block.inherited_from_block_id),
      "column_group_id" => block.column_group_id,
      "column_index" => block.column_index
    }

    if block.type == "table" do
      Map.put(base, "table_data", %{
        "columns" => Enum.map(block.table_columns, &serialize_table_column/1),
        "rows" => Enum.map(block.table_rows, &serialize_table_row/1)
      })
    else
      base
    end
  end

  defp serialize_table_column(col) do
    %{
      "id" => to_string(col.id),
      "name" => col.name,
      "slug" => col.slug,
      "type" => col.type,
      "is_constant" => col.is_constant,
      "required" => col.required,
      "position" => col.position,
      "config" => col.config || %{}
    }
  end

  defp serialize_table_row(row) do
    %{
      "id" => to_string(row.id),
      "name" => row.name,
      "slug" => row.slug,
      "position" => row.position,
      "cells" => row.cells || %{}
    }
  end

  # -- Flows --

  defp serialize_flows(flows) do
    Enum.map(flows, &serialize_flow/1)
  end

  defp serialize_flow(flow) do
    %{
      "id" => to_string(flow.id),
      "shortcut" => flow.shortcut,
      "name" => flow.name,
      "description" => flow.description,
      "parent_id" => maybe_to_string(flow.parent_id),
      "position" => flow.position,
      "is_main" => flow.is_main,
      "settings" => flow.settings || %{},
      "scene_id" => maybe_to_string(flow.scene_id),
      "nodes" => Enum.map(flow.nodes, &serialize_node/1),
      "connections" => Enum.map(flow.connections, &serialize_connection/1)
    }
  end

  defp serialize_node(node) do
    %{
      "id" => to_string(node.id),
      "type" => node.type,
      "position_x" => node.position_x,
      "position_y" => node.position_y,
      "source" => node.source,
      "data" => serialize_node_data(node.type, node.data || %{})
    }
  end

  defp serialize_node_data("dialogue", data) do
    responses =
      (data["responses"] || [])
      |> Enum.map(fn resp ->
        resp
        |> Map.put("instruction_assignments", parse_response_instruction(resp["instruction"]))
      end)

    Map.put(data, "responses", responses)
  end

  defp serialize_node_data(_type, data), do: data

  defp parse_response_instruction(nil), do: []
  defp parse_response_instruction(""), do: []

  defp parse_response_instruction(instruction) when is_binary(instruction) do
    case Jason.decode(instruction) do
      {:ok, assignments} when is_list(assignments) -> assignments
      _ -> []
    end
  end

  defp parse_response_instruction(_), do: []

  defp serialize_connection(conn) do
    %{
      "id" => to_string(conn.id),
      "source_node_id" => to_string(conn.source_node_id),
      "source_pin" => conn.source_pin,
      "target_node_id" => to_string(conn.target_node_id),
      "target_pin" => conn.target_pin,
      "label" => conn.label
    }
  end

  # -- Scenes --

  defp serialize_scenes(scenes) do
    Enum.map(scenes, &serialize_scene/1)
  end

  defp serialize_scene(scene) do
    %{
      "id" => to_string(scene.id),
      "shortcut" => scene.shortcut,
      "name" => scene.name,
      "description" => scene.description,
      "parent_id" => maybe_to_string(scene.parent_id),
      "position" => scene.position,
      "background_asset_id" => maybe_to_string(scene.background_asset_id),
      "width" => scene.width,
      "height" => scene.height,
      "default_zoom" => scene.default_zoom,
      "default_center_x" => scene.default_center_x,
      "default_center_y" => scene.default_center_y,
      "scale_unit" => scene.scale_unit,
      "scale_value" => scene.scale_value,
      "layers" => Enum.map(scene.layers, &serialize_layer/1),
      "pins" => Enum.map(scene.pins, &serialize_pin/1),
      "zones" => Enum.map(scene.zones, &serialize_zone/1),
      "connections" => Enum.map(scene.connections, &serialize_scene_connection/1),
      "annotations" => Enum.map(scene.annotations, &serialize_annotation/1)
    }
  end

  defp serialize_layer(layer) do
    %{
      "id" => to_string(layer.id),
      "name" => layer.name,
      "is_default" => layer.is_default,
      "position" => layer.position,
      "visible" => layer.visible,
      "fog_enabled" => layer.fog_enabled,
      "fog_color" => layer.fog_color,
      "fog_opacity" => layer.fog_opacity
    }
  end

  defp serialize_pin(pin) do
    %{
      "id" => to_string(pin.id),
      "layer_id" => maybe_to_string(pin.layer_id),
      "position_x" => pin.position_x,
      "position_y" => pin.position_y,
      "pin_type" => pin.pin_type,
      "icon" => pin.icon,
      "color" => pin.color,
      "opacity" => pin.opacity,
      "label" => pin.label,
      "target_type" => pin.target_type,
      "target_id" => maybe_to_string(pin.target_id),
      "tooltip" => pin.tooltip,
      "size" => pin.size,
      "position" => pin.position,
      "locked" => pin.locked,
      "icon_asset_id" => maybe_to_string(pin.icon_asset_id),
      "sheet_id" => maybe_to_string(pin.sheet_id),
      "action_type" => pin.action_type,
      "action_data" => pin.action_data || %{},
      "condition" => pin.condition,
      "condition_effect" => pin.condition_effect
    }
  end

  defp serialize_zone(zone) do
    %{
      "id" => to_string(zone.id),
      "name" => zone.name,
      "layer_id" => maybe_to_string(zone.layer_id),
      "vertices" => zone.vertices || [],
      "fill_color" => zone.fill_color,
      "border_color" => zone.border_color,
      "border_width" => zone.border_width,
      "border_style" => zone.border_style,
      "opacity" => zone.opacity,
      "target_type" => zone.target_type,
      "target_id" => maybe_to_string(zone.target_id),
      "tooltip" => zone.tooltip,
      "position" => zone.position,
      "locked" => zone.locked,
      "action_type" => zone.action_type,
      "action_data" => zone.action_data || %{},
      "condition" => zone.condition,
      "condition_effect" => zone.condition_effect
    }
  end

  defp serialize_scene_connection(conn) do
    %{
      "id" => to_string(conn.id),
      "from_pin_id" => to_string(conn.from_pin_id),
      "to_pin_id" => to_string(conn.to_pin_id),
      "line_style" => conn.line_style,
      "line_width" => conn.line_width,
      "color" => conn.color,
      "label" => conn.label,
      "show_label" => conn.show_label,
      "bidirectional" => conn.bidirectional,
      "waypoints" => conn.waypoints || []
    }
  end

  defp serialize_annotation(ann) do
    %{
      "id" => to_string(ann.id),
      "text" => ann.text,
      "position_x" => ann.position_x,
      "position_y" => ann.position_y,
      "font_size" => ann.font_size,
      "color" => ann.color,
      "layer_id" => maybe_to_string(ann.layer_id),
      "position" => ann.position,
      "locked" => ann.locked
    }
  end

  # -- Screenplays --

  defp serialize_screenplays(screenplays) do
    Enum.map(screenplays, &serialize_screenplay/1)
  end

  defp serialize_screenplay(sp) do
    %{
      "id" => to_string(sp.id),
      "shortcut" => sp.shortcut,
      "name" => sp.name,
      "description" => sp.description,
      "parent_id" => maybe_to_string(sp.parent_id),
      "position" => sp.position,
      "linked_flow_id" => maybe_to_string(sp.linked_flow_id),
      "draft_label" => sp.draft_label,
      "draft_status" => sp.draft_status,
      "draft_of_id" => maybe_to_string(sp.draft_of_id),
      "elements" => Enum.map(sp.elements, &serialize_element/1)
    }
  end

  defp serialize_element(el) do
    %{
      "id" => to_string(el.id),
      "type" => el.type,
      "position" => el.position,
      "content" => el.content,
      "data" => el.data || %{},
      "depth" => el.depth,
      "branch" => el.branch,
      "linked_node_id" => maybe_to_string(el.linked_node_id)
    }
  end

  # -- Localization --

  defp serialize_localization(%{languages: languages, strings: strings, glossary: glossary}) do
    source_lang = Enum.find(languages, & &1.is_source)

    %{
      "source_language" => (source_lang && source_lang.locale_code) || "en",
      "languages" => Enum.map(languages, &serialize_language/1),
      "strings" => group_localized_texts(strings),
      "glossary" => group_glossary_entries(glossary)
    }
  end

  defp serialize_language(lang) do
    %{
      "locale_code" => lang.locale_code,
      "name" => lang.name,
      "is_source" => lang.is_source
    }
  end

  defp group_localized_texts(texts) do
    texts
    |> Enum.group_by(fn t -> {t.source_type, t.source_id, t.source_field} end)
    |> Enum.map(fn {{source_type, source_id, source_field}, locale_texts} ->
      first = List.first(locale_texts)

      translations =
        Map.new(locale_texts, fn t ->
          {t.locale_code,
           %{
             "translated_text" => t.translated_text,
             "status" => t.status,
             "vo_status" => t.vo_status,
             "vo_asset_id" => maybe_to_string(t.vo_asset_id),
             "translator_notes" => t.translator_notes,
             "reviewer_notes" => t.reviewer_notes,
             "word_count" => t.word_count,
             "machine_translated" => t.machine_translated,
             "last_translated_at" => maybe_to_iso8601(t.last_translated_at),
             "last_reviewed_at" => maybe_to_iso8601(t.last_reviewed_at)
           }}
        end)

      %{
        "source_type" => source_type,
        "source_id" => to_string(source_id),
        "source_field" => source_field,
        "source_text" => first.source_text,
        "source_text_hash" => first.source_text_hash,
        "speaker_sheet_id" => maybe_to_string(first.speaker_sheet_id),
        "translations" => translations
      }
    end)
  end

  defp group_glossary_entries(entries) do
    entries
    |> Enum.group_by(fn e -> {e.source_term, e.source_locale} end)
    |> Enum.map(fn {{source_term, source_locale}, group} ->
      first = List.first(group)

      translations =
        Map.new(group, fn e -> {e.target_locale, e.target_term} end)

      %{
        "source_term" => source_term,
        "source_locale" => source_locale,
        "translations" => translations,
        "do_not_translate" => first.do_not_translate,
        "context" => first.context
      }
    end)
  end

  # -- Assets --

  defp serialize_assets(assets, opts) do
    %{
      "mode" => to_string(opts.include_assets),
      "items" => Enum.map(assets, &serialize_asset/1)
    }
  end

  defp serialize_asset(asset) do
    %{
      "id" => to_string(asset.id),
      "filename" => asset.filename,
      "content_type" => asset.content_type,
      "size" => asset.size,
      "key" => asset.key,
      "url" => asset.url,
      "metadata" => asset.metadata || %{}
    }
  end

  # -- Metadata --

  defp put_metadata(result, project_data) do
    flows = project_data.flows || []

    {node_count, connection_count} =
      Enum.reduce(flows, {0, 0}, fn f, {nc, cc} ->
        {nc + length(f.nodes), cc + length(f.connections)}
      end)

    Map.put(result, "metadata", %{
      "statistics" => %{
        "sheet_count" => length(project_data.sheets || []),
        "flow_count" => length(flows),
        "node_count" => node_count,
        "connection_count" => connection_count,
        "scene_count" => length(project_data.scenes || []),
        "screenplay_count" => length(project_data.screenplays || []),
        "asset_count" => length(Map.get(project_data, :assets, []))
      }
    })
  end

  # -- Utilities --

  defp maybe_put_section(result, key, data, opts, section, serializer_fn) do
    if ExportOptions.include_section?(opts, section) do
      Map.put(result, key, serializer_fn.(data))
    else
      result
    end
  end

  defp maybe_to_string(nil), do: nil
  defp maybe_to_string(id), do: to_string(id)

  defp maybe_to_iso8601(nil), do: nil
  defp maybe_to_iso8601(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
end

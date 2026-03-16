defmodule Storyarn.Localization.LocalizableWords do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.{Flow, FlowConnection, FlowNode}
  alias Storyarn.Localization.{LanguageCrud, TextCrud}
  alias Storyarn.Repo
  alias Storyarn.Scenes.{Scene, SceneAnnotation, SceneConnection, SceneLayer, ScenePin, SceneZone}
  alias Storyarn.Shared.HtmlUtils
  alias Storyarn.Sheets.{Block, BlockGalleryImage, Sheet, TableColumn, TableRow}

  # =============================================================================
  # Public — Word Counts
  # =============================================================================

  @doc """
  Returns per-flow counts for all localizable words in the flow.
  """
  @spec flow_word_counts(integer()) :: %{integer() => non_neg_integer()}
  def flow_word_counts(project_id) do
    dialogue_counts =
      from(n in FlowNode,
        join: f in Flow,
        on: n.flow_id == f.id,
        where:
          f.project_id == ^project_id and is_nil(f.deleted_at) and is_nil(n.deleted_at) and
            n.type == "dialogue",
        group_by: n.flow_id,
        select: {n.flow_id, coalesce(sum(n.word_count), 0)}
      )
      |> Repo.all()
      |> Map.new()

    flows = load_project_flows(project_id)
    flow_connections = load_project_flow_connections(project_id) |> Enum.group_by(& &1.flow_id)

    flow_metadata_counts =
      flows
      |> Enum.map(fn flow ->
        {flow.id, count_fields(flow_source_fields(flow, Map.get(flow_connections, flow.id, [])))}
      end)
      |> Map.new()

    node_metadata_counts =
      project_flow_nodes(project_id, ["slug_line", "condition", "exit"])
      |> Enum.group_by(& &1.flow_id)
      |> Map.new(fn {flow_id, nodes} ->
        {flow_id, nodes |> Enum.map(&count_flow_node_non_denormalized_fields/1) |> Enum.sum()}
      end)

    merge_count_maps([dialogue_counts, flow_metadata_counts, node_metadata_counts])
  end

  @doc """
  Returns per-sheet counts for all localizable words in the sheet.
  """
  @spec sheet_word_counts(integer()) :: %{integer() => non_neg_integer()}
  def sheet_word_counts(project_id) do
    block_content_counts =
      from(b in Block,
        join: s in Sheet,
        on: b.sheet_id == s.id,
        where:
          s.project_id == ^project_id and is_nil(s.deleted_at) and is_nil(b.deleted_at) and
            b.word_count > 0,
        group_by: s.id,
        select: {s.id, coalesce(sum(b.word_count), 0)}
      )
      |> Repo.all()
      |> Map.new()

    sheets = load_project_sheets(project_id)
    blocks = load_project_blocks(project_id)

    sheet_counts =
      sheets
      |> Enum.map(fn sheet -> {sheet.id, count_fields(sheet_source_fields(sheet))} end)
      |> Map.new()

    block_counts =
      count_sheet_block_fields(blocks)

    merge_count_maps([sheet_counts, block_content_counts, block_counts])
  end

  @doc """
  Returns per-scene counts for all localizable words in the scene.
  """
  @spec scene_word_counts(integer()) :: %{integer() => non_neg_integer()}
  def scene_word_counts(project_id) do
    scenes = load_project_scenes(project_id)
    deps = load_scene_dependencies(Enum.map(scenes, & &1.id))

    scenes
    |> Enum.map(fn scene ->
      fields =
        scene_source_fields(scene, %{
          layers: Map.get(deps.layers, scene.id, []),
          zones: Map.get(deps.zones, scene.id, []),
          pins: Map.get(deps.pins, scene.id, []),
          annotations: Map.get(deps.annotations, scene.id, []),
          connections: Map.get(deps.connections, scene.id, [])
        })

      {scene.id, count_fields(fields)}
    end)
    |> Map.new()
  end

  # =============================================================================
  # Public — Extraction
  # =============================================================================

  @doc """
  Rebuilds all localizable texts for flows, sheets, blocks, and scenes in a project.
  """
  @spec extract_all(integer()) :: {:ok, non_neg_integer()}
  def extract_all(project_id) do
    target_locales = get_target_locales(project_id)

    if target_locales == [] do
      {:ok, 0}
    else
      flows = load_project_flows(project_id)
      flow_connections = load_project_flow_connections(project_id) |> Enum.group_by(& &1.flow_id)
      flow_nodes = project_flow_nodes(project_id)

      sheets = load_project_sheets(project_id)
      sheet_ids = Enum.map(sheets, & &1.id)
      blocks = project_blocks_for_sheet_ids(sheet_ids)
      block_dependencies = load_block_dependencies_for_ids(Enum.map(blocks, & &1.id))

      scenes = load_project_scenes(project_id)
      scene_ids = Enum.map(scenes, & &1.id)
      scene_dependencies = load_scene_dependencies(scene_ids)

      count =
        TextCrud.batch_upsert_texts(
          project_id,
          build_entries(flows, target_locales, "flow", & &1.id, fn flow ->
            flow_source_fields(flow, Map.get(flow_connections, flow.id, []))
          end)
        ) +
          TextCrud.batch_upsert_texts(
            project_id,
            build_entries(
              flow_nodes,
              target_locales,
              "flow_node",
              & &1.id,
              &flow_node_source_fields/1,
              fn node -> %{speaker_sheet_id: speaker_sheet_id(node)} end
            )
          ) +
          TextCrud.batch_upsert_texts(
            project_id,
            build_entries(sheets, target_locales, "sheet", & &1.id, &sheet_source_fields/1)
          ) +
          TextCrud.batch_upsert_texts(
            project_id,
            build_entries(blocks, target_locales, "block", & &1.id, fn block ->
              block_source_fields(block, block_dependencies_for(block.id, block_dependencies))
            end)
          ) +
          TextCrud.batch_upsert_texts(
            project_id,
            build_entries(scenes, target_locales, "scene", & &1.id, fn scene ->
              scene_source_fields(scene, scene_dependencies_for(scene.id, scene_dependencies))
            end)
          )

      {:ok, count}
    end
  end

  @spec extract_flow_node(FlowNode.t()) :: :ok
  def extract_flow_node(%FlowNode{} = node) do
    project_id = flow_project_id(node.flow_id)

    if project_id do
      target_locales = get_target_locales(project_id)

      if target_locales != [] do
        upsert_source_fields(
          project_id,
          "flow_node",
          node.id,
          flow_node_source_fields(node),
          target_locales,
          speaker_sheet_id: speaker_sheet_id(node)
        )
      end
    end

    :ok
  end

  @spec extract_flow(Flow.t()) :: :ok
  def extract_flow(%Flow{} = flow) do
    target_locales = get_target_locales(flow.project_id)

    if target_locales != [] do
      connections = load_flow_connections(flow.id)

      upsert_source_fields(
        flow.project_id,
        "flow",
        flow.id,
        flow_source_fields(flow, connections),
        target_locales
      )
    end

    :ok
  end

  @spec extract_sheet(Sheet.t()) :: :ok
  def extract_sheet(%Sheet{} = sheet) do
    target_locales = get_target_locales(sheet.project_id)

    if target_locales != [] do
      upsert_source_fields(
        sheet.project_id,
        "sheet",
        sheet.id,
        sheet_source_fields(sheet),
        target_locales
      )
    end

    :ok
  end

  @spec extract_block(Block.t()) :: :ok
  def extract_block(%Block{} = block) do
    project_id = sheet_project_id(block.sheet_id)

    if project_id do
      target_locales = get_target_locales(project_id)

      if target_locales != [] do
        upsert_source_fields(
          project_id,
          "block",
          block.id,
          block_source_fields(block),
          target_locales
        )
      end
    end

    :ok
  end

  @spec extract_scene(Scene.t()) :: :ok
  def extract_scene(%Scene{} = scene) do
    target_locales = get_target_locales(scene.project_id)

    if target_locales != [] do
      upsert_source_fields(
        scene.project_id,
        "scene",
        scene.id,
        scene_source_fields(scene),
        target_locales
      )
    end

    :ok
  end

  @spec delete_flow_node_texts(integer()) :: :ok
  def delete_flow_node_texts(node_id) do
    TextCrud.delete_texts_for_source("flow_node", node_id)
    :ok
  end

  @spec delete_flow_texts(integer()) :: :ok
  def delete_flow_texts(flow_id) do
    TextCrud.delete_texts_for_source("flow", flow_id)
    :ok
  end

  @spec delete_sheet_texts(integer()) :: :ok
  def delete_sheet_texts(sheet_id) do
    TextCrud.delete_texts_for_source("sheet", sheet_id)
    :ok
  end

  @spec delete_block_texts(integer()) :: :ok
  def delete_block_texts(block_id) do
    TextCrud.delete_texts_for_source("block", block_id)
    :ok
  end

  @spec delete_scene_texts(integer()) :: :ok
  def delete_scene_texts(scene_id) do
    TextCrud.delete_texts_for_source("scene", scene_id)
    :ok
  end

  # =============================================================================
  # Private — Flow Source Fields
  # =============================================================================

  defp flow_source_fields(%Flow{} = flow, connections) do
    base_entity_fields(flow.name, flow.description) ++
      Enum.flat_map(connections, &flow_connection_source_fields/1)
  end

  defp flow_connection_source_fields(%FlowConnection{id: id, label: label}) do
    optional_field("connection.#{id}.label", label)
  end

  defp flow_node_source_fields(%FlowNode{type: "dialogue", data: data}) do
    optional_field("text", data["text"]) ++
      optional_field("stage_directions", data["stage_directions"]) ++
      optional_field("menu_text", data["menu_text"]) ++
      indexed_text_fields("response", list_value(data["responses"]), &response_field/2)
  end

  defp flow_node_source_fields(%FlowNode{type: "slug_line", data: data}) do
    optional_field("location", data["location"]) ++
      optional_field("description", data["description"]) ++
      optional_field("sub_location", data["sub_location"]) ++
      optional_field("time_of_day", data["time_of_day"])
  end

  defp flow_node_source_fields(%FlowNode{type: "condition", data: data}) do
    indexed_text_fields("case", list_value(data["cases"]), &condition_case_field/2)
  end

  defp flow_node_source_fields(%FlowNode{type: "exit", data: data}) do
    optional_field("label", data["label"])
  end

  defp flow_node_source_fields(_node), do: []

  defp count_flow_node_non_denormalized_fields(%FlowNode{type: "dialogue"}), do: 0

  defp count_flow_node_non_denormalized_fields(%FlowNode{} = node) do
    node
    |> flow_node_source_fields()
    |> count_fields()
  end

  defp response_field(response, index) when is_map(response) do
    field_id = response["id"] || index
    optional_field("response.#{field_id}.text", response["text"])
  end

  defp response_field(_response, _index), do: []

  defp condition_case_field(case_data, index) when is_map(case_data) do
    field_id = case_data["id"] || index
    optional_field("case.#{field_id}.label", case_data["label"])
  end

  defp condition_case_field(_case_data, _index), do: []

  defp speaker_sheet_id(%FlowNode{type: "dialogue", data: data}), do: data["speaker_sheet_id"]
  defp speaker_sheet_id(_node), do: nil

  # =============================================================================
  # Private — Sheet / Block Source Fields
  # =============================================================================

  defp sheet_source_fields(%Sheet{} = sheet) do
    base_entity_fields(sheet.name, sheet.description)
  end

  defp block_source_fields(%Block{} = block) do
    block_source_fields(block, load_block_dependencies(block))
  end

  defp block_source_fields(%Block{} = block, dependencies) do
    block_metadata_source_fields(block, dependencies) ++ block_content_source_fields(block)
  end

  defp block_metadata_source_fields(%Block{} = block, dependencies) do
    base_fields =
      optional_field("config.label", get_in(block.config, ["label"])) ++
        optional_field("config.placeholder", get_in(block.config, ["placeholder"]))

    option_fields =
      if block.type in ["select", "multi_select"] do
        indexed_text_fields(
          "config.options",
          list_value(block.config["options"]),
          &block_option_field/2
        )
      else
        []
      end

    table_fields =
      Enum.flat_map(dependencies.columns, fn column ->
        optional_field("table_column.#{column.id}.name", column.name)
      end) ++
        Enum.flat_map(dependencies.rows, fn row ->
          optional_field("table_row.#{row.id}.name", row.name)
        end)

    gallery_fields =
      Enum.flat_map(dependencies.gallery_images, fn image ->
        optional_field("gallery_image.#{image.id}.label", image.label) ++
          optional_field("gallery_image.#{image.id}.description", image.description)
      end)

    base_fields ++ option_fields ++ table_fields ++ gallery_fields
  end

  defp block_content_source_fields(%Block{type: type, value: value})
       when type in ["text", "rich_text"] do
    optional_field("value.content", value["content"])
  end

  defp block_content_source_fields(_block), do: []

  defp block_option_field(option, index) when is_map(option) do
    field_id = option["key"] || option["value"] || option["label"] || index
    optional_field("config.options.#{field_id}", option["value"] || option["label"])
  end

  defp block_option_field(option, index) when is_binary(option) do
    optional_field("config.options.#{index}", option)
  end

  defp block_option_field(_option, _index), do: []

  # =============================================================================
  # Private — Scene Source Fields
  # =============================================================================

  defp scene_source_fields(%Scene{} = scene) do
    scene_source_fields(scene, load_single_scene_dependencies(scene.id))
  end

  defp scene_source_fields(%Scene{} = scene, dependencies) do
    base_entity_fields(scene.name, scene.description) ++
      Enum.flat_map(dependencies.layers, fn layer ->
        optional_field("layer.#{layer.id}.name", layer.name)
      end) ++
      Enum.flat_map(dependencies.zones, fn zone ->
        optional_field("zone.#{zone.id}.name", zone.name) ++
          optional_field("zone.#{zone.id}.tooltip", zone.tooltip)
      end) ++
      Enum.flat_map(dependencies.pins, fn pin ->
        optional_field("pin.#{pin.id}.label", pin.label) ++
          optional_field("pin.#{pin.id}.tooltip", pin.tooltip)
      end) ++
      Enum.flat_map(dependencies.annotations, fn annotation ->
        optional_field("annotation.#{annotation.id}.text", annotation.text)
      end) ++
      Enum.flat_map(dependencies.connections, fn connection ->
        optional_field("connection.#{connection.id}.label", connection.label)
      end)
  end

  # =============================================================================
  # Private — Extraction Helpers
  # =============================================================================

  defp upsert_source_fields(
         project_id,
         source_type,
         source_id,
         fields,
         target_locales,
         opts \\ []
       ) do
    speaker_sheet_id = Keyword.get(opts, :speaker_sheet_id)

    for {field, text} <- fields, locale <- target_locales do
      TextCrud.upsert_text(project_id, %{
        "source_type" => source_type,
        "source_id" => source_id,
        "source_field" => field,
        "source_text" => text,
        "source_text_hash" => hash(text),
        "locale_code" => locale,
        "word_count" => word_count(text),
        "speaker_sheet_id" => speaker_sheet_id
      })
    end

    cleanup_removed_fields(source_type, source_id, fields)
  end

  defp build_entries(
         records,
         target_locales,
         source_type,
         source_id_fun,
         source_fields_fun,
         opts_fun \\ fn _ -> %{} end
       ) do
    for record <- records,
        {field, text} <- source_fields_fun.(record),
        locale <- target_locales do
      extra = opts_fun.(record)

      %{
        "source_type" => source_type,
        "source_id" => source_id_fun.(record),
        "source_field" => field,
        "source_text" => text,
        "source_text_hash" => hash(text),
        "locale_code" => locale,
        "word_count" => word_count(text),
        "speaker_sheet_id" => Map.get(extra, :speaker_sheet_id)
      }
    end
  end

  defp cleanup_removed_fields(source_type, source_id, current_fields) do
    current_field_names = MapSet.new(current_fields, fn {field, _} -> field end)

    source_type
    |> TextCrud.get_texts_for_source(source_id)
    |> Enum.map(& &1.source_field)
    |> Enum.uniq()
    |> Enum.each(fn field ->
      if field not in current_field_names do
        TextCrud.delete_texts_for_source_field(source_type, source_id, field)
      end
    end)

    :ok
  end

  # =============================================================================
  # Private — Counting Helpers
  # =============================================================================

  defp count_sheet_block_fields(blocks) do
    block_dependencies = load_block_dependencies_for_ids(Enum.map(blocks, & &1.id))

    blocks
    |> Enum.group_by(& &1.sheet_id)
    |> Map.new(fn {sheet_id, sheet_blocks} ->
      count =
        Enum.reduce(sheet_blocks, 0, fn block, acc ->
          acc +
            count_fields(
              block_metadata_source_fields(
                block,
                block_dependencies_for(block.id, block_dependencies)
              )
            )
        end)

      {sheet_id, count}
    end)
  end

  defp count_fields(fields) do
    fields
    |> Enum.map(fn {_field, text} -> word_count(text) end)
    |> Enum.sum()
  end

  defp merge_count_maps(maps) do
    Enum.reduce(maps, %{}, fn counts, acc ->
      Map.merge(acc, counts, fn _id, left, right -> left + right end)
    end)
  end

  # =============================================================================
  # Private — Loading Helpers
  # =============================================================================

  defp load_project_flows(project_id) do
    from(f in Flow,
      where: f.project_id == ^project_id and is_nil(f.deleted_at),
      order_by: [asc: f.id]
    )
    |> Repo.all()
  end

  defp project_flow_nodes(project_id, types \\ nil) do
    query =
      from(n in FlowNode,
        join: f in Flow,
        on: n.flow_id == f.id,
        where: f.project_id == ^project_id and is_nil(f.deleted_at) and is_nil(n.deleted_at),
        order_by: [asc: n.id]
      )

    query =
      case types do
        nil -> query
        [] -> where(query, [n, _f], false)
        values -> where(query, [n, _f], n.type in ^values)
      end

    Repo.all(query)
  end

  defp load_project_flow_connections(project_id) do
    from(c in FlowConnection,
      join: f in Flow,
      on: c.flow_id == f.id,
      where: f.project_id == ^project_id and is_nil(f.deleted_at),
      order_by: [asc: c.id]
    )
    |> Repo.all()
  end

  defp load_flow_connections(flow_id) do
    from(c in FlowConnection,
      where: c.flow_id == ^flow_id,
      order_by: [asc: c.id]
    )
    |> Repo.all()
  end

  defp load_project_sheets(project_id) do
    from(s in Sheet,
      where: s.project_id == ^project_id and is_nil(s.deleted_at),
      order_by: [asc: s.id]
    )
    |> Repo.all()
  end

  defp project_blocks_for_sheet_ids([]), do: []

  defp project_blocks_for_sheet_ids(sheet_ids) do
    from(b in Block,
      join: s in Sheet,
      on: b.sheet_id == s.id,
      where: b.sheet_id in ^sheet_ids and is_nil(b.deleted_at) and is_nil(s.deleted_at),
      order_by: [asc: b.id]
    )
    |> Repo.all()
  end

  defp load_project_blocks(project_id) do
    project_id
    |> load_project_sheets()
    |> Enum.map(& &1.id)
    |> project_blocks_for_sheet_ids()
  end

  defp load_block_dependencies(%Block{id: block_id, type: "table"}) do
    block_dependencies_for(block_id, load_block_dependencies_for_ids([block_id]))
  end

  defp load_block_dependencies(%Block{id: block_id, type: "gallery"}) do
    block_dependencies_for(block_id, load_block_dependencies_for_ids([block_id]))
  end

  defp load_block_dependencies(_block) do
    %{columns: [], rows: [], gallery_images: []}
  end

  defp load_block_dependencies_for_ids(block_ids) do
    %{
      columns: load_table_columns(block_ids),
      rows: load_table_rows(block_ids),
      gallery_images: load_gallery_images(block_ids)
    }
  end

  defp load_table_columns([]), do: %{}

  defp load_table_columns(block_ids) do
    from(c in TableColumn,
      where: c.block_id in ^block_ids,
      order_by: [asc: c.id]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.block_id)
  end

  defp load_table_rows([]), do: %{}

  defp load_table_rows(block_ids) do
    from(r in TableRow,
      where: r.block_id in ^block_ids,
      order_by: [asc: r.id]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.block_id)
  end

  defp load_gallery_images([]), do: %{}

  defp load_gallery_images(block_ids) do
    from(i in BlockGalleryImage,
      where: i.block_id in ^block_ids,
      order_by: [asc: i.id]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.block_id)
  end

  defp load_project_scenes(project_id) do
    from(s in Scene,
      where: s.project_id == ^project_id and is_nil(s.deleted_at),
      order_by: [asc: s.id]
    )
    |> Repo.all()
  end

  defp load_single_scene_dependencies(scene_id) do
    deps = load_scene_dependencies([scene_id])

    scene_dependencies_for(scene_id, deps)
  end

  defp load_scene_dependencies(scene_ids) do
    %{
      layers: load_scene_layers(scene_ids),
      zones: load_scene_zones(scene_ids),
      pins: load_scene_pins(scene_ids),
      annotations: load_scene_annotations(scene_ids),
      connections: load_scene_connections(scene_ids)
    }
  end

  defp load_scene_layers([]), do: %{}

  defp load_scene_layers(scene_ids) do
    from(l in SceneLayer,
      where: l.scene_id in ^scene_ids,
      order_by: [asc: l.id]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.scene_id)
  end

  defp load_scene_zones([]), do: %{}

  defp load_scene_zones(scene_ids) do
    from(z in SceneZone,
      where: z.scene_id in ^scene_ids,
      order_by: [asc: z.id]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.scene_id)
  end

  defp load_scene_pins([]), do: %{}

  defp load_scene_pins(scene_ids) do
    from(p in ScenePin,
      where: p.scene_id in ^scene_ids,
      order_by: [asc: p.id]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.scene_id)
  end

  defp load_scene_annotations([]), do: %{}

  defp load_scene_annotations(scene_ids) do
    from(a in SceneAnnotation,
      where: a.scene_id in ^scene_ids,
      order_by: [asc: a.id]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.scene_id)
  end

  defp load_scene_connections([]), do: %{}

  defp load_scene_connections(scene_ids) do
    from(c in SceneConnection,
      where: c.scene_id in ^scene_ids,
      order_by: [asc: c.id]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.scene_id)
  end

  # =============================================================================
  # Private — Generic Helpers
  # =============================================================================

  defp flow_project_id(flow_id) do
    from(f in Flow, where: f.id == ^flow_id and is_nil(f.deleted_at), select: f.project_id)
    |> Repo.one()
  end

  defp sheet_project_id(sheet_id) do
    from(s in Sheet, where: s.id == ^sheet_id and is_nil(s.deleted_at), select: s.project_id)
    |> Repo.one()
  end

  defp get_target_locales(project_id) do
    project_id
    |> LanguageCrud.get_target_languages()
    |> Enum.map(& &1.locale_code)
  end

  defp base_entity_fields(name, description) do
    optional_field("name", name) ++ optional_field("description", description)
  end

  defp block_dependencies_for(block_id, dependencies) do
    %{
      columns: Map.get(dependencies.columns, block_id, []),
      rows: Map.get(dependencies.rows, block_id, []),
      gallery_images: Map.get(dependencies.gallery_images, block_id, [])
    }
  end

  defp scene_dependencies_for(scene_id, dependencies) do
    %{
      layers: Map.get(dependencies.layers, scene_id, []),
      zones: Map.get(dependencies.zones, scene_id, []),
      pins: Map.get(dependencies.pins, scene_id, []),
      annotations: Map.get(dependencies.annotations, scene_id, []),
      connections: Map.get(dependencies.connections, scene_id, [])
    }
  end

  defp optional_field(_field, nil), do: []
  defp optional_field(_field, ""), do: []

  defp optional_field(field, text) when is_binary(text) do
    if String.trim(text) == "" do
      []
    else
      [{field, text}]
    end
  end

  defp optional_field(_field, _value), do: []

  defp indexed_text_fields(_prefix, values, mapper) do
    values
    |> Enum.with_index()
    |> Enum.flat_map(fn {value, index} -> mapper.(value, index) end)
  end

  defp list_value(values) when is_list(values), do: values
  defp list_value(_values), do: []

  defp hash(text) when is_binary(text) do
    :crypto.hash(:sha256, text) |> Base.encode16(case: :lower)
  end

  defp hash(_), do: nil

  defp word_count(text), do: HtmlUtils.word_count(text)
end

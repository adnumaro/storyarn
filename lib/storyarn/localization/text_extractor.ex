defmodule Storyarn.Localization.TextExtractor do
  @moduledoc false

  alias Storyarn.Flows
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Localization.{LanguageCrud, TextCrud}
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Block

  # =============================================================================
  # Flow Node Extraction
  # =============================================================================

  @doc """
  Extracts localizable texts from a flow node after its data is updated.
  Creates/updates localized_text rows for each target language.
  """
  @spec extract_flow_node(FlowNode.t()) :: :ok
  def extract_flow_node(%FlowNode{} = node) do
    project_id = get_project_id_for_node(node)
    if project_id, do: do_extract_flow_node(node, project_id)
    :ok
  end

  @doc """
  Cleans up localized texts when a flow node is deleted.
  """
  @spec delete_flow_node_texts(integer()) :: :ok
  def delete_flow_node_texts(node_id) do
    TextCrud.delete_texts_for_source("flow_node", node_id)
    :ok
  end

  # =============================================================================
  # Block Extraction
  # =============================================================================

  @doc """
  Extracts localizable texts from a block after its value or config is updated.
  """
  @spec extract_block(Block.t()) :: :ok
  def extract_block(%Block{} = block) do
    project_id = get_project_id_for_block(block)
    if project_id, do: do_extract_block(block, project_id)
    :ok
  end

  @doc """
  Cleans up localized texts when a block is deleted.
  """
  @spec delete_block_texts(integer()) :: :ok
  def delete_block_texts(block_id) do
    TextCrud.delete_texts_for_source("block", block_id)
    :ok
  end

  # =============================================================================
  # Sheet Extraction
  # =============================================================================

  @doc """
  Extracts localizable texts from a sheet after its metadata is updated.
  """
  @spec extract_sheet(Storyarn.Sheets.Sheet.t()) :: :ok
  def extract_sheet(%Storyarn.Sheets.Sheet{} = sheet) do
    target_locales = get_target_locales(sheet.project_id)
    if target_locales != [], do: do_extract_sheet(sheet, target_locales)
    :ok
  end

  @doc """
  Cleans up localized texts when a sheet is deleted.
  """
  @spec delete_sheet_texts(integer()) :: :ok
  def delete_sheet_texts(sheet_id) do
    TextCrud.delete_texts_for_source("sheet", sheet_id)
    :ok
  end

  # =============================================================================
  # Flow Extraction
  # =============================================================================

  @doc """
  Extracts localizable texts from a flow after its metadata is updated.
  """
  @spec extract_flow(Storyarn.Flows.Flow.t()) :: :ok
  def extract_flow(%Storyarn.Flows.Flow{} = flow) do
    target_locales = get_target_locales(flow.project_id)
    if target_locales != [], do: do_extract_flow(flow, target_locales)
    :ok
  end

  @doc """
  Cleans up localized texts when a flow is deleted.
  """
  @spec delete_flow_texts(integer()) :: :ok
  def delete_flow_texts(flow_id) do
    TextCrud.delete_texts_for_source("flow", flow_id)
    :ok
  end

  # =============================================================================
  # Bulk Extraction
  # =============================================================================

  @doc """
  Extracts all localizable texts for an entire project.

  Iterates over all flows, flow nodes, sheets, and blocks, creating
  localized_text rows for every target language. Safe to call multiple
  times — uses upsert so existing rows are updated, not duplicated.

  Returns `{:ok, count}` with the total number of text entries upserted.
  """
  @spec extract_all(integer()) :: {:ok, non_neg_integer()}
  def extract_all(project_id) do
    target_locales = get_target_locales(project_id)

    if target_locales == [] do
      {:ok, 0}
    else
      count = 0

      # Flows
      flows = Flows.list_flows(project_id)

      count = count + extract_many_flows(flows, target_locales)

      # Flow nodes (through flows)
      flow_ids = Enum.map(flows, & &1.id)

      nodes = Flows.list_nodes_for_flow_ids(flow_ids)

      count = count + extract_many_nodes(nodes, project_id, target_locales)

      # Sheets
      sheets = Sheets.list_all_sheets(project_id)

      count = count + extract_many_sheets(sheets, target_locales)

      # Blocks (through sheets)
      sheet_ids = Enum.map(sheets, & &1.id)

      blocks = Sheets.list_blocks_for_sheet_ids(sheet_ids)

      count = count + extract_many_blocks(blocks, project_id, target_locales)

      {:ok, count}
    end
  end

  defp extract_many_flows(flows, target_locales) do
    Enum.reduce(flows, 0, fn flow, acc ->
      fields = []
      fields = if non_blank?(flow.name), do: [{"name", flow.name} | fields], else: fields

      fields =
        if non_blank?(flow.description),
          do: [{"description", flow.description} | fields],
          else: fields

      upserted =
        for {field, text} <- fields, locale <- target_locales do
          TextCrud.upsert_text(flow.project_id, %{
            "source_type" => "flow",
            "source_id" => flow.id,
            "source_field" => field,
            "source_text" => text,
            "source_text_hash" => hash(text),
            "locale_code" => locale,
            "word_count" => word_count(text)
          })
        end

      acc + length(upserted)
    end)
  end

  defp extract_many_nodes(nodes, project_id, target_locales) do
    Enum.reduce(nodes, 0, fn node, acc ->
      fields = extract_node_fields(node)
      speaker_sheet_id = get_speaker_sheet_id(node)

      upserted =
        for {field, text} <- fields, locale <- target_locales do
          TextCrud.upsert_text(project_id, %{
            "source_type" => "flow_node",
            "source_id" => node.id,
            "source_field" => field,
            "source_text" => text,
            "source_text_hash" => hash(text),
            "locale_code" => locale,
            "word_count" => word_count(text),
            "speaker_sheet_id" => speaker_sheet_id
          })
        end

      acc + length(upserted)
    end)
  end

  defp extract_many_sheets(sheets, target_locales) do
    Enum.reduce(sheets, 0, fn sheet, acc ->
      fields = []
      fields = if non_blank?(sheet.name), do: [{"name", sheet.name} | fields], else: fields

      fields =
        if non_blank?(sheet.description),
          do: [{"description", sheet.description} | fields],
          else: fields

      upserted =
        for {field, text} <- fields, locale <- target_locales do
          TextCrud.upsert_text(sheet.project_id, %{
            "source_type" => "sheet",
            "source_id" => sheet.id,
            "source_field" => field,
            "source_text" => text,
            "source_text_hash" => hash(text),
            "locale_code" => locale,
            "word_count" => word_count(text)
          })
        end

      acc + length(upserted)
    end)
  end

  defp extract_many_blocks(blocks, project_id, target_locales) do
    Enum.reduce(blocks, 0, fn block, acc ->
      fields = extract_block_fields(block)

      upserted =
        for {field, text} <- fields, locale <- target_locales do
          TextCrud.upsert_text(project_id, %{
            "source_type" => "block",
            "source_id" => block.id,
            "source_field" => field,
            "source_text" => text,
            "source_text_hash" => hash(text),
            "locale_code" => locale,
            "word_count" => word_count(text)
          })
        end

      acc + length(upserted)
    end)
  end

  # =============================================================================
  # Private — Flow Node
  # =============================================================================

  defp do_extract_flow_node(node, project_id) do
    target_locales = get_target_locales(project_id)
    if target_locales == [], do: :ok

    fields = extract_node_fields(node)
    speaker_sheet_id = get_speaker_sheet_id(node)

    for {field, text} <- fields, locale <- target_locales do
      TextCrud.upsert_text(project_id, %{
        "source_type" => "flow_node",
        "source_id" => node.id,
        "source_field" => field,
        "source_text" => text,
        "source_text_hash" => hash(text),
        "locale_code" => locale,
        "word_count" => word_count(text),
        "speaker_sheet_id" => speaker_sheet_id
      })
    end

    # Clean up fields that no longer exist (e.g., removed responses)
    cleanup_removed_fields(project_id, "flow_node", node.id, fields)
  end

  defp extract_node_fields(%FlowNode{type: "dialogue", data: data}) do
    fields = []

    fields =
      if non_blank?(data["text"]),
        do: [{"text", data["text"]} | fields],
        else: fields

    fields =
      if non_blank?(data["stage_directions"]),
        do: [{"stage_directions", data["stage_directions"]} | fields],
        else: fields

    fields =
      if non_blank?(data["menu_text"]),
        do: [{"menu_text", data["menu_text"]} | fields],
        else: fields

    # Extract response texts
    responses = data["responses"] || []

    response_fields =
      for response <- responses,
          non_blank?(response["text"]),
          do: {"response.#{response["id"]}.text", response["text"]}

    fields ++ response_fields
  end

  defp extract_node_fields(%FlowNode{type: "scene", data: data}) do
    fields = []

    fields =
      if non_blank?(data["description"]),
        do: [{"description", data["description"]} | fields],
        else: fields

    fields
  end

  defp extract_node_fields(%FlowNode{type: "exit", data: data}) do
    if non_blank?(data["label"]),
      do: [{"label", data["label"]}],
      else: []
  end

  defp extract_node_fields(_node), do: []

  defp get_speaker_sheet_id(%FlowNode{type: "dialogue", data: data}) do
    data["speaker_sheet_id"]
  end

  defp get_speaker_sheet_id(_node), do: nil

  # =============================================================================
  # Private — Block
  # =============================================================================

  defp do_extract_block(block, project_id) do
    target_locales = get_target_locales(project_id)
    if target_locales == [], do: :ok

    fields = extract_block_fields(block)

    for {field, text} <- fields, locale <- target_locales do
      TextCrud.upsert_text(project_id, %{
        "source_type" => "block",
        "source_id" => block.id,
        "source_field" => field,
        "source_text" => text,
        "source_text_hash" => hash(text),
        "locale_code" => locale,
        "word_count" => word_count(text)
      })
    end

    cleanup_removed_fields(project_id, "block", block.id, fields)
  end

  defp extract_block_fields(%Block{type: "text", value: value, config: config}) do
    fields = []

    # Block label from config
    fields =
      if non_blank?(config["label"]),
        do: [{"config.label", config["label"]} | fields],
        else: fields

    # Text content from value
    fields =
      if non_blank?(value["content"]),
        do: [{"value.content", value["content"]} | fields],
        else: fields

    fields
  end

  defp extract_block_fields(%Block{type: "select", config: config}) do
    fields = []

    fields =
      if non_blank?(config["label"]),
        do: [{"config.label", config["label"]} | fields],
        else: fields

    # Select options
    options = config["options"] || []

    option_fields =
      for option <- options,
          is_map(option),
          non_blank?(option["label"]),
          do: {"config.options.#{option["key"] || option["value"]}", option["label"]}

    fields ++ option_fields
  end

  defp extract_block_fields(%Block{config: config}) do
    # For other block types, only extract label
    if non_blank?(config["label"]),
      do: [{"config.label", config["label"]}],
      else: []
  end

  # =============================================================================
  # Private — Sheet
  # =============================================================================

  defp do_extract_sheet(sheet, target_locales) do
    fields = []

    fields =
      if non_blank?(sheet.name),
        do: [{"name", sheet.name} | fields],
        else: fields

    fields =
      if non_blank?(sheet.description),
        do: [{"description", sheet.description} | fields],
        else: fields

    for {field, text} <- fields, locale <- target_locales do
      TextCrud.upsert_text(sheet.project_id, %{
        "source_type" => "sheet",
        "source_id" => sheet.id,
        "source_field" => field,
        "source_text" => text,
        "source_text_hash" => hash(text),
        "locale_code" => locale,
        "word_count" => word_count(text)
      })
    end
  end

  # =============================================================================
  # Private — Flow
  # =============================================================================

  defp do_extract_flow(flow, target_locales) do
    fields = []

    fields =
      if non_blank?(flow.name),
        do: [{"name", flow.name} | fields],
        else: fields

    fields =
      if non_blank?(flow.description),
        do: [{"description", flow.description} | fields],
        else: fields

    for {field, text} <- fields, locale <- target_locales do
      TextCrud.upsert_text(flow.project_id, %{
        "source_type" => "flow",
        "source_id" => flow.id,
        "source_field" => field,
        "source_text" => text,
        "source_text_hash" => hash(text),
        "locale_code" => locale,
        "word_count" => word_count(text)
      })
    end
  end

  # =============================================================================
  # Private — Helpers
  # =============================================================================

  defp get_project_id_for_node(%FlowNode{flow_id: flow_id}) do
    Flows.get_flow_project_id(flow_id)
  end

  defp get_project_id_for_block(%Block{sheet_id: sheet_id}) do
    Sheets.get_sheet_project_id(sheet_id)
  end

  defp get_target_locales(project_id) do
    project_id
    |> LanguageCrud.get_target_languages()
    |> Enum.map(& &1.locale_code)
  end

  defp hash(text) when is_binary(text) do
    :crypto.hash(:sha256, text) |> Base.encode16(case: :lower)
  end

  defp hash(_), do: nil

  defp word_count(text) when is_binary(text) do
    text
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.split(~r/\s+/, trim: true)
    |> length()
  end

  defp word_count(_), do: 0

  defp non_blank?(nil), do: false
  defp non_blank?(""), do: false
  defp non_blank?(text) when is_binary(text), do: String.trim(text) != ""
  defp non_blank?(_), do: false

  defp cleanup_removed_fields(_project_id, source_type, source_id, current_fields) do
    current_field_names = MapSet.new(current_fields, fn {field, _} -> field end)

    existing_texts =
      TextCrud.get_texts_for_source(source_type, source_id)

    # Group by field — only need to check once per field (not per locale)
    existing_fields =
      existing_texts
      |> Enum.map(& &1.source_field)
      |> Enum.uniq()

    for field <- existing_fields, field not in current_field_names do
      TextCrud.delete_texts_for_source_field(source_type, source_id, field)
    end

    :ok
  end
end

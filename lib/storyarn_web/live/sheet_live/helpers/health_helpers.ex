defmodule StoryarnWeb.SheetLive.Helpers.HealthHelpers do
  @moduledoc """
  Builds the enriched snapshot used by the sheet health checker and serializes
  its findings for the Vue header.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Storyarn.Flows
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.HealthChecker

  @empty_health %{errorItems: [], warningItems: [], infoItems: []}

  @doc "Returns an empty health payload suitable for the initial socket assign."
  def empty_health, do: @empty_health

  @doc "Enriches the current sheet snapshot, checks it, and assigns its UI payload."
  def assign_sheet_health(socket) do
    %{sheet: sheet, project: project, blocks: own_blocks, inherited_groups: inherited_groups} = socket.assigns

    all_blocks = Enum.flat_map(inherited_groups, & &1.blocks) ++ own_blocks
    block_ids = Enum.map(all_blocks, & &1.id)
    referenced_block_ids = Flows.referenced_block_ids(block_ids)

    snapshot = %{
      sheet: sheet,
      blocks: all_blocks,
      table_data: socket.assigns.table_data,
      gallery_data: socket.assigns.gallery_data,
      has_children: Sheets.get_children(sheet.id) != [],
      inheritance_issues: Sheets.list_inheritance_health_issues(sheet.id),
      referenced_block_ids: referenced_block_ids,
      stale_variable_reference_counts: stale_variable_reference_counts(all_blocks, referenced_block_ids, project.id),
      stale_entity_reference_block_ids: Sheets.list_stale_block_reference_source_ids(project.id, block_ids),
      reference_targets: reference_targets(all_blocks, project.id),
      project_variable_types: project_variable_types(project.id)
    }

    findings = HealthChecker.check(snapshot)
    assign(socket, :sheet_health, health_payload(findings, sheet, all_blocks, socket.assigns.table_data))
  end

  @doc "Serializes checker findings into stable, grouped UI payloads."
  def health_payload(findings, sheet, blocks, table_data) do
    context = health_label_context(sheet, blocks, table_data)

    %{
      errorItems: health_items(findings, :error, context),
      warningItems: health_items(findings, :warning, context),
      infoItems: health_items(findings, :info, context)
    }
  end

  defp stale_variable_reference_counts(blocks, referenced_block_ids, project_id) do
    blocks
    |> Enum.filter(&(MapSet.member?(referenced_block_ids, &1.id) and Block.variable?(&1)))
    |> Map.new(fn block ->
      count = block.id |> Flows.check_stale_references(project_id) |> Enum.count(&(&1[:stale] == true))
      {block.id, count}
    end)
  end

  defp reference_targets(blocks, project_id) do
    blocks
    |> Enum.filter(&(&1.type == "reference"))
    |> Map.new(fn block ->
      target_type = get_in(block.value || %{}, ["target_type"])
      target_id = get_in(block.value || %{}, ["target_id"])
      {block.id, Sheets.get_reference_target(target_type, target_id, project_id)}
    end)
  end

  defp project_variable_types(project_id) do
    project_id
    |> Sheets.list_project_variables()
    |> Map.new(fn variable ->
      reference = "#{variable.sheet_shortcut}.#{variable.variable_name}"
      {reference, variable.block_type}
    end)
  end

  defp health_items(findings, severity, context) do
    findings
    |> Enum.filter(&(&1.severity == severity))
    |> Enum.group_by(&{&1.block_id, &1.row_id, &1.column_id})
    |> Enum.map(fn {_location, grouped_findings} -> health_item(grouped_findings, context) end)
    |> Enum.sort_by(&{is_nil(&1.blockId), &1.label, &1.rowId || 0, &1.columnId || 0})
  end

  defp health_item([finding | _] = findings, context) do
    %{
      blockId: finding.block_id,
      rowId: finding.row_id,
      columnId: finding.column_id,
      label: health_label(finding, context),
      reasons:
        Enum.map(findings, fn item ->
          %{code: Atom.to_string(item.code), details: item.details}
        end)
    }
  end

  defp health_label(%{block_id: nil}, context), do: context.sheet_name

  defp health_label(%{block_id: block_id, row_id: row_id, column_id: column_id}, context) do
    block_label = Map.get(context.block_labels, block_id, "Block ##{block_id}")

    case {row_id, column_id} do
      {nil, nil} ->
        block_label

      {row_id, nil} ->
        "#{block_label} · #{Map.get(context.row_labels, row_id, "Row ##{row_id}")}"

      {nil, column_id} ->
        "#{block_label} · #{Map.get(context.column_labels, column_id, "Column ##{column_id}")}"

      {row_id, column_id} ->
        row_label = Map.get(context.row_labels, row_id, "Row ##{row_id}")
        column_label = Map.get(context.column_labels, column_id, "Column ##{column_id}")
        "#{block_label} · #{row_label} · #{column_label}"
    end
  end

  defp health_label_context(sheet, blocks, table_data) do
    block_labels =
      Map.new(blocks, fn block ->
        label = get_in(block.config || %{}, ["label"])
        {block.id, present_label(label, "#{humanize_type(block.type)} ##{block.id}")}
      end)

    {row_labels, column_labels} =
      Enum.reduce(table_data, {%{}, %{}}, fn {_block_id, table}, {rows, columns} ->
        row_labels = Map.new(table.rows, &{&1.id, present_label(&1.name, "Row ##{&1.id}")})
        column_labels = Map.new(table.columns, &{&1.id, present_label(&1.name, "Column ##{&1.id}")})
        {Map.merge(rows, row_labels), Map.merge(columns, column_labels)}
      end)

    %{
      sheet_name: present_label(sheet.name, "Sheet"),
      block_labels: block_labels,
      row_labels: row_labels,
      column_labels: column_labels
    }
  end

  defp present_label(value, fallback) when is_binary(value) do
    if String.trim(value) == "", do: fallback, else: value
  end

  defp present_label(_value, fallback), do: fallback

  defp humanize_type(type) when is_binary(type), do: type |> String.replace("_", " ") |> String.capitalize()
  defp humanize_type(_type), do: "Block"
end

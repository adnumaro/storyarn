defmodule StoryarnWeb.SheetLive.Helpers.HealthHelpers do
  @moduledoc """
  Serializes sheet health findings for the Vue header.

  The check itself runs through `Sheets.sheet_health_findings/1` — the same
  composition point the project-wide dashboard sweep enters — so the editor and
  the dashboard cannot feed the checker differently for the same sheet. What is
  left here is presentation: grouping findings by location and naming that
  location.
  """

  use Gettext, backend: Storyarn.Gettext

  import Phoenix.Component, only: [assign: 3]

  alias Storyarn.Platform.Shared.StringUtils
  alias Storyarn.Sheets

  @empty_health %{errorItems: [], warningItems: [], infoItems: []}

  @doc "Returns an empty health payload suitable for the initial socket assign."
  def empty_health, do: @empty_health

  @doc "Checks the current sheet assigns and stores their grouped UI payload."
  def assign_sheet_health(socket) do
    assigns = socket.assigns
    material = health_material(assigns)
    findings = Sheets.sheet_health_findings(material)

    assign(
      socket,
      :sheet_health,
      health_payload(findings, assigns.sheet, labelled_blocks(material), material.table_data)
    )
  end

  defp health_material(assigns) do
    %{
      sheet: assigns.sheet,
      project: assigns.project,
      blocks: assigns.blocks,
      inherited_groups: assigns.inherited_groups,
      table_data: assigns.table_data,
      gallery_data: assigns.gallery_data
    }
  end

  # Order does not matter here — these blocks only feed a `Map.new/2` of labels.
  # The order that DOES matter (which block of a column group carries an
  # `invalid_block_layout`) is assembled once inside `Sheets.HealthSnapshots`.
  defp labelled_blocks(%{blocks: own_blocks, inherited_groups: inherited_groups}) do
    Enum.flat_map(inherited_groups, & &1.blocks) ++ own_blocks
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

  @doc """
  The human name of a block type.

  A clause per type rather than `String.capitalize/1` over the column value: a DB
  enum humanized in Elixir is English no catalog can translate, so a Spanish user
  read "Multi select" in a list the editor calls "Selección múltiple". Shared with
  `StoryarnWeb.SheetLive.Index`, which names the same blocks on the dashboard.

  `nil` is the generic word, for a finding built without a block type. An unknown
  type raises rather than leaking the enum into the UI — a type added to
  `Sheets.Block` and not here should fail loudly, not render in one language.
  """
  @spec block_type_label(String.t() | nil) :: String.t()
  def block_type_label(nil), do: dgettext("sheets", "Block")
  def block_type_label("text"), do: dgettext("sheets", "Text")
  def block_type_label("rich_text"), do: dgettext("sheets", "Rich Text")
  def block_type_label("number"), do: dgettext("sheets", "Number")
  def block_type_label("select"), do: dgettext("sheets", "Select")
  def block_type_label("multi_select"), do: dgettext("sheets", "Multi Select")
  def block_type_label("date"), do: dgettext("sheets", "Date")
  def block_type_label("boolean"), do: dgettext("sheets", "Boolean")
  def block_type_label("reference"), do: dgettext("sheets", "Reference")
  def block_type_label("table"), do: dgettext("sheets", "Table")
  def block_type_label("gallery"), do: dgettext("sheets", "Gallery")
  def block_type_label("formula"), do: dgettext("sheets", "Formula")

  @doc "Names a block by type and id when it carries no label of its own."
  @spec block_identifier(String.t() | nil, integer()) :: String.t()
  def block_identifier(type, id) do
    dgettext("sheets", "%{type} #%{id}", type: block_type_label(type), id: id)
  end

  @doc "Names a table row by id when it carries no name of its own."
  @spec row_identifier(integer()) :: String.t()
  def row_identifier(id), do: dgettext("sheets", "Row #%{id}", id: id)

  @doc "Names a table column by id when it carries no name of its own."
  @spec column_identifier(integer()) :: String.t()
  def column_identifier(id), do: dgettext("sheets", "Column #%{id}", id: id)

  defp health_items(findings, severity, context) do
    findings
    |> Enum.filter(&(&1.severity == severity))
    |> Enum.group_by(&{&1.block_id, &1.row_id, &1.column_id})
    |> Enum.map(fn {_location, grouped_findings} -> health_item(grouped_findings, context) end)
    |> Enum.sort_by(&{is_nil(&1.blockId), &1.label, &1.rowId || 0, &1.columnId || 0})
  end

  defp health_item([finding | _] = findings, context) do
    %{
      # `entityType`/`entityId` is the location every domain's findings carry;
      # `blockId`/`rowId`/`columnId` is the finer one only sheets need, since a
      # finding here can land on a single cell.
      entityType: finding.entity_type,
      entityId: finding.entity_id,
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

  defp health_label(%{block_id: block_id, block_type: block_type, row_id: row_id, column_id: column_id}, context) do
    block_label = Map.get(context.block_labels, block_id) || block_identifier(block_type, block_id)

    Enum.join([block_label | axis_labels(row_id, column_id, context)], " · ")
  end

  defp axis_labels(row_id, column_id, context) do
    row = row_id && (Map.get(context.row_labels, row_id) || row_identifier(row_id))
    column = column_id && (Map.get(context.column_labels, column_id) || column_identifier(column_id))

    Enum.reject([row, column], &is_nil/1)
  end

  defp health_label_context(sheet, blocks, table_data) do
    block_labels =
      Map.new(blocks, fn block -> {block.id, present_label(get_in(block.config || %{}, ["label"]))} end)

    {row_labels, column_labels} =
      Enum.reduce(table_data, {%{}, %{}}, fn {_block_id, table}, {rows, columns} ->
        row_labels = Map.new(table.rows, &{&1.id, present_label(&1.name)})
        column_labels = Map.new(table.columns, &{&1.id, present_label(&1.name)})
        {Map.merge(rows, row_labels), Map.merge(columns, column_labels)}
      end)

    %{
      sheet_name: present_label(sheet.name) || dgettext("sheets", "Sheet"),
      block_labels: block_labels,
      row_labels: row_labels,
      column_labels: column_labels
    }
  end

  # `nil` rather than a fallback string, so the identifier is built — and
  # translated — at the point of use instead of being baked into the map.
  defp present_label(value), do: StringUtils.present_label(value, nil)
end

defmodule Storyarn.Scenes.VariableCatalog do
  @moduledoc """
  Scene-owned read model for every variable addressable by conditions and
  instructions.

  It reads the shared persistence tables through records owned by Scenes and
  emits the runtime descriptor shape consumed by the editor and evaluator.
  """

  import Ecto.Query

  alias Storyarn.Repo
  alias Storyarn.Scenes.Expressions.Projections.BlockRecord
  alias Storyarn.Scenes.Expressions.Projections.SheetRecord
  alias Storyarn.Scenes.Expressions.Projections.TableColumnRecord
  alias Storyarn.Scenes.Expressions.Projections.TableRowRecord
  alias Storyarn.Scenes.Scene, as: SceneRecord
  alias Storyarn.Scenes.ScenePin, as: ScenePinRecord
  alias Storyarn.Scenes.SceneZone, as: SceneZoneRecord
  alias Storyarn.Scenes.VariableConstraints
  alias Storyarn.Scenes.VariableNamespaceResolver

  require VariableNamespaceResolver

  @regular_types ~w(text rich_text number select multi_select boolean date)
  @table_types ~w(number text boolean select multi_select date reference formula)

  @spec list_referenceable(integer()) :: [map()]
  def list_referenceable(project_id) when is_integer(project_id) do
    list_block_variables(project_id) ++
      list_table_variables(project_id) ++
      list_pin_variables(project_id) ++
      list_zone_variables(project_id)
  end

  defp list_block_variables(project_id) do
    from(block in BlockRecord,
      join: sheet in SheetRecord,
      on: block.sheet_id == sheet.id,
      where:
        sheet.project_id == ^project_id and is_nil(sheet.deleted_at) and
          is_nil(block.deleted_at) and block.type in ^@regular_types and
          block.is_constant == false and not is_nil(block.variable_name) and
          block.variable_name != "" and
          VariableNamespaceResolver.authoritative_namespace_owner?(sheet),
      order_by: [asc: sheet.name, asc: block.position],
      select: %{
        sheet_id: sheet.id,
        sheet_name: sheet.name,
        sheet_shortcut: coalesce(sheet.shortcut, fragment("CAST(? AS TEXT)", sheet.id)),
        block_id: block.id,
        variable_name: block.variable_name,
        block_type: block.type,
        config: block.config,
        value: block.value,
        table_name: nil,
        row_name: nil,
        column_name: nil
      }
    )
    |> Repo.all()
    |> Enum.map(&decorate_variable/1)
  end

  defp list_table_variables(project_id) do
    variables =
      Repo.all(
        from(column in TableColumnRecord,
          join: block in BlockRecord,
          on: column.block_id == block.id,
          join: sheet in SheetRecord,
          on: block.sheet_id == sheet.id,
          join: row in TableRowRecord,
          on: row.block_id == block.id,
          where:
            sheet.project_id == ^project_id and is_nil(sheet.deleted_at) and
              is_nil(block.deleted_at) and block.type == "table" and
              column.type in ^@table_types and
              (column.is_constant == false or column.type == "formula") and
              VariableNamespaceResolver.authoritative_namespace_owner?(sheet),
          order_by: [
            asc: sheet.name,
            asc: block.position,
            asc: row.position,
            asc: column.position
          ],
          select: %{
            sheet_id: sheet.id,
            sheet_name: sheet.name,
            sheet_shortcut: coalesce(sheet.shortcut, fragment("CAST(? AS TEXT)", sheet.id)),
            block_id: block.id,
            variable_name: fragment("? || '.' || ? || '.' || ?", block.variable_name, row.slug, column.slug),
            block_type: column.type,
            config: column.config,
            cell_value: fragment("?->?", row.cells, column.slug),
            table_name: block.variable_name,
            row_name: row.slug,
            column_name: column.slug
          }
        )
      )

    sheet_options =
      if Enum.any?(variables, &(&1.block_type == "reference")),
        do: list_sheet_options(project_id),
        else: []

    variables
    |> Enum.map(&remap_reference(&1, sheet_options))
    |> Enum.map(&decorate_variable/1)
  end

  defp list_pin_variables(project_id) do
    from(pin in ScenePinRecord,
      join: scene in SceneRecord,
      on: pin.scene_id == scene.id,
      where:
        scene.project_id == ^project_id and is_nil(scene.deleted_at) and
          not is_nil(pin.shortcut),
      select: %{
        id: pin.id,
        shortcut: pin.shortcut,
        label: pin.label,
        hidden: pin.hidden,
        is_playable: pin.is_playable,
        is_leader: pin.is_leader
      }
    )
    |> Repo.all()
    |> Enum.flat_map(&expand_pin/1)
  end

  defp list_zone_variables(project_id) do
    from(zone in SceneZoneRecord,
      join: scene in SceneRecord,
      on: zone.scene_id == scene.id,
      where:
        scene.project_id == ^project_id and is_nil(scene.deleted_at) and
          not is_nil(zone.shortcut),
      select: %{
        id: zone.id,
        shortcut: zone.shortcut,
        name: zone.name,
        hidden: zone.hidden
      }
    )
    |> Repo.all()
    |> Enum.map(&expand_zone/1)
  end

  defp expand_pin(pin) do
    base = %{
      source_type: "pin",
      source_id: pin.id,
      sheet_shortcut: pin.shortcut,
      sheet_name: pin.label || pin.shortcut,
      block_id: nil,
      options: nil,
      constraints: nil
    }

    [
      boolean_descriptor(base, "hidden", pin.hidden),
      boolean_descriptor(base, "is_playable", pin.is_playable),
      boolean_descriptor(base, "is_leader", pin.is_leader)
    ]
  end

  defp expand_zone(zone) do
    base = %{
      source_type: "zone",
      source_id: zone.id,
      sheet_shortcut: zone.shortcut,
      sheet_name: zone.name || zone.shortcut,
      block_id: nil,
      options: nil,
      constraints: nil
    }

    boolean_descriptor(base, "hidden", zone.hidden)
  end

  defp boolean_descriptor(base, variable_name, value) do
    Map.merge(base, %{
      variable_name: variable_name,
      block_type: "boolean",
      value: %{"content" => value}
    })
  end

  defp remap_reference(%{block_type: "reference", config: config} = variable, options) do
    config = Map.put(config || %{}, "options", options)
    type = if config["multiple"], do: "multi_select", else: "select"
    %{variable | block_type: type, config: config}
  end

  defp remap_reference(variable, _options), do: variable

  defp decorate_variable(variable) do
    options =
      if variable.block_type in ["select", "multi_select"],
        do: variable.config["options"] || []

    variable
    |> Map.put(:constraints, VariableConstraints.extract(variable.block_type, variable.config))
    |> Map.put(:options, options)
    |> Map.delete(:config)
  end

  defp list_sheet_options(project_id) do
    from(sheet in SheetRecord,
      where:
        sheet.project_id == ^project_id and is_nil(sheet.deleted_at) and
          not is_nil(sheet.shortcut) and sheet.shortcut != "",
      order_by: [asc: sheet.name],
      select: %{name: sheet.name, shortcut: sheet.shortcut}
    )
    |> Repo.all()
    |> Enum.map(fn sheet -> %{"key" => sheet.shortcut, "value" => sheet.name} end)
  end
end

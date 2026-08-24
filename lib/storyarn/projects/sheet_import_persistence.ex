defmodule Storyarn.Projects.SheetImportPersistence do
  @moduledoc """
  Project-owned Sheet writer used only by project import/reconstitution.

  Every function duplicates the Sheet tool's import path exactly — the same
  raw inserts, the same table-scope locks and cell validation — over
  Project-owned persistence records.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Platform.Shared.HtmlUtils
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.FlowFormulaEngine, as: FormulaEngine
  alias Storyarn.Projects.Persistence.BlockRecord
  alias Storyarn.Projects.Persistence.SheetAvatarRecord
  alias Storyarn.Projects.Persistence.SheetRecord
  alias Storyarn.Projects.Persistence.TableColumnRecord
  alias Storyarn.Projects.Persistence.TableRowRecord
  alias Storyarn.References.ProjectReferenceIntegrity
  alias Storyarn.Repo

  def list_shortcuts(project_id) do
    from(sheet in SheetRecord,
      where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at),
      select: sheet.shortcut
    )
    |> Repo.all()
    |> MapSet.new()
  end

  def detect_shortcut_conflicts(project_id, shortcuts) when is_list(shortcuts) do
    if shortcuts == [] do
      []
    else
      Repo.all(
        from(sheet in SheetRecord,
          where: sheet.project_id == ^project_id and sheet.shortcut in ^shortcuts and is_nil(sheet.deleted_at),
          select: sheet.shortcut
        )
      )
    end
  end

  def soft_delete_by_shortcut(project_id, shortcut) do
    now = TimeHelpers.now()

    Repo.update_all(
      from(sheet in SheetRecord,
        where: sheet.project_id == ^project_id and sheet.shortcut == ^shortcut and is_nil(sheet.deleted_at)
      ),
      set: [deleted_at: now]
    )
  end

  @doc """
  Creates a sheet for import. Raw insert — no auto-shortcut, no auto-position,
  no property inheritance. Returns `{:ok, sheet}` or `{:error, changeset}`.
  """
  def import_sheet(project_id, attrs) do
    %SheetRecord{project_id: project_id}
    |> SheetRecord.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a sheet's parent_id after import (two-pass parent linking)."
  def link_import_parent(%SheetRecord{} = sheet, parent_id) do
    sheet
    |> Ecto.Changeset.change(%{parent_id: parent_id})
    |> Repo.update!()
  end

  @doc "Creates a block for import. Raw insert with the persisted word count."
  def import_block(sheet_id, attrs) do
    type = attrs[:type] || attrs["type"]
    value = attrs[:value] || attrs["value"]

    %BlockRecord{sheet_id: sheet_id}
    |> BlockRecord.create_changeset(attrs)
    |> Ecto.Changeset.put_change(:word_count, word_count_for_block(type, value))
    |> Repo.insert()
  end

  @doc "Creates a table column for import under the tool's table-scope lock."
  def import_column(block_id, attrs) do
    Repo.transaction(fn ->
      _scope = lock_table_scope!(block_id)

      case %TableColumnRecord{block_id: block_id}
           |> TableColumnRecord.create_changeset(attrs)
           |> Repo.insert() do
        {:ok, column} -> column
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc "Creates a table row for import, validating cells against the locked scope."
  def import_row(block_id, attrs) do
    Repo.transaction(fn ->
      scope = lock_table_scope!(block_id)
      cells = attrs[:cells] || attrs["cells"] || %{}
      validate_cell_keys!(scope, cells, enforce_required: false)

      case %TableRowRecord{block_id: block_id}
           |> TableRowRecord.create_changeset(attrs)
           |> Repo.insert() do
        {:ok, row} -> row
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc "Adds an avatar to a sheet under the tool's project and asset locks."
  def add_avatar(%SheetRecord{id: sheet_id}, asset_id, attrs \\ %{}) do
    Repo.transaction(fn ->
      project_id = fetch_sheet_project_id!(sheet_id)
      lock_active_project!(project_id)
      sheet = lock_active_sheet!(sheet_id, project_id)

      normalized_asset_id = lock_avatar_asset!(sheet.project_id, asset_id)

      position = next_avatar_position(sheet_id)
      is_first = position == 0

      case %SheetAvatarRecord{sheet_id: sheet_id}
           |> SheetAvatarRecord.create_changeset(
             Map.merge(attrs, %{
               asset_id: normalized_asset_id,
               position: position,
               is_default: is_first
             })
           )
           |> Repo.insert() do
        {:ok, avatar} -> avatar
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # ===========================================================================
  # Word count (mirror of the Sheet content contract)
  # ===========================================================================

  defp word_count_for_block(type, value) when type in ["text", "rich_text"], do: word_count_for_value(value)
  defp word_count_for_block(_type, _value), do: 0

  defp word_count_for_value(value) when is_map(value) do
    value
    |> flexible_field("content", :content)
    |> count_text()
  end

  defp word_count_for_value(_value), do: 0

  defp count_text(text) when is_binary(text), do: HtmlUtils.word_count(text)
  defp count_text(_text), do: 0

  defp flexible_field(map, string_key, atom_key) do
    case Map.fetch(map, string_key) do
      {:ok, value} -> value
      :error -> Map.get(map, atom_key)
    end
  end

  # ===========================================================================
  # Avatar locks (mirror of the Sheet avatar writer)
  # ===========================================================================

  defp fetch_sheet_project_id!(sheet_id) do
    Repo.one(
      from(sheet in SheetRecord,
        where: sheet.id == ^sheet_id,
        select: sheet.project_id
      )
    ) || Repo.rollback(:sheet_not_found)
  end

  defp lock_active_sheet!(sheet_id, project_id) do
    case Repo.one(
           from(sheet in SheetRecord,
             where:
               sheet.id == ^sheet_id and sheet.project_id == ^project_id and
                 is_nil(sheet.deleted_at),
             lock: "FOR UPDATE"
           )
         ) do
      %SheetRecord{} = sheet -> sheet
      nil -> Repo.rollback(:sheet_not_active)
    end
  end

  defp lock_avatar_asset!(project_id, asset_id) do
    with {:ok, [normalized_asset_id]} <-
           ProjectReferenceIntegrity.lock_active_references(project_id, [
             {:asset, :avatar_asset_id, asset_id}
           ]),
         :ok <- ensure_avatar_asset_present(normalized_asset_id, asset_id),
         :ok <-
           ProjectReferenceIntegrity.ensure_locked_asset_content_type(
             project_id,
             normalized_asset_id,
             :avatar_asset_id,
             "image/%"
           ) do
      normalized_asset_id
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp ensure_avatar_asset_present(nil, original_asset_id),
    do: {:error, {:invalid_project_reference, :avatar_asset_id, original_asset_id}}

  defp ensure_avatar_asset_present(_asset_id, _original_asset_id), do: :ok

  defp next_avatar_position(sheet_id) do
    from(avatar in SheetAvatarRecord,
      where: avatar.sheet_id == ^sheet_id,
      select: coalesce(max(avatar.position), -1)
    )
    |> Repo.one()
    |> Kernel.+(1)
  end

  # ===========================================================================
  # Table scope lock (mirror of the Sheet table writer)
  # ===========================================================================

  defp lock_table_scope!(block_id) do
    {project_id, sheet_id} = fetch_table_owner!(block_id)

    lock_active_project!(project_id)
    instance_metadata = active_table_instance_metadata(block_id, project_id)
    block_ids = [block_id | Enum.map(instance_metadata, &elem(&1, 0))] |> Enum.uniq() |> Enum.sort()
    instance_sheet_ids = instance_metadata |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

    lock_table_source_and_target_sheets!(project_id, sheet_id, instance_sheet_ids)
    blocks = lock_active_table_blocks!(block_id, block_ids)
    columns = lock_table_columns!(block_ids)
    rows = lock_table_rows!(block_ids)

    block =
      Enum.find(blocks, &(&1.id == block_id and &1.sheet_id == sheet_id)) ||
        Repo.rollback(:inactive_table)

    %{
      block: block,
      instance_ids: Enum.reject(block_ids, &(&1 == block_id)),
      columns: columns,
      rows: rows
    }
  end

  defp fetch_table_owner!(block_id) do
    Repo.one(
      from(block in BlockRecord,
        join: sheet in SheetRecord,
        on: sheet.id == block.sheet_id,
        where: block.id == ^block_id,
        select: {sheet.project_id, sheet.id}
      )
    ) || Repo.rollback(:inactive_table)
  end

  defp lock_active_project!(project_id) do
    case ProjectReferenceIntegrity.lock_active_project(project_id, :update) do
      {:ok, _project} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp active_table_instance_metadata(block_id, project_id) do
    Repo.all(
      from(instance in BlockRecord,
        join: owner_sheet in SheetRecord,
        on: owner_sheet.id == instance.sheet_id,
        join: source in BlockRecord,
        on: source.id == ^block_id,
        where:
          is_nil(source.deleted_at) and
            instance.inherited_from_block_id == source.id and
            instance.detached == false and
            instance.type == "table" and
            owner_sheet.project_id == ^project_id and
            source.scope == "children" and is_nil(instance.deleted_at),
        order_by: [asc: instance.id],
        select: {instance.id, instance.sheet_id}
      )
    )
  end

  defp lock_table_source_and_target_sheets!(project_id, source_sheet_id, target_sheet_ids) do
    requested_ids =
      [source_sheet_id | target_sheet_ids]
      |> Enum.uniq()
      |> Enum.sort()

    locked_sheets =
      Repo.all(
        from(sheet in SheetRecord,
          where:
            sheet.id in ^requested_ids and
              sheet.project_id == ^project_id,
          order_by: [asc: sheet.id],
          lock: "FOR UPDATE",
          select: {sheet.id, sheet.deleted_at}
        )
      )

    locked_ids = Enum.map(locked_sheets, &elem(&1, 0))

    source_active? =
      Enum.any?(locked_sheets, fn {id, deleted_at} ->
        id == source_sheet_id and is_nil(deleted_at)
      end)

    if locked_ids != requested_ids or !source_active?, do: Repo.rollback(:inactive_table)
  end

  defp lock_active_table_blocks!(source_block_id, block_ids) do
    blocks =
      Repo.all(
        from(block in BlockRecord,
          where:
            block.id in ^block_ids and
              block.type == "table",
          order_by: [asc: block.id],
          lock: "FOR UPDATE"
        )
      )

    source = Enum.find(blocks, &(&1.id == source_block_id))

    valid? =
      ((Enum.map(blocks, & &1.id) == block_ids and
          source) && is_nil(source.deleted_at)) and
        Enum.all?(blocks, fn
          %{id: ^source_block_id} ->
            true

          instance ->
            instance.inherited_from_block_id == source_block_id and
              instance.detached == false and is_nil(instance.deleted_at)
        end)

    if valid? do
      blocks
    else
      Repo.rollback(:inactive_table)
    end
  end

  defp lock_table_columns!(block_ids) do
    Repo.all(
      from(column in TableColumnRecord,
        where: column.block_id in ^block_ids,
        order_by: [asc: column.block_id, asc: column.id],
        lock: "FOR UPDATE"
      )
    )
  end

  defp lock_table_rows!(block_ids) do
    Repo.all(
      from(row in TableRowRecord,
        where: row.block_id in ^block_ids,
        order_by: [asc: row.block_id, asc: row.id],
        lock: "FOR UPDATE"
      )
    )
  end

  defp parent_columns(scope), do: Enum.filter(scope.columns, &(&1.block_id == scope.block.id))

  # ===========================================================================
  # Cell validation (mirror of the Sheet table writer)
  # ===========================================================================

  defp validate_cell_keys!(scope, cells_map, opts) when is_map(cells_map) do
    columns_by_slug = Map.new(parent_columns(scope), &{&1.slug, &1})
    enforce_required? = Keyword.fetch!(opts, :enforce_required)

    Enum.each(cells_map, fn {slug, value} ->
      column = Map.get(columns_by_slug, slug)
      validate_table_cell!(column, slug, value, columns_by_slug, enforce_required?)
    end)
  end

  defp validate_cell_keys!(_scope, _cells_map, _opts), do: Repo.rollback(:invalid_table_cells)

  defp validate_table_cell!(nil, slug, _value, _columns_by_slug, _enforce_required?) do
    Repo.rollback({:unknown_table_column, slug})
  end

  defp validate_table_cell!(
         %TableColumnRecord{type: "formula"} = column,
         _slug,
         value,
         columns_by_slug,
         _enforce_required?
       ) do
    validate_formula_cell!(value, column, columns_by_slug)
  end

  defp validate_table_cell!(%TableColumnRecord{required: true}, slug, value, _columns_by_slug, true) do
    if empty_cell_value?(value),
      do: Repo.rollback({:required_table_column, slug})
  end

  defp validate_table_cell!(%TableColumnRecord{}, _slug, _value, _columns_by_slug, _enforce_required?), do: :ok

  defp validate_formula_cell!(nil, _column, _columns_by_slug), do: :ok

  defp validate_formula_cell!(%{"expression" => expression, "bindings" => bindings} = value, column, columns_by_slug)
       when is_binary(expression) and is_map(bindings) do
    if value |> Map.keys() |> Enum.sort() != ["bindings", "expression"] do
      Repo.rollback({:invalid_formula_cell, column.slug})
    end

    allowed_symbols =
      case FormulaEngine.parse(expression) do
        {:ok, ast} -> ast |> FormulaEngine.extract_symbols() |> MapSet.new()
        {:error, _reason} -> MapSet.new()
      end

    Enum.each(bindings, fn {symbol, binding} ->
      if !is_binary(symbol) or !MapSet.member?(allowed_symbols, symbol) do
        Repo.rollback({:invalid_formula_cell, column.slug})
      end

      validate_formula_binding!(binding, column, columns_by_slug)
    end)
  end

  defp validate_formula_cell!(_value, column, _columns_by_slug) do
    Repo.rollback({:invalid_formula_cell, column.slug})
  end

  defp validate_formula_binding!(
         %{"type" => "same_row", "column_slug" => referenced_slug} = binding,
         column,
         columns_by_slug
       )
       when is_binary(referenced_slug) and referenced_slug != "" do
    referenced_column = Map.get(columns_by_slug, referenced_slug)

    if binding |> Map.keys() |> Enum.sort() != ["column_slug", "type"] or
         referenced_slug == column.slug or
         is_nil(referenced_column) or
         referenced_column.type not in ["number", "formula"] do
      Repo.rollback({:invalid_formula_cell, column.slug})
    end
  end

  defp validate_formula_binding!(%{"type" => "variable", "ref" => reference} = binding, column, _columns_by_slug)
       when is_binary(reference) and reference != "" do
    if binding |> Map.keys() |> Enum.sort() != ["ref", "type"] do
      Repo.rollback({:invalid_formula_cell, column.slug})
    end
  end

  defp validate_formula_binding!(_binding, column, _columns_by_slug) do
    Repo.rollback({:invalid_formula_cell, column.slug})
  end

  defp empty_cell_value?(nil), do: true
  defp empty_cell_value?(""), do: true
  defp empty_cell_value?([]), do: true
  defp empty_cell_value?(_value), do: false
end

defmodule Storyarn.Projects.Imports.ConflictResolution do
  @moduledoc """
  Pure shortcut-conflict decisions for additive project imports.

  A decision always carries the identity that downstream reference remapping
  needs. `:skip` reuses the one active target selected by the conflicting
  shortcut; `:rename` creates a distinct target; and conflicting `:overwrite`
  fails closed until Projects can replace or relink every supported inbound
  reference atomically.
  """

  alias Storyarn.Projects.Imports.ShortcutAllocator
  alias Storyarn.Projects.References

  @regular_variable_types References.regular_variable_types()
  @table_variable_types References.table_variable_types()
  @constant_table_variable_types References.constant_table_variable_types()

  @type shortcut :: String.t() | nil
  @type decision :: {:create, shortcut()} | {:reuse, pos_integer()}
  @type target_id_by_shortcut :: %{optional(String.t()) => pos_integer()}

  @doc """
  Rejects an overwrite that would retire any existing or earlier imported
  logical identity.

  This runs before materialization. The error deliberately carries no source
  shortcut, entity name, or database ID so it is safe to persist and report.
  """
  @spec preflight(atom(), %{optional(atom()) => [map()]}, %{optional(atom()) => target_id_by_shortcut()}) ::
          :ok | {:error, :overwrite_conflict_requires_rename}
  def preflight(:overwrite, imported_by_type, active_targets) do
    conflict? =
      Enum.any?(imported_by_type, fn {entity_type, entities} ->
        overwrite_conflict?(entities, Map.get(active_targets, entity_type, %{}))
      end)

    if conflict?, do: {:error, :overwrite_conflict_requires_rename}, else: :ok
  end

  def preflight(:skip, imported_by_type, _active_targets) do
    if Enum.any?(imported_by_type, fn {_entity_type, entities} -> duplicate_shortcuts?(entities) end),
      do: {:error, :skip_conflict_ambiguous},
      else: :ok
  end

  def preflight(_strategy, _imported_by_type, _active_targets), do: :ok

  @doc """
  Verifies every declared variable from a skipped Sheet against the active target.

  A shortcut collision proves only root identity. Imported consumers also need
  every declared regular variable to resolve to a block with the same name and
  persisted type. Referenceable table cells are checked structurally: one table
  identity, each row, and each typed column. That proves every row-column cell
  without materializing their Cartesian product. Checking all declarations
  includes text interpolations, which are not represented by the structured
  expression reference extractor. Anything less fails before writes instead of
  completing with an unresolved or type-shifted reference.
  """
  @spec preflight_skip_variables(map(), target_id_by_shortcut(), map()) ::
          :ok | {:error, :skip_variable_contract_mismatch}
  def preflight_skip_variables(data, active_sheets, active_variable_contracts) do
    skipped_shortcuts =
      data
      |> Map.get("sheets")
      |> List.wrap()
      |> Enum.map(& &1["shortcut"])
      |> Enum.filter(&Map.has_key?(active_sheets, &1))
      |> MapSet.new()

    imported_contracts =
      data
      |> imported_variable_contracts()
      |> Enum.filter(fn {key, _type} -> MapSet.member?(skipped_shortcuts, contract_sheet_shortcut(key)) end)

    compatible? =
      Enum.all?(imported_contracts, fn {key, imported_type} ->
        Map.get(active_variable_contracts, key) == imported_type
      end)

    if compatible?, do: :ok, else: {:error, :skip_variable_contract_mismatch}
  end

  @doc "Returns the identity decision for one imported top-level entity."
  @spec resolve(shortcut(), atom(), MapSet.t(), target_id_by_shortcut()) ::
          {:ok, decision()}
          | {:error, :overwrite_conflict_requires_rename | :skip_conflict_target_missing}
  def resolve(nil, _strategy, _used_shortcuts, _target_ids), do: {:ok, {:create, nil}}

  def resolve(shortcut, strategy, used_shortcuts, target_ids) when is_binary(shortcut) do
    if MapSet.member?(used_shortcuts, shortcut) do
      resolve_conflict(shortcut, strategy, used_shortcuts, target_ids)
    else
      {:ok, {:create, shortcut}}
    end
  end

  defp resolve_conflict(shortcut, :skip, _used_shortcuts, target_ids) do
    case Map.fetch(target_ids, shortcut) do
      {:ok, target_id} when is_integer(target_id) and target_id > 0 ->
        {:ok, {:reuse, target_id}}

      _missing_or_invalid ->
        {:error, :skip_conflict_target_missing}
    end
  end

  defp resolve_conflict(_shortcut, :overwrite, _used_shortcuts, _target_ids),
    do: {:error, :overwrite_conflict_requires_rename}

  defp resolve_conflict(shortcut, :rename, used_shortcuts, _target_ids) do
    {:ok, {:create, ShortcutAllocator.unique(shortcut, used_shortcuts, shortcut)}}
  end

  defp resolve_conflict(shortcut, _strategy, _used_shortcuts, _target_ids), do: {:ok, {:create, shortcut}}

  defp overwrite_conflict?(entities, active_targets) do
    shortcuts =
      entities
      |> Enum.map(& &1["shortcut"])
      |> Enum.filter(&is_binary/1)

    duplicate_shortcuts?(shortcuts) or
      Enum.any?(shortcuts, &Map.has_key?(active_targets, &1))
  end

  defp duplicate_shortcuts?(entities) when is_list(entities) do
    shortcuts =
      case entities do
        [shortcut | _rest] when is_binary(shortcut) -> entities
        _entities -> entities |> Enum.map(& &1["shortcut"]) |> Enum.filter(&is_binary/1)
      end

    length(shortcuts) != length(Enum.uniq(shortcuts))
  end

  defp imported_variable_contracts(data) do
    data
    |> Map.get("sheets")
    |> List.wrap()
    |> Enum.flat_map(&sheet_variable_contracts/1)
  end

  defp sheet_variable_contracts(sheet) do
    shortcut = sheet["shortcut"]

    sheet
    |> Map.get("blocks")
    |> List.wrap()
    |> Enum.flat_map(fn block ->
      variable_contract(shortcut, block) ++ table_variable_contracts(shortcut, block)
    end)
  end

  defp variable_contract(shortcut, block) do
    case {shortcut, block["variable_name"], block["type"], block["is_constant"]} do
      {sheet_shortcut, variable_name, type, is_constant}
      when is_binary(sheet_shortcut) and is_binary(variable_name) and variable_name != "" and
             type in @regular_variable_types and is_constant != true ->
        [{{sheet_shortcut, variable_name}, type}]

      _not_a_regular_variable ->
        []
    end
  end

  defp table_variable_contracts(sheet_shortcut, %{
         "type" => "table",
         "variable_name" => table_name,
         "table_data" => %{"columns" => columns, "rows" => rows}
       }) do
    with true <- valid_table_contract_identity?(sheet_shortcut, table_name),
         true <- is_list(columns),
         true <- is_list(rows) do
      row_contracts =
        Enum.flat_map(rows, &table_row_contract(sheet_shortcut, table_name, &1))

      column_contracts =
        Enum.flat_map(columns, &table_column_contract(sheet_shortcut, table_name, &1))

      complete_table_contracts(sheet_shortcut, table_name, row_contracts, column_contracts)
    else
      false -> []
    end
  end

  defp table_variable_contracts(_sheet_shortcut, _block), do: []

  defp valid_table_contract_identity?(sheet_shortcut, table_name) do
    is_binary(sheet_shortcut) and is_binary(table_name) and table_name != ""
  end

  defp table_row_contract(sheet_shortcut, table_name, %{"slug" => row_slug})
       when is_binary(row_slug) and row_slug != "" do
    [{{:table_row, sheet_shortcut, table_name, row_slug}, :present}]
  end

  defp table_row_contract(_sheet_shortcut, _table_name, _row), do: []

  defp table_column_contract(sheet_shortcut, table_name, %{"slug" => column_slug, "type" => type} = column)
       when is_binary(column_slug) and column_slug != "" do
    if table_variable_column?(column),
      do: [{{:table_column, sheet_shortcut, table_name, column_slug}, type}],
      else: []
  end

  defp table_column_contract(_sheet_shortcut, _table_name, _column), do: []

  defp complete_table_contracts(_sheet_shortcut, _table_name, [], _column_contracts), do: []
  defp complete_table_contracts(_sheet_shortcut, _table_name, _row_contracts, []), do: []

  defp complete_table_contracts(sheet_shortcut, table_name, row_contracts, column_contracts) do
    [{{:table, sheet_shortcut, table_name}, :present} | row_contracts] ++ column_contracts
  end

  defp table_variable_column?(column) when is_map(column) do
    type = column["type"]

    type in @table_variable_types and
      (column["is_constant"] != true or type in @constant_table_variable_types)
  end

  defp table_variable_column?(_column), do: false

  defp contract_sheet_shortcut({sheet_shortcut, _variable_name}), do: sheet_shortcut

  defp contract_sheet_shortcut({:table, sheet_shortcut, _table_name}), do: sheet_shortcut
  defp contract_sheet_shortcut({:table_row, sheet_shortcut, _table_name, _row_slug}), do: sheet_shortcut
  defp contract_sheet_shortcut({:table_column, sheet_shortcut, _table_name, _column_slug}), do: sheet_shortcut
end

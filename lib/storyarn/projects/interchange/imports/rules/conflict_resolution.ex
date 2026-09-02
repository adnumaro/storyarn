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
  every declared variable to resolve to a block with the same name and persisted
  type. Checking all declarations includes text interpolations, which are not
  represented by the structured expression reference extractor. Anything less
  fails before writes instead of completing with an unresolved or type-shifted
  reference.
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
      |> Enum.filter(fn {{sheet_shortcut, _variable_name}, _type} ->
        MapSet.member?(skipped_shortcuts, sheet_shortcut)
      end)

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
    |> Enum.flat_map(&variable_contract(shortcut, &1))
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
end

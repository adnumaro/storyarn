defmodule Storyarn.Versioning.DiffHelpers do
  @moduledoc """
  Shared helpers for snapshot diffing across all entity types.

  Provides generic collection matching and field comparison utilities
  used by FlowBuilder, SheetBuilder, and SceneBuilder.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Repo

  @type change :: %{category: atom(), action: :added | :removed | :modified, detail: String.t()}

  @doc """
  Appends a `:modified` change if a top-level field differs between two snapshots.
  """
  @spec check_field_change([change()], map(), map(), String.t(), atom(), String.t()) ::
          [change()]
  def check_field_change(changes, old_snapshot, new_snapshot, field, category, detail) do
    if old_snapshot[field] != new_snapshot[field] do
      [%{category: category, action: :modified, detail: detail} | changes]
    else
      changes
    end
  end

  @doc """
  Matches two collections using a list of key functions in priority order.

  Each key function receives an item and returns a match key (or nil to skip).
  Items matched by earlier key functions are consumed before trying later ones.

  Returns `{matched_pairs, added, removed}` where:
  - `matched_pairs` — `[{old_item, new_item}]` sharing a key
  - `added` — items only in `new_list`
  - `removed` — items only in `old_list`
  """
  @spec match_by_keys([map()], [map()], [(map() -> term() | nil)]) ::
          {[{map(), map()}], [map()], [map()]}
  def match_by_keys(old_list, new_list, key_fns) do
    {matched, remaining_old, remaining_new} =
      Enum.reduce(key_fns, {[], old_list, new_list}, fn key_fn, {matched, old, new} ->
        match_round(old, new, key_fn, matched)
      end)

    {Enum.reverse(matched), remaining_new, remaining_old}
  end

  defp match_round(old_list, new_list, key_fn, matched) do
    old_keyed =
      old_list
      |> Enum.map(fn item -> {key_fn.(item), item} end)
      |> Enum.reject(fn {key, _} -> is_nil(key) end)
      |> Map.new()

    new_keyed =
      new_list
      |> Enum.map(fn item -> {key_fn.(item), item} end)
      |> Enum.reject(fn {key, _} -> is_nil(key) end)

    {new_matched, consumed_keys} =
      Enum.reduce(new_keyed, {matched, MapSet.new()}, fn {key, new_item}, {acc, consumed} ->
        case Map.get(old_keyed, key) do
          nil -> {acc, consumed}
          old_item -> {[{old_item, new_item} | acc], MapSet.put(consumed, key)}
        end
      end)

    remaining_old =
      Enum.reject(old_list, fn item ->
        key = key_fn.(item)
        key != nil and MapSet.member?(consumed_keys, key)
      end)

    remaining_new =
      Enum.reject(new_list, fn item ->
        key = key_fn.(item)
        key != nil and MapSet.member?(consumed_keys, key)
      end)

    {new_matched, remaining_old, remaining_new}
  end

  @doc """
  Splits matched pairs into modified (where compare_fn returns true) and unchanged.

  Returns `{modified_pairs, unchanged_count}`.
  """
  @spec find_modified([{map(), map()}], (map(), map() -> boolean())) ::
          {[{map(), map()}], non_neg_integer()}
  def find_modified(matched_pairs, differ_fn) do
    {modified, unchanged_count} =
      Enum.reduce(matched_pairs, {[], 0}, fn {old, new}, {mods, unch} ->
        if differ_fn.(old, new) do
          {[{old, new} | mods], unch}
        else
          {mods, unch + 1}
        end
      end)

    {Enum.reverse(modified), unchanged_count}
  end

  @doc """
  Appends a single `:modified` change if ANY of the given fields differ.

  Unlike calling `check_field_change/6` per field (which emits one change per
  differing field), this emits at most one change for the whole group.
  """
  @spec check_field_group_change([change()], map(), map(), [String.t()], atom(), String.t()) ::
          [change()]
  def check_field_group_change(changes, old_snapshot, new_snapshot, fields, category, detail) do
    if Enum.any?(fields, fn f -> old_snapshot[f] != new_snapshot[f] end) do
      [%{category: category, action: :modified, detail: detail} | changes]
    else
      changes
    end
  end

  @doc """
  Compares two maps, considering only the given fields.
  Returns true if any specified field differs.
  """
  @spec fields_differ?(map(), map(), [String.t()]) :: boolean()
  def fields_differ?(old, new, fields) do
    Enum.any?(fields, fn field -> old[field] != new[field] end)
  end

  @doc """
  Returns the FK value only if the referenced record still exists, nil otherwise.
  Used by builders during snapshot restoration to gracefully handle deleted references.
  """
  @spec resolve_fk(integer() | nil, module()) :: integer() | nil
  def resolve_fk(nil, _schema), do: nil

  def resolve_fk(id, schema) do
    if Repo.exists?(from(e in schema, where: e.id == ^id)), do: id, else: nil
  end
end

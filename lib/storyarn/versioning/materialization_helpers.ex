defmodule Storyarn.Versioning.MaterializationHelpers do
  @moduledoc false

  alias Storyarn.Shared.TimeHelpers

  @spec now() :: DateTime.t()
  def now, do: TimeHelpers.now()

  @spec timestamps(DateTime.t()) :: map()
  def timestamps(now), do: %{inserted_at: now, updated_at: now}

  @spec root_shortcut(map(), keyword()) :: String.t() | nil
  def root_shortcut(snapshot, opts) do
    cond do
      Keyword.get(opts, :preserve_shortcut, false) -> snapshot["shortcut"]
      Keyword.get(opts, :reset_shortcut, false) -> nil
      true -> snapshot["shortcut"]
    end
  end

  @spec root_parent_id(keyword()) :: integer() | nil
  def root_parent_id(opts), do: Keyword.get(opts, :parent_id)

  @spec root_position(keyword()) :: integer()
  def root_position(opts), do: Keyword.get(opts, :position, 0)

  @spec root_draft_id(keyword()) :: integer() | nil
  def root_draft_id(opts), do: Keyword.get(opts, :draft_id)

  @spec preserve_external_refs?(keyword()) :: boolean()
  def preserve_external_refs?(opts), do: Keyword.get(opts, :preserve_external_refs, true)

  @spec insert_one_returning_id(module(), module(), map()) :: {:ok, integer()} | {:error, term()}
  def insert_one_returning_id(repo, schema, attrs) do
    case repo.insert_all(schema, [attrs], returning: [:id]) do
      {1, [%{id: id}]} -> {:ok, id}
      other -> {:error, {:insert_failed, schema, other}}
    end
  end

  @spec insert_all_returning(module(), module(), [map()], [atom()]) ::
          {:ok, [map()]} | {:error, term()}
  def insert_all_returning(_repo, _schema, [], _returning), do: {:ok, []}

  def insert_all_returning(repo, schema, entries, returning) do
    case repo.insert_all(schema, entries, returning: returning) do
      {count, rows} when count == length(entries) -> {:ok, rows}
      other -> {:error, {:insert_all_failed, schema, other}}
    end
  end

  @spec insert_all(module(), module(), [map()]) :: :ok | {:error, term()}
  def insert_all(_repo, _schema, []), do: :ok

  def insert_all(repo, schema, entries) do
    case repo.insert_all(schema, entries) do
      {count, _} when count == length(entries) -> :ok
      other -> {:error, {:insert_all_failed, schema, other}}
    end
  end

  @spec build_id_map([map()], [map()], String.t()) :: %{optional(integer()) => integer()}
  def build_id_map(snapshot_entries, inserted_rows, original_id_key \\ "original_id") do
    snapshot_entries
    |> Enum.zip(inserted_rows)
    |> Enum.reduce(%{}, fn {snapshot_entry, inserted_row}, acc ->
      case Map.get(snapshot_entry, original_id_key) do
        nil -> acc
        old_id -> Map.put(acc, old_id, inserted_row.id)
      end
    end)
  end

  @spec root_id_map(map(), integer()) :: %{optional(integer()) => integer()}
  def root_id_map(snapshot, new_id) do
    case Map.get(snapshot, "original_id") do
      nil -> %{}
      old_id -> %{old_id => new_id}
    end
  end

  @spec remap_reference(integer() | nil, map(), boolean()) :: integer() | nil
  def remap_reference(nil, _id_map, _preserve_external_refs?), do: nil

  def remap_reference(old_id, id_map, preserve_external_refs?) do
    case Map.fetch(id_map, old_id) do
      {:ok, new_id} -> new_id
      :error when preserve_external_refs? -> old_id
      :error -> nil
    end
  end
end

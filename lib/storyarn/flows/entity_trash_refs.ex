defmodule Storyarn.Flows.EntityTrashRefs do
  @moduledoc """
  Generic sweep + restore API for `flows_entity_trash_refs`.

  When a target entity (sheet, asset, flow, flow_node-hub, sheet_avatar)
  is soft-deleted, call the appropriate `sweep_*` function to move all
  live refs to the trash table. On restore, call `restore/2` to re-apply
  the refs conservatively (only if the live field is currently nil —
  i.e., the user hasn't re-pointed it elsewhere in the meantime).

  Source types supported: `flow_node`.
  Target types supported: `:sheet`, `:asset`, `:flow`, `:flow_node`,
  `:sheet_avatar`.

  The `:flow_sequence` target type was removed in Phase 1 of the flow
  relational refactor: sequences are now `flow_nodes` with
  `type='sequence'` and their inbound refs are handled by a DB trigger.

  Path kinds supported in v1:
    * Column on the source row — see `sweep_column/5`.
    * Flat JSONB field — see `sweep_jsonb_field/6`.

  Nested JSONB array paths are intentionally not part of the current
  sequence media model; sequence visual/audio records are relational.

  All operations run in `Repo.transaction`.

  ## Cross-domain callers

  External contexts (Sheets, Assets) that hold soft-deletable targets must
  call through the `Storyarn.Flows` facade:

      Flows.sweep_trash_refs_jsonb(FlowNode, "flow_node", :data,
        "speaker_sheet_id", :sheet, sheet.id)
      Flows.restore_trash_refs(:sheet, sheet.id)

  This crosses domain boundaries (flagged by static analysis) but is
  necessary for referential integrity — see
  `project_entity_trash_refs_pattern.md` in user memory for the full
  rationale.
  """

  import Ecto.Query

  alias Storyarn.Flows.EntityTrashRef
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  @type target_type ::
          :sheet | :asset | :flow | :flow_node | :sheet_avatar

  @target_type_to_column %{
    sheet: :target_sheet_id,
    asset: :target_asset_id,
    flow: :target_flow_id,
    flow_node: :target_flow_node_id,
    sheet_avatar: :target_sheet_avatar_id
  }

  @source_type_to_schema %{
    "flow_node" => FlowNode
  }

  # ===========================================================================
  # Sweep — column
  # ===========================================================================

  @doc """
  Sweep all rows of `source_schema` where `source_column = target_id`.
  Inserts a trash ref per row; sets the column to nil.

  Returns `{:ok, swept_count}`.
  """
  @spec sweep_column(module(), String.t(), atom(), target_type(), integer()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def sweep_column(source_schema, source_type, source_column, target_type, target_id)
      when is_atom(source_schema) and is_binary(source_type) and is_atom(source_column) and is_integer(target_id) do
    validate_source_type!(source_type)
    target_column = fetch_target_column!(target_type)

    Repo.transaction(fn ->
      rows =
        source_schema
        |> where([s], field(s, ^source_column) == ^target_id)
        |> Repo.all()

      case rows do
        [] ->
          0

        _ ->
          source_field = Atom.to_string(source_column)
          insert_trash_refs(rows, source_type, source_field, target_column, target_id)

          {count, _} =
            source_schema
            |> where([s], field(s, ^source_column) == ^target_id)
            |> Repo.update_all(set: [{source_column, nil}])

          count
      end
    end)
  end

  # ===========================================================================
  # Sweep — flat JSONB field
  # ===========================================================================

  @doc """
  Sweep all rows of `source_schema` whose `jsonb_column->>jsonb_key = target_id`.
  Inserts a trash ref per row; sets the key value to nil inside the JSONB
  (key is preserved, value becomes null).

  Returns `{:ok, swept_count}`.

  ## Example

      # On Sheet delete — sweep flow_nodes.data.speaker_sheet_id
      sweep_jsonb_field(FlowNode, "flow_node", :data, "speaker_sheet_id",
        :sheet, sheet.id)
  """
  @spec sweep_jsonb_field(module(), String.t(), atom(), String.t(), target_type(), integer()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def sweep_jsonb_field(source_schema, source_type, jsonb_column, jsonb_key, target_type, target_id)
      when is_atom(source_schema) and is_binary(source_type) and is_atom(jsonb_column) and is_binary(jsonb_key) and
             is_integer(target_id) do
    validate_source_type!(source_type)
    target_column = fetch_target_column!(target_type)
    target_id_str = Integer.to_string(target_id)

    Repo.transaction(fn ->
      rows =
        source_schema
        |> where(
          [s],
          fragment("?->>? = ?", field(s, ^jsonb_column), ^jsonb_key, ^target_id_str)
        )
        |> Repo.all()

      sweep_jsonb_rows(rows, source_schema, source_type, jsonb_column, jsonb_key, target_column, target_id)
    end)
  end

  # ===========================================================================
  # Restore
  # ===========================================================================

  @doc """
  Restore all trash refs pointing at `{target_type, target_id}`. Conservative:
  only re-applies a ref if the live source field is currently nil (don't yank
  refs the user created in the interim).

  Always deletes the processed trash rows, whether restored or skipped.

  Returns `{:ok, %{restored: n, skipped: m}}`.
  """
  @spec restore(target_type(), integer()) ::
          {:ok, %{restored: non_neg_integer(), skipped: non_neg_integer()}} | {:error, term()}
  def restore(target_type, target_id) when is_integer(target_id) do
    target_column = fetch_target_column!(target_type)

    Repo.transaction(fn ->
      refs =
        EntityTrashRef
        |> where([r], field(r, ^target_column) == ^target_id)
        |> Repo.all()

      results =
        Enum.map(refs, fn ref ->
          outcome = apply_restore(ref, target_id)
          Repo.delete!(ref)
          outcome
        end)

      %{
        restored: Enum.count(results, &(&1 == :restored)),
        skipped: Enum.count(results, &(&1 == :skipped))
      }
    end)
  end

  # ===========================================================================
  # Private helpers
  # ===========================================================================

  defp validate_source_type!(source_type) do
    if !Map.has_key?(@source_type_to_schema, source_type) do
      raise ArgumentError, "invalid source_type: #{inspect(source_type)}"
    end
  end

  defp fetch_target_column!(target_type) do
    case Map.fetch(@target_type_to_column, target_type) do
      {:ok, col} -> col
      :error -> raise ArgumentError, "invalid target_type: #{inspect(target_type)}"
    end
  end

  defp insert_trash_refs(rows, source_type, source_field, target_column, target_id) do
    now = TimeHelpers.now()

    entries =
      Enum.map(rows, fn row ->
        Map.put(
          %{source_type: source_type, source_id: row.id, source_field: source_field, inserted_at: now},
          target_column,
          target_id
        )
      end)

    Repo.insert_all(EntityTrashRef, entries)
  end

  defp sweep_jsonb_rows([], _source_schema, _source_type, _jsonb_column, _jsonb_key, _target_column, _target_id) do
    0
  end

  defp sweep_jsonb_rows(rows, source_schema, source_type, jsonb_column, jsonb_key, target_column, target_id) do
    source_field = "#{jsonb_column}.#{jsonb_key}"
    insert_trash_refs(rows, source_type, source_field, target_column, target_id)
    Enum.each(rows, &clear_jsonb_ref(source_schema, &1, jsonb_column, jsonb_key))
    length(rows)
  end

  defp clear_jsonb_ref(source_schema, row, jsonb_column, jsonb_key) do
    new_jsonb = row |> Map.fetch!(jsonb_column) |> Map.put(jsonb_key, nil)

    source_schema
    |> where([s], s.id == ^row.id)
    |> Repo.update_all(set: [{jsonb_column, new_jsonb}])
  end

  defp apply_restore(%EntityTrashRef{} = ref, target_id) do
    source_schema = Map.fetch!(@source_type_to_schema, ref.source_type)

    if String.contains?(ref.source_field, ".") do
      restore_jsonb_field(ref, source_schema, target_id)
    else
      restore_column(ref, source_schema, target_id)
    end
  end

  defp restore_column(%EntityTrashRef{} = ref, source_schema, target_id) do
    column = String.to_existing_atom(ref.source_field)

    {count, _} =
      source_schema
      |> where([s], s.id == ^ref.source_id and is_nil(field(s, ^column)))
      |> Repo.update_all(set: [{column, target_id}])

    if count > 0, do: :restored, else: :skipped
  end

  defp restore_jsonb_field(%EntityTrashRef{} = ref, source_schema, target_id) do
    [jsonb_col_str, jsonb_key] = String.split(ref.source_field, ".", parts: 2)
    jsonb_column = String.to_existing_atom(jsonb_col_str)

    case Repo.get(source_schema, ref.source_id) do
      nil ->
        :skipped

      row ->
        jsonb_map = Map.fetch!(row, jsonb_column) || %{}

        if Map.get(jsonb_map, jsonb_key) == nil do
          new_jsonb = Map.put(jsonb_map, jsonb_key, target_id)

          source_schema
          |> where([s], s.id == ^ref.source_id)
          |> Repo.update_all(set: [{jsonb_column, new_jsonb}])

          :restored
        else
          :skipped
        end
    end
  end
end

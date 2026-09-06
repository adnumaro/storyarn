defmodule Storyarn.Flows.Editor.Commands.SequenceTracks do
  @moduledoc false

  import Ecto.Query

  alias Storyarn.Flows.Editor.Commands.SequenceCompositionWrite
  alias Storyarn.Flows.Editor.Queries.SequenceComposition
  alias Storyarn.Flows.SequenceTrack
  alias Storyarn.Repo

  @doc "Upserts the local definition for `(owner_id, kind)`. Inherited patches with the same kind are left untouched."
  @spec upsert_sequence_track(integer(), String.t(), map()) ::
          {:ok, SequenceTrack.t()} | {:error, atom() | Ecto.Changeset.t()}
  def upsert_sequence_track(sequence_id, kind, attrs) when is_integer(sequence_id) and is_binary(kind) do
    if kind in SequenceTrack.kinds() do
      do_upsert_sequence_track(sequence_id, kind, attrs)
    else
      {:error, :invalid_kind}
    end
  end

  @doc "Deletes the local definition for `(owner_id, kind)` and preserves inherited patches."
  @spec clear_sequence_track(integer(), String.t()) ::
          {:ok, :cleared} | {:error, atom()}
  def clear_sequence_track(sequence_id, kind) when is_integer(sequence_id) and is_binary(kind) do
    if kind in SequenceTrack.kinds() do
      do_clear_sequence_track(sequence_id, kind)
    else
      {:error, :invalid_kind}
    end
  end

  @doc "Creates or updates the local property patch for an inherited audio track."
  def override_sequence_track(owner_id, track_key, attrs)
      when is_integer(owner_id) and is_binary(track_key) and is_map(attrs) do
    with {:ok, attrs, fields} <-
           SequenceCompositionWrite.normalize_override_attrs(
             attrs,
             SequenceTrack.property_fields()
           ) do
      Repo.transaction(fn ->
        do_override_sequence_track(owner_id, track_key, attrs, fields)
      end)
    end
  end

  defp do_override_sequence_track(owner_id, track_key, attrs, fields) do
    with {:ok, context} <- SequenceCompositionWrite.lock_owner(owner_id),
         local = lock_track_by_key(owner_id, track_key),
         {:ok, inherited} <-
           SequenceComposition.inherited_or_materialized_audio_track(
             context.flow.id,
             context.node,
             track_key,
             local
           ),
         changeset =
           track_override_changeset(
             local,
             inherited.item,
             owner_id,
             track_key,
             attrs,
             fields
           ),
         asset_id = Ecto.Changeset.get_field(changeset, :asset_id),
         {:ok, asset_id} <-
           SequenceCompositionWrite.lock_project_asset(
             context.project_id,
             :sequence_track_asset_id,
             asset_id,
             "audio/%"
           ),
         {:ok, persisted} <- persist_sequence_track(changeset, asset_id, local) do
      persisted
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  @doc "Returns selected local audio-track properties to inheritance."
  def revert_sequence_track_fields(owner_id, track_key, fields)
      when is_integer(owner_id) and is_binary(track_key) and is_list(fields) do
    with {:ok, fields} <-
           SequenceCompositionWrite.normalize_override_fields(
             fields,
             SequenceTrack.property_fields()
           ) do
      Repo.transaction(fn ->
        do_revert_sequence_track_fields(owner_id, track_key, fields)
      end)
    end
  end

  defp do_revert_sequence_track_fields(owner_id, track_key, fields) do
    with {:ok, context} <- SequenceCompositionWrite.lock_owner(owner_id),
         {:ok, _inherited} <-
           SequenceComposition.inherited_audio_track(context.flow.id, context.node, track_key),
         %SequenceTrack{is_override: true} = local <- lock_track_by_key(owner_id, track_key),
         {:ok, result} <- revert_or_delete_track(local, fields) do
      result
    else
      nil -> :inherited
      %SequenceTrack{} -> Repo.rollback(:track_is_local_definition)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  @doc "Removes a local track definition or tombstones an inherited track."
  def remove_sequence_track(owner_id, track_key) when is_integer(owner_id) and is_binary(track_key) do
    Repo.transaction(fn ->
      with {:ok, context} <- SequenceCompositionWrite.lock_owner(owner_id),
           local = lock_track_by_key(owner_id, track_key),
           {:ok, removed} <-
             remove_track(context.flow.id, context.node, local, owner_id, track_key),
           :ok <- SequenceCompositionWrite.validate_dependents(context.flow.id, owner_id) do
        removed
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc "Restores a local tombstone or materializes an inherited tombstoned track."
  def restore_sequence_track(owner_id, track_key) when is_integer(owner_id) and is_binary(track_key) do
    Repo.transaction(fn ->
      with {:ok, context} <- SequenceCompositionWrite.lock_owner(owner_id),
           local = lock_track_by_key(owner_id, track_key),
           {:ok, restored} <- restore_track(context, local, owner_id, track_key) do
        restored
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp do_upsert_sequence_track(sequence_id, kind, attrs) do
    Repo.transaction(fn ->
      with {:ok, %{project_id: project_id}} <-
             SequenceCompositionWrite.lock_owner(sequence_id),
           track = lock_sequence_track(sequence_id, kind),
           changeset = sequence_track_changeset(track, sequence_id, kind, attrs),
           asset_id = Ecto.Changeset.get_field(changeset, :asset_id),
           {:ok, asset_id} <-
             SequenceCompositionWrite.lock_project_asset(
               project_id,
               :sequence_track_asset_id,
               asset_id,
               "audio/%"
             ),
           {:ok, persisted_track} <-
             persist_sequence_track(changeset, asset_id, track) do
        persisted_track
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp do_clear_sequence_track(sequence_id, kind) do
    Repo.transaction(fn -> clear_sequence_track_in_transaction(sequence_id, kind) end)
  end

  defp clear_sequence_track_in_transaction(sequence_id, kind) do
    case SequenceCompositionWrite.lock_owner(sequence_id) do
      {:ok, context} ->
        Repo.delete_all(
          from(track in SequenceTrack,
            where:
              track.flow_node_id == ^sequence_id and track.kind == ^kind and
                track.is_override == false
          )
        )

        finish_clearing_track(SequenceCompositionWrite.validate_dependents(context.flow.id, sequence_id))

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp finish_clearing_track(:ok), do: :cleared
  defp finish_clearing_track({:error, reason}), do: Repo.rollback(reason)

  defp lock_sequence_track(sequence_id, kind) do
    Repo.one(
      from(track in SequenceTrack,
        where:
          track.flow_node_id == ^sequence_id and track.kind == ^kind and
            track.is_override == false,
        lock: "FOR UPDATE"
      )
    )
  end

  defp sequence_track_changeset(nil, sequence_id, kind, attrs) do
    attrs =
      attrs
      |> SequenceCompositionWrite.normalize_keys()
      |> Map.drop(~w(flow_node_id kind track_key is_override overridden_fields removed))
      |> Map.put("flow_node_id", sequence_id)
      |> Map.put("kind", kind)

    SequenceTrack.create_changeset(%SequenceTrack{}, attrs)
  end

  defp sequence_track_changeset(%SequenceTrack{} = track, _sequence_id, _kind, attrs) do
    SequenceTrack.update_changeset(track, SequenceCompositionWrite.normalize_keys(attrs))
  end

  defp persist_sequence_track(changeset, asset_id, nil) do
    changeset
    |> Ecto.Changeset.put_change(:asset_id, asset_id)
    |> Repo.insert()
  end

  defp persist_sequence_track(changeset, asset_id, %SequenceTrack{}) do
    changeset
    |> Ecto.Changeset.put_change(:asset_id, asset_id)
    |> Repo.update()
  end

  defp track_override_changeset(nil, inherited, owner_id, track_key, attrs, fields) do
    inherited
    |> SequenceCompositionWrite.relational_attrs(SequenceTrack.property_fields())
    |> Map.merge(attrs)
    |> Map.merge(%{
      "flow_node_id" => owner_id,
      "kind" => SequenceCompositionWrite.map_value(inherited, :kind),
      "track_key" => track_key,
      "is_override" => true,
      "overridden_fields" => fields,
      "removed" => false
    })
    |> then(&SequenceTrack.override_changeset(%SequenceTrack{}, &1))
  end

  defp track_override_changeset(
         %SequenceTrack{is_override: true} = local,
         _inherited,
         _owner_id,
         _track_key,
         attrs,
         _fields
       ) do
    local
    |> SequenceTrack.update_changeset(attrs)
    |> Ecto.Changeset.put_change(:removed, false)
  end

  defp track_override_changeset(%SequenceTrack{} = local, _inherited, _owner_id, _track_key, _attrs, _fields),
    do: Ecto.Changeset.add_error(Ecto.Changeset.change(local), :track_key, "is a local definition")

  defp lock_track_by_key(owner_id, track_key) do
    Repo.one(
      from(track in SequenceTrack,
        where: track.flow_node_id == ^owner_id and track.track_key == ^track_key,
        lock: "FOR UPDATE"
      )
    )
  end

  defp revert_or_delete_track(local, fields) do
    changeset = SequenceTrack.revert_fields_changeset(local, fields)

    if Ecto.Changeset.get_field(changeset, :overridden_fields) == [] and
         not Ecto.Changeset.get_field(changeset, :removed) do
      case Repo.delete(local) do
        {:ok, _deleted} -> {:ok, :inherited}
        {:error, reason} -> {:error, reason}
      end
    else
      Repo.update(changeset)
    end
  end

  defp persist_track_tombstone(nil, effective, owner_id, track_key) do
    effective
    |> SequenceCompositionWrite.relational_attrs(SequenceTrack.property_fields())
    |> Map.merge(%{
      "flow_node_id" => owner_id,
      "kind" => SequenceCompositionWrite.map_value(effective, :kind),
      "track_key" => track_key,
      "is_override" => true,
      "overridden_fields" => [],
      "removed" => true
    })
    |> then(&SequenceTrack.override_changeset(%SequenceTrack{}, &1))
    |> Repo.insert()
  end

  defp remove_track(_flow_id, _owner, %SequenceTrack{removed: true} = local, _owner_id, _track_key), do: {:ok, local}

  defp remove_track(flow_id, owner, nil, owner_id, track_key) do
    with {:ok, inherited} <-
           SequenceComposition.inherited_audio_track(flow_id, owner, track_key) do
      persist_track_tombstone(nil, inherited.item, owner_id, track_key)
    end
  end

  defp remove_track(_flow_id, _owner, %SequenceTrack{is_override: false} = local, _owner_id, _track_key),
    do: Repo.delete(local)

  defp remove_track(flow_id, owner, %SequenceTrack{} = local, _owner_id, track_key) do
    case SequenceComposition.inherited_audio_track(flow_id, owner, track_key) do
      {:ok, _inherited} ->
        local |> SequenceTrack.removal_changeset(true) |> Repo.update()

      {:error, :inherited_track_not_found} ->
        Repo.delete(local)

      {:error, _reason} = error ->
        error
    end
  end

  defp restore_track(_context, %SequenceTrack{removed: false}, _owner_id, _track_key),
    do: {:error, :sequence_track_not_removed}

  defp restore_track(context, %SequenceTrack{} = local, _owner_id, track_key) do
    case SequenceComposition.inherited_audio_track(context.flow.id, context.node, track_key) do
      {:ok, _inherited} -> restore_track_row(local)
      {:error, :inherited_track_not_found} -> clear_orphan_track_tombstone(local)
      {:error, _reason} = error -> error
    end
  end

  defp restore_track(context, nil, owner_id, track_key) do
    fields = SequenceTrack.property_fields()

    with {:ok, inherited} <-
           SequenceComposition.inherited_removed_audio_track(
             context.flow.id,
             context.node,
             track_key
           ),
         changeset =
           track_override_changeset(
             nil,
             inherited.item,
             owner_id,
             track_key,
             %{},
             fields
           ),
         asset_id = Ecto.Changeset.get_field(changeset, :asset_id),
         {:ok, asset_id} <-
           SequenceCompositionWrite.lock_project_asset(
             context.project_id,
             :sequence_track_asset_id,
             asset_id,
             "audio/%"
           ) do
      persist_sequence_track(changeset, asset_id, nil)
    end
  end

  defp restore_track_row(%SequenceTrack{is_override: true, overridden_fields: []} = local) do
    case Repo.delete(local) do
      {:ok, _deleted} -> {:ok, :inherited}
      {:error, reason} -> {:error, reason}
    end
  end

  defp restore_track_row(local), do: local |> SequenceTrack.removal_changeset(false) |> Repo.update()

  defp clear_orphan_track_tombstone(local) do
    case Repo.delete(local) do
      {:ok, _deleted} -> {:ok, :cleared}
      {:error, reason} -> {:error, reason}
    end
  end
end

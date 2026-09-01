defmodule Storyarn.Projects.Versioning.SnapshotReferences do
  @moduledoc """
  Validates portable snapshot references before Project materialization.

  This rule is deliberately pure: it scans the already validated snapshot and
  checks references only against the preflight identity maps and asset set.
  The scanner and reference order are part of the recovery error contract.
  """

  alias Storyarn.Projects.Versioning.SnapshotReferences.FlowScanner
  alias Storyarn.Projects.Versioning.SnapshotReferences.SceneScanner
  alias Storyarn.Projects.Versioning.SnapshotReferences.SheetScanner

  @spec validate(map(), map(), MapSet.t(), map()) :: :ok | {:error, term()}
  def validate(snapshot_data, id_maps, asset_ids, avatar_owners) do
    scanners = [
      {:sheet, snapshot_data["sheets"], &SheetScanner.scan/1},
      {:flow, snapshot_data["flows"], &FlowScanner.scan/1},
      {:scene, snapshot_data["scenes"], &SceneScanner.scan/1}
    ]

    Enum.reduce_while(scanners, :ok, fn {entity_type, entries, scanner}, :ok ->
      case validate_entity_references(
             entity_type,
             entries,
             scanner,
             id_maps,
             asset_ids,
             avatar_owners
           ) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_entity_references(entity_type, entries, scanner, id_maps, asset_ids, avatar_owners) do
    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      references = scanner.(entry["snapshot"])

      case validate_entry_references(
             references,
             entity_type,
             entry["id"],
             id_maps,
             asset_ids,
             avatar_owners
           ) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_entry_references(references, entity_type, entry_id, id_maps, asset_ids, avatar_owners) do
    Enum.reduce_while(references, :ok, fn reference, :ok ->
      case validate_reference(reference, id_maps, asset_ids, avatar_owners) do
        :ok ->
          {:cont, :ok}

        {:error, reason} ->
          {:halt, {:error, {:missing_project_snapshot_reference, {entity_type, entry_id, reference.context}, reason}}}
      end
    end)
  end

  defp validate_reference(%{type: :asset, id: id}, _id_maps, asset_ids, _avatar_owners) do
    if MapSet.member?(asset_ids, normalize_id(id)), do: :ok, else: {:error, id}
  end

  defp validate_reference(%{type: :avatar, id: id} = reference, id_maps, _asset_ids, avatar_owners) do
    avatar_id = normalize_id(id)
    speaker_id = normalize_id(reference[:speaker_sheet_id])

    cond do
      is_nil(avatar_id) or not Map.has_key?(id_maps.avatar, avatar_id) -> {:error, id}
      is_nil(speaker_id) -> :ok
      Map.get(avatar_owners, avatar_id) == speaker_id -> :ok
      true -> {:error, {:avatar_speaker_mismatch, avatar_id, Map.get(avatar_owners, avatar_id), speaker_id}}
    end
  end

  defp validate_reference(%{type: type, id: id}, id_maps, _asset_ids, _avatar_owners)
       when type in [:sheet, :flow, :scene, :block] do
    normalized_id = normalize_id(id)

    if Map.has_key?(Map.fetch!(id_maps, type), normalized_id),
      do: :ok,
      else: {:error, id}
  end

  defp validate_reference(%{type: type, id: id}, _id_maps, _asset_ids, _avatar_owners),
    do: {:error, {:unsupported_reference, type, id}}

  defp normalize_id(value) when is_integer(value) and value > 0, do: value

  defp normalize_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> id
      _invalid -> nil
    end
  end

  defp normalize_id(_value), do: nil
end

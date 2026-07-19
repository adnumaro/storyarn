defmodule Storyarn.Versioning.ProjectSnapshotIntegrity do
  @moduledoc """
  Validates the storage envelope of a project snapshot against trusted metadata.

  The entity counts stored in `project_snapshots` are written independently from
  the compressed snapshot blob. Comparing both prevents a coherently altered or
  truncated blob from being accepted merely because its embedded counts were
  changed to match its contents.
  """

  @format_version 2
  @count_collections [
    {"sheets", ["sheets"]},
    {"flows", ["flows"]},
    {"scenes", ["scenes"]},
    {"languages", ["localization", "languages"]},
    {"localized_texts", ["localization", "texts"]},
    {"glossary_entries", ["localization", "glossary"]}
  ]
  @checksum_format ~r/\A[0-9a-f]{64}\z/

  @doc """
  Validates the snapshot envelope and its independently persisted checksum
  against the exact bytes loaded from storage.
  """
  @spec validate_recovery_blob(term(), term(), term(), term()) ::
          :ok | {:error, term()}
  def validate_recovery_blob(
        %{"format_version" => @format_version} = snapshot,
        persisted_counts,
        persisted_checksum,
        actual_checksum
      ) do
    with :ok <- validate_envelope(snapshot, persisted_counts),
         {:ok, canonical_counts} <- canonical_entity_counts(snapshot),
         declared_counts = snapshot["entity_counts"],
         :ok <- validate_declared_counts(declared_counts, canonical_counts),
         :ok <- validate_persisted_counts(persisted_counts, canonical_counts) do
      validate_checksum(persisted_checksum, actual_checksum)
    end
  end

  def validate_recovery_blob(%{"format_version" => version}, _persisted_counts, _persisted_checksum, _actual_checksum)
      when version != @format_version do
    {:error, {:unsupported_project_snapshot_format, version}}
  end

  def validate_recovery_blob(_snapshot, _persisted_counts, _persisted_checksum, _actual_checksum) do
    {:error, :invalid_project_snapshot_envelope}
  end

  defp validate_envelope(snapshot, persisted_counts) do
    valid? =
      Enum.all?([
        is_map(persisted_counts),
        is_map(snapshot["entity_counts"]),
        is_map(snapshot["project"]),
        is_list(snapshot["sheets"]),
        is_list(snapshot["flows"]),
        is_list(snapshot["scenes"]),
        is_map(snapshot["tree"]),
        is_map(snapshot["localization"]),
        is_map(snapshot["asset_blob_hashes"]),
        is_map(snapshot["asset_metadata"])
      ])

    if valid?, do: :ok, else: {:error, :invalid_project_snapshot_envelope}
  end

  defp canonical_entity_counts(snapshot) do
    Enum.reduce_while(@count_collections, {:ok, %{}}, fn {count_key, path}, {:ok, counts} ->
      case get_in(snapshot, path) do
        collection when is_list(collection) ->
          {:cont, {:ok, Map.put(counts, count_key, length(collection))}}

        _invalid_collection ->
          {:halt, {:error, {:invalid_project_snapshot_collection, count_key}}}
      end
    end)
  end

  defp validate_declared_counts(declared_counts, canonical_counts) do
    compare_counts(
      declared_counts,
      canonical_counts,
      :invalid_project_snapshot_entity_count,
      :project_snapshot_entity_count_mismatch
    )
  end

  defp validate_persisted_counts(persisted_counts, canonical_counts) do
    compare_counts(
      persisted_counts,
      canonical_counts,
      :invalid_persisted_project_snapshot_entity_count,
      :persisted_project_snapshot_entity_count_mismatch
    )
  end

  defp compare_counts(counts, canonical_counts, invalid_tag, mismatch_tag) do
    Enum.reduce_while(@count_collections, :ok, fn {count_key, _path}, :ok ->
      stored_count = counts[count_key]
      canonical_count = canonical_counts[count_key]

      cond do
        not (is_integer(stored_count) and stored_count >= 0) ->
          {:halt, {:error, {invalid_tag, count_key, stored_count}}}

        stored_count != canonical_count ->
          {:halt, {:error, {mismatch_tag, count_key, stored_count, canonical_count}}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp validate_checksum(nil, _actual_checksum), do: {:error, :missing_project_snapshot_checksum}

  defp validate_checksum(persisted_checksum, actual_checksum)
       when is_binary(persisted_checksum) and is_binary(actual_checksum) do
    cond do
      not Regex.match?(@checksum_format, persisted_checksum) ->
        {:error, {:invalid_persisted_project_snapshot_checksum, persisted_checksum}}

      not Regex.match?(@checksum_format, actual_checksum) ->
        {:error, {:invalid_loaded_project_snapshot_checksum, actual_checksum}}

      secure_checksum_equal?(persisted_checksum, actual_checksum) ->
        :ok

      true ->
        {:error, {:project_snapshot_checksum_mismatch, persisted_checksum, actual_checksum}}
    end
  end

  defp validate_checksum(persisted_checksum, actual_checksum) do
    {:error, {:invalid_project_snapshot_checksum_metadata, persisted_checksum, actual_checksum}}
  end

  defp secure_checksum_equal?(left, right) when byte_size(left) == byte_size(right) do
    Plug.Crypto.secure_compare(left, right)
  end

  defp secure_checksum_equal?(_left, _right), do: false
end

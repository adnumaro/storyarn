defmodule Storyarn.Scenes.Assets.Adapters.Storage.Objects do
  @moduledoc false

  alias Storyarn.Platform.ObjectStorage

  require Logger

  @conditional_copy_suffix_pattern ~r/\A[A-Za-z0-9_-]{16}\z/
  @asset_uuid_pattern ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/

  defdelegate get_url(key), to: ObjectStorage
  defdelegate put_if_absent(key, data, content_type), to: ObjectStorage
  defdelegate copy_if_absent(source_key, destination_key), to: ObjectStorage
  defdelegate canonical_key?(key), to: ObjectStorage
  defdelegate stat(key), to: ObjectStorage
  defdelegate stream(key, offset, length, opts \\ []), to: ObjectStorage
  defdelegate download(key), to: ObjectStorage
  defdelegate delete_if_matches(key, expected_identity), to: ObjectStorage

  def delete(key), do: protected_delete(key)

  def delete_owned_conditional_copy(key) do
    cond do
      not canonical_key?(key) ->
        reject_delete(
          :invalid_key,
          "Blocked conditional-copy deletion for a non-canonical storage key",
          :invalid_delete_blocked
        )

      conditional_copy_key?(key) ->
        ObjectStorage.delete(key)

      recoverable_blob_key?(key) ->
        reject_delete(
          :recoverable_blob,
          "Blocked conditional-copy deletion of a recoverable versioning blob",
          :recoverable_blob_delete_blocked
        )

      true ->
        reject_delete(
          :conditional_copy_not_owned,
          "Blocked conditional-copy deletion for a key not owned by Scenes cleanup",
          :conditional_copy_delete_blocked
        )
    end
  end

  defp protected_delete(key) do
    cond do
      not canonical_key?(key) ->
        reject_delete(
          :invalid_key,
          "Blocked deletion for a non-canonical storage key",
          :invalid_delete_blocked
        )

      recoverable_blob_key?(key) ->
        reject_delete(
          :recoverable_blob,
          "Blocked deletion of a recoverable versioning blob",
          :recoverable_blob_delete_blocked
        )

      true ->
        ObjectStorage.delete(key)
    end
  end

  defp recoverable_blob_key?(key) when is_binary(key) do
    case String.split(key, "/", trim: false) do
      ["projects", project_id, "blobs" | tail] -> valid_project_id?(project_id) and canonical_tail?(tail)
      _segments -> false
    end
  end

  defp recoverable_blob_key?(_key), do: false

  defp conditional_copy_key?(key) when is_binary(key) do
    case String.split(key, "/", trim: false) do
      ["projects", project_id, "blobs", ".storyarn-copy", suffix] ->
        valid_project_id?(project_id) and String.match?(suffix, @conditional_copy_suffix_pattern)

      ["projects", project_id, "assets", asset_uuid, ".storyarn-copy", suffix] ->
        valid_project_id?(project_id) and String.match?(asset_uuid, @asset_uuid_pattern) and
          String.match?(suffix, @conditional_copy_suffix_pattern)

      _parts ->
        false
    end
  end

  defp conditional_copy_key?(_key), do: false

  defp valid_project_id?(project_id) do
    case Integer.parse(project_id) do
      {id, ""} when id > 0 -> true
      _invalid -> false
    end
  end

  defp canonical_tail?(tail), do: tail != [] and Enum.all?(tail, &(&1 != "" and &1 not in [".", ".."]))

  defp reject_delete(reason, message, event) do
    Logger.warning(message)
    :telemetry.execute([:storyarn, :assets, :storage, event], %{count: 1}, %{})
    {:error, reason}
  end
end

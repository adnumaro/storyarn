defmodule Storyarn.Scenes.Versioning.Adapters.Storage.Objects do
  @moduledoc false

  alias Storyarn.Platform.ObjectStorage

  require Logger

  defdelegate canonical_key?(key), to: ObjectStorage
  defdelegate upload(key, data, content_type), to: ObjectStorage
  defdelegate stat(key), to: ObjectStorage
  defdelegate stream(key, offset, length, opts \\ []), to: ObjectStorage

  def delete(key) do
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

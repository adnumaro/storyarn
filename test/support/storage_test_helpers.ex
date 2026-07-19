defmodule Storyarn.StorageTestHelpers do
  @moduledoc false

  alias Storyarn.Assets.Storage

  def delete_storage_blob(key) when is_binary(key) do
    if !recoverable_blob_key?(key) do
      raise ArgumentError, "expected a canonical recoverable blob key"
    end

    Storage.adapter().delete(key)
  end

  defp recoverable_blob_key?(key) do
    case String.split(key, "/", trim: false) do
      ["projects", project_id, "blobs" | tail] ->
        positive_integer?(project_id) and
          tail != [] and
          Enum.all?(tail, &valid_segment?/1)

      _segments ->
        false
    end
  end

  defp positive_integer?(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> true
      _invalid -> false
    end
  end

  defp valid_segment?(segment), do: segment != "" and segment not in [".", ".."]
end

defmodule Storyarn.SnapshotResetStorage do
  @moduledoc false

  @objects_key {__MODULE__, :objects}
  @failures_key {__MODULE__, :failures}

  def put_objects(objects) when is_map(objects) do
    Process.put(@objects_key, objects)
    Process.put(@failures_key, MapSet.new())
    :ok
  end

  def fail_once(keys) when is_list(keys) do
    Process.put(@failures_key, MapSet.new(keys))
    :ok
  end

  def objects, do: Process.get(@objects_key, %{})

  def list_prefix(prefix, opts) do
    limit = Keyword.fetch!(opts, :limit)
    cursor = Keyword.get(opts, :cursor)

    with {:ok, offset} <- decode_cursor(cursor) do
      matching =
        objects()
        |> Enum.filter(fn {key, _size} -> String.starts_with?(key, prefix) end)
        |> Enum.sort_by(&elem(&1, 0))

      page = Enum.slice(matching, offset, limit)
      next_offset = offset + length(page)

      {:ok,
       %{
         objects: Enum.map(page, fn {key, size} -> %{key: key, size: size} end),
         cursor: if(next_offset < length(matching), do: Integer.to_string(next_offset))
       }}
    end
  end

  def delete(key) do
    failures = Process.get(@failures_key, MapSet.new())

    if MapSet.member?(failures, key) do
      Process.put(@failures_key, MapSet.delete(failures, key))
      {:error, :injected_delete_failure}
    else
      Process.put(@objects_key, Map.delete(objects(), key))
      :ok
    end
  end

  defp decode_cursor(nil), do: {:ok, 0}

  defp decode_cursor(cursor) when is_binary(cursor) do
    case Integer.parse(cursor) do
      {offset, ""} when offset >= 0 -> {:ok, offset}
      _invalid -> {:error, :invalid_cursor}
    end
  end
end

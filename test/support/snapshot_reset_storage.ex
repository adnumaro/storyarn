defmodule Storyarn.SnapshotResetStorage do
  @moduledoc false

  @objects_key {__MODULE__, :objects}
  @failures_key {__MODULE__, :failures}
  @replace_before_delete_key {__MODULE__, :replace_before_delete}

  def put_objects(objects) when is_map(objects) do
    normalized =
      Map.new(objects, fn
        {key, size} when is_integer(size) -> {key, %{identity: identity(key, size), size: size}}
        {key, %{identity: identity, size: size}} -> {key, %{identity: identity, size: size}}
      end)

    Process.put(@objects_key, normalized)
    Process.put(@failures_key, MapSet.new())
    Process.put(@replace_before_delete_key, MapSet.new())
    :ok
  end

  def fail_once(keys) when is_list(keys) do
    Process.put(@failures_key, MapSet.new(keys))
    :ok
  end

  def objects, do: Process.get(@objects_key, %{})

  def replace_object(key, size) when is_binary(key) and is_integer(size) and size >= 0 do
    replacement = %{identity: identity(key, size), size: size}
    Process.put(@objects_key, Map.put(objects(), key, replacement))
    :ok
  end

  def replace_before_delete(keys) when is_list(keys) do
    Process.put(@replace_before_delete_key, MapSet.new(keys))
    :ok
  end

  def list_prefix(prefix, opts) do
    limit = Keyword.fetch!(opts, :limit)
    cursor = Keyword.get(opts, :cursor)

    with {:ok, offset} <- decode_cursor(cursor) do
      matching =
        objects()
        |> Enum.filter(fn {key, _object} -> String.starts_with?(key, prefix) end)
        |> Enum.sort_by(&elem(&1, 0))

      page = Enum.slice(matching, offset, limit)
      next_offset = offset + length(page)

      {:ok,
       %{
         objects:
           Enum.map(page, fn {key, %{identity: identity, size: size}} ->
             %{identity: identity, key: key, size: size}
           end),
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

  def delete_if_matches(key, expected_identity) do
    maybe_replace_before_delete(key)

    case Map.get(objects(), key) do
      nil ->
        :ok

      %{identity: ^expected_identity} ->
        delete(key)

      %{identity: _different} ->
        {:error, :object_changed}
    end
  end

  defp maybe_replace_before_delete(key) do
    replacements = Process.get(@replace_before_delete_key, MapSet.new())

    if MapSet.member?(replacements, key) do
      Process.put(@replace_before_delete_key, MapSet.delete(replacements, key))
      %{size: size} = Map.fetch!(objects(), key)
      replace_object(key, size)
    end
  end

  defp identity(key, size) do
    nonce = System.unique_integer([:positive, :monotonic])
    :sha256 |> :crypto.hash("#{key}:#{size}:#{nonce}") |> Base.encode16(case: :lower)
  end

  defp decode_cursor(nil), do: {:ok, 0}

  defp decode_cursor(cursor) when is_binary(cursor) do
    case Integer.parse(cursor) do
      {offset, ""} when offset >= 0 -> {:ok, offset}
      _invalid -> {:error, :invalid_cursor}
    end
  end
end

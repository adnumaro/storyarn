defmodule Storyarn.SnapshotResetStorage do
  @moduledoc false

  alias Storyarn.Assets.Storage.Local

  @objects_key {__MODULE__, :objects}
  @failures_key {__MODULE__, :failures}
  @insert_before_list_key {__MODULE__, :insert_before_list}
  @list_prefix_metadata_response_key {__MODULE__, :list_prefix_metadata_response}
  @list_call_count_key {__MODULE__, :list_call_count}
  @namespace_fingerprint_key {__MODULE__, :namespace_fingerprint}
  @replace_before_delete_key {__MODULE__, :replace_before_delete}

  def put_objects(objects) when is_map(objects) do
    Process.put(@objects_key, normalize_objects(objects))
    Process.put(@failures_key, MapSet.new())
    Process.delete(@insert_before_list_key)
    Process.delete(@list_prefix_metadata_response_key)
    Process.put(@list_call_count_key, 0)
    Process.put(@namespace_fingerprint_key, String.duplicate("c", 64))
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

  def insert_before_list(call_number, objects) when is_integer(call_number) and call_number > 0 and is_map(objects) do
    Process.put(@insert_before_list_key, {call_number, normalize_objects(objects)})
    :ok
  end

  def put_list_prefix_metadata_response(response) do
    Process.put(@list_prefix_metadata_response_key, response)
    :ok
  end

  def list_prefix(prefix, opts) do
    maybe_insert_before_list()

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

  def list_prefix_metadata(prefix, opts) do
    case Process.delete(@list_prefix_metadata_response_key) do
      nil ->
        with {:ok, %{objects: objects, cursor: cursor}} <- list_prefix(prefix, opts) do
          {:ok, %{objects: Enum.map(objects, &Map.take(&1, [:key, :size])), cursor: cursor}}
        end

      response ->
        response
    end
  end

  defdelegate stat(key), to: Local
  defdelegate stream(key, offset, length, opts), to: Local

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

  def namespace_fingerprint, do: {:ok, Process.get(@namespace_fingerprint_key, String.duplicate("c", 64))}

  def change_namespace_fingerprint do
    Process.put(@namespace_fingerprint_key, String.duplicate("d", 64))
    :ok
  end

  defp maybe_replace_before_delete(key) do
    replacements = Process.get(@replace_before_delete_key, MapSet.new())

    if MapSet.member?(replacements, key) do
      Process.put(@replace_before_delete_key, MapSet.delete(replacements, key))
      %{size: size} = Map.fetch!(objects(), key)
      replace_object(key, size)
    end
  end

  defp maybe_insert_before_list do
    call_number = Process.get(@list_call_count_key, 0) + 1
    Process.put(@list_call_count_key, call_number)

    case Process.get(@insert_before_list_key) do
      {^call_number, inserted} ->
        Process.delete(@insert_before_list_key)
        Process.put(@objects_key, Map.merge(objects(), inserted))

      _none ->
        :ok
    end
  end

  defp normalize_objects(objects) do
    Map.new(objects, fn
      {key, size} when is_integer(size) -> {key, %{identity: identity(key, size), size: size}}
      {key, %{identity: identity, size: size}} -> {key, %{identity: identity, size: size}}
    end)
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

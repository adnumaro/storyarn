defmodule Storyarn.Assets.Storage.Local do
  @moduledoc """
  Local file storage adapter for development.

  Stores files in priv/static/uploads and serves them through authenticated media routes.
  """

  @behaviour Storyarn.Assets.Storage

  alias Storyarn.Assets.Storage.Local.ConditionalCopyRegistry

  @stream_chunk_size 1_048_576
  @conditional_copy_directory ".storyarn-copy"
  @conditional_copy_suffix_pattern ~r/\A[A-Za-z0-9_-]{16}\z/
  @default_conditional_copy_stale_after_seconds 3_600

  @impl true
  # sobelow_skip ["Traversal.FileModule"]
  def upload(key, data, _content_type) do
    with {:ok, path} <- file_path(key),
         :ok <- ensure_directory(path),
         :ok <- File.write(path, data) do
      {:ok, get_url(key)}
    end
  end

  @impl true
  # sobelow_skip ["Traversal.FileModule"]
  def put_if_absent(key, data, _content_type) do
    with {:ok, path} <- file_path(key),
         :ok <- ensure_directory(path) do
      case File.write(path, data, [:binary, :exclusive]) do
        :ok -> {:ok, get_url(key), true}
        {:error, :eexist} -> {:ok, get_url(key), false}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @impl true
  # sobelow_skip ["Traversal.FileModule"]
  def download(key) do
    with {:ok, path} <- file_path(key) do
      File.read(path)
    end
  end

  @impl true
  def stat(key) do
    with {:ok, path} <- file_path(key),
         {:ok, stat} <- File.stat(path) do
      {:ok, %{size: stat.size, etag: nil, content_type: MIME.from_path(key)}}
    end
  end

  @impl true
  def stream(key, offset, length, _opts) when is_integer(offset) and offset >= 0 and is_integer(length) and length >= 0 do
    with {:ok, path} <- file_path(key) do
      {:ok, file_stream(path, offset, length)}
    end
  end

  def stream(_key, _offset, _length, _opts), do: {:error, :invalid_range}

  @impl true
  # sobelow_skip ["Traversal.FileModule"]
  def delete(key) do
    with {:ok, path} <- file_path(key, allow_conditional_copy: true) do
      case File.rm(path) do
        :ok -> :ok
        {:error, :enoent} -> :ok
        error -> error
      end
    end
  end

  @impl true
  def get_url(key) do
    public_path = config()[:public_path] || "/uploads"
    safe_key = validate_key!(key)

    Path.join(public_path, safe_key)
  end

  @impl true
  # sobelow_skip ["Traversal.FileModule"]
  def copy(source_key, dest_key) do
    with {:ok, source_path} <- file_path(source_key),
         {:ok, dest_path} <- file_path(dest_key),
         :ok <- ensure_directory(dest_path) do
      File.cp(source_path, dest_path)
    end
  end

  @impl true
  # sobelow_skip ["Traversal.FileModule"]
  def copy_if_absent(source_key, dest_key) do
    with {:ok, source_path} <- file_path(source_key),
         {:ok, dest_path} <- file_path(dest_key),
         temporary_key = temporary_copy_key(dest_key),
         {:ok, temporary_path} <- file_path(temporary_key, allow_conditional_copy: true),
         :ok <- ensure_directory(dest_path),
         :ok <- ensure_directory(temporary_path),
         {:ok, result} <-
           File.open(source_path, [:read, :binary], fn source ->
             copy_open_source_if_absent(source, dest_path, temporary_path, temporary_key)
           end) do
      result
    end
  end

  @doc false
  @spec cleanup_stale_conditional_copies() :: :ok | {:error, [{String.t(), term()}]}
  def cleanup_stale_conditional_copies do
    cutoff = System.system_time(:second) - conditional_copy_stale_after_seconds()
    {conditional_copy_paths, traversal_failures} = conditional_copy_paths(upload_dir())

    failures =
      Enum.reduce(conditional_copy_paths, traversal_failures, fn path, failures ->
        case remove_stale_conditional_copy(path, cutoff) do
          :ok -> failures
          {:error, reason} -> [{path, reason} | failures]
        end
      end)

    case Enum.reverse(failures) do
      [] -> :ok
      failures -> {:error, failures}
    end
  end

  @impl true
  def presigned_upload_url(_key, _content_type, _opts) do
    # Local storage doesn't support presigned URLs
    # Files should be uploaded through the server
    {:error, :not_supported}
  end

  @impl true
  def key_from_url(url) when is_binary(url) do
    public_path = config()[:public_path] || "/uploads"
    path = URI.parse(url).path || ""
    prefix = String.trim_trailing(public_path, "/") <> "/"

    if String.starts_with?(path, prefix) do
      case validate_key(String.replace_prefix(path, prefix, "")) do
        {:ok, key} -> {:ok, key}
        {:error, :invalid_key} -> {:error, :invalid_url}
      end
    else
      {:error, :invalid_url}
    end
  end

  def key_from_url(_url), do: {:error, :invalid_url}

  defp file_path(key, opts \\ []) do
    with {:ok, key} <- validate_key(key, opts) do
      upload_dir = upload_dir()
      path = Path.expand(Path.join(upload_dir, key))

      if path_inside?(path, upload_dir), do: {:ok, path}, else: {:error, :invalid_key}
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp ensure_directory(path) do
    path
    |> Path.dirname()
    |> File.mkdir_p()
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp copy_open_source_if_absent(source, dest_path, temporary_path, temporary_key) do
    ConditionalCopyRegistry.with_active_copy(temporary_path, fn ->
      copy_to_temporary_and_publish(source, dest_path, temporary_path, temporary_key)
    end)
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp copy_to_temporary_and_publish(source, dest_path, temporary_path, temporary_key) do
    case File.open(temporary_path, [:write, :binary, :exclusive], fn destination ->
           {:copy_result, copy_chunks(source, destination)}
         end) do
      {:ok, {:copy_result, :ok}} ->
        publish_temporary_copy(temporary_path, temporary_key, dest_path)

      {:ok, {:copy_result, {:error, reason}}} ->
        cleanup_partial_copy(temporary_path, temporary_key, reason)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp copy_chunks(source, destination) do
    case IO.binread(source, @stream_chunk_size) do
      data when is_binary(data) ->
        case IO.binwrite(destination, data) do
          :ok -> copy_chunks(source, destination)
          {:error, reason} -> {:error, reason}
        end

      :eof ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp publish_temporary_copy(temporary_path, temporary_key, dest_path) do
    case File.ln(temporary_path, dest_path) do
      :ok ->
        finish_conditional_copy(temporary_path, temporary_key, true)

      {:error, :eexist} ->
        finish_conditional_copy(temporary_path, temporary_key, false)

      {:error, reason} ->
        cleanup_partial_copy(temporary_path, temporary_key, reason)
    end
  end

  defp temporary_copy_key(dest_key) do
    suffix = 12 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    Path.join([Path.dirname(dest_key), @conditional_copy_directory, suffix])
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp finish_conditional_copy(temporary_path, temporary_key, destination_created?) do
    case remove_temporary_copy(temporary_path) do
      :ok ->
        {:ok, destination_created?}

      {:error, :enoent} ->
        {:ok, destination_created?}

      {:error, reason} ->
        {:error, {:conditional_copy_cleanup_required, destination_created?, temporary_key, reason}}
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp cleanup_partial_copy(temporary_path, temporary_key, copy_reason) do
    case remove_temporary_copy(temporary_path) do
      :ok ->
        {:error, copy_reason}

      {:error, :enoent} ->
        {:error, copy_reason}

      {:error, cleanup_reason} ->
        cleanup_failure = {:copy_failed, copy_reason, cleanup_reason}
        {:error, {:conditional_copy_cleanup_required, false, temporary_key, cleanup_failure}}
    end
  end

  defp remove_temporary_copy(path) do
    case config()[:conditional_copy_file_rm] do
      remove when is_function(remove, 1) -> remove.(path)
      _other -> File.rm(path)
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp remove_stale_conditional_copy(path, cutoff) do
    if ConditionalCopyRegistry.owner_marker?(path) do
      remove_orphaned_owner_marker(path, cutoff)
    else
      remove_stale_copy(path, cutoff)
    end
  end

  defp remove_stale_copy(path, cutoff) do
    if ConditionalCopyRegistry.active?(path, cutoff) do
      :ok
    else
      remove_stale_regular_file(
        path,
        cutoff,
        fn -> ConditionalCopyRegistry.remove_inactive_owner_marker(path, cutoff) end
      )
    end
  end

  defp remove_orphaned_owner_marker(marker_path, cutoff) do
    copy_path = ConditionalCopyRegistry.copy_path_from_owner_marker(marker_path)

    case File.lstat(copy_path) do
      {:ok, _stat} ->
        :ok

      {:error, :enoent} ->
        remove_stale_owner_marker(copy_path, marker_path, cutoff)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp remove_stale_owner_marker(copy_path, marker_path, cutoff) do
    if ConditionalCopyRegistry.active?(copy_path, cutoff) do
      :ok
    else
      remove_stale_regular_file(marker_path, cutoff, fn -> :ok end)
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp remove_stale_regular_file(path, cutoff, after_remove) do
    case File.lstat(path, time: :posix) do
      {:ok, %{type: :regular, mtime: mtime}} when mtime <= cutoff ->
        remove_file(path, after_remove)

      {:ok, _stat} ->
        :ok

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp remove_file(path, after_remove) do
    case File.rm(path) do
      :ok -> after_remove.()
      {:error, :enoent} -> after_remove.()
      {:error, reason} -> {:error, reason}
    end
  end

  defp conditional_copy_paths(root) do
    walk_storage_directories([root], [], [])
  end

  defp walk_storage_directories([], candidates, failures), do: {candidates, failures}

  defp walk_storage_directories([directory | rest], candidates, failures) do
    case File.ls(directory) do
      {:ok, entries} ->
        {directories, candidates, failures} =
          Enum.reduce(entries, {rest, candidates, failures}, fn entry, acc ->
            collect_storage_entry(directory, entry, acc)
          end)

        walk_storage_directories(directories, candidates, failures)

      {:error, :enoent} ->
        walk_storage_directories(rest, candidates, failures)

      {:error, reason} ->
        walk_storage_directories(rest, candidates, [{directory, reason} | failures])
    end
  end

  defp collect_storage_entry(directory, entry, {directories, candidates, failures}) do
    path = Path.join(directory, entry)

    case File.lstat(path) do
      {:ok, %{type: :directory}} when entry == @conditional_copy_directory ->
        collect_conditional_copy_directory(path, directories, candidates, failures)

      {:ok, %{type: :directory}} ->
        {[path | directories], candidates, failures}

      {:ok, _stat} ->
        {directories, candidates, failures}

      {:error, :enoent} ->
        {directories, candidates, failures}

      {:error, reason} ->
        {directories, candidates, [{path, reason} | failures]}
    end
  end

  defp collect_conditional_copy_directory(path, directories, candidates, failures) do
    case File.ls(path) do
      {:ok, entries} ->
        candidates =
          entries
          |> Enum.map(&Path.join(path, &1))
          |> Enum.filter(&(generated_conditional_copy_path?(&1) or generated_owner_marker_path?(&1)))
          |> Kernel.++(candidates)

        {directories, candidates, failures}

      {:error, :enoent} ->
        {directories, candidates, failures}

      {:error, reason} ->
        {directories, candidates, [{path, reason} | failures]}
    end
  end

  defp generated_conditional_copy_path?(path) do
    Path.basename(Path.dirname(path)) == @conditional_copy_directory and
      String.match?(Path.basename(path), @conditional_copy_suffix_pattern)
  end

  defp generated_owner_marker_path?(path) do
    basename = Path.basename(path)

    Path.basename(Path.dirname(path)) == @conditional_copy_directory and
      String.ends_with?(basename, ".owner") and
      String.match?(
        String.trim_trailing(basename, ".owner"),
        @conditional_copy_suffix_pattern
      )
  end

  defp conditional_copy_stale_after_seconds do
    case config()[:conditional_copy_stale_after_seconds] do
      seconds when is_integer(seconds) and seconds >= 0 -> seconds
      _other -> @default_conditional_copy_stale_after_seconds
    end
  end

  defp file_stream(_path, _offset, 0), do: []

  defp file_stream(path, offset, length) do
    Stream.resource(
      fn -> open_stream_file(path, offset, length) end,
      &read_stream_chunk/1,
      &close_stream_file/1
    )
  end

  defp open_stream_file(path, offset, length) do
    case File.open(path, [:read, :binary]) do
      {:ok, file} ->
        case :file.position(file, offset) do
          {:ok, _position} ->
            {:open, file, length}

          {:error, reason} ->
            File.close(file)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_stream_chunk({:open, _file, 0} = state), do: {:halt, state}
  defp read_stream_chunk({:done, _file} = state), do: {:halt, state}
  defp read_stream_chunk({:error, reason}), do: {[{:error, reason}], :done}
  defp read_stream_chunk(:done), do: {:halt, :done}

  defp read_stream_chunk({:open, file, remaining}) do
    bytes_to_read = min(remaining, @stream_chunk_size)

    case IO.binread(file, bytes_to_read) do
      data when is_binary(data) and byte_size(data) == bytes_to_read ->
        {[{:ok, data}], {:open, file, remaining - byte_size(data)}}

      data when is_binary(data) ->
        {[{:error, {:unexpected_length, byte_size(data), bytes_to_read}}], {:done, file}}

      :eof ->
        {[{:error, :unexpected_eof}], {:done, file}}

      {:error, reason} ->
        {[{:error, reason}], {:done, file}}
    end
  end

  defp close_stream_file({:open, file, _remaining}), do: File.close(file)
  defp close_stream_file({:done, file}), do: File.close(file)
  defp close_stream_file(_state), do: :ok

  defp config do
    Application.get_env(:storyarn, :storage, [])
  end

  defp upload_dir do
    config()
    |> Keyword.get(:upload_dir, "priv/static/uploads")
    |> Path.expand()
  end

  defp validate_key!(key) do
    case validate_key(key) do
      {:ok, safe_key} -> safe_key
      {:error, :invalid_key} -> raise ArgumentError, "invalid storage key"
    end
  end

  defp validate_key(key, opts \\ [])

  defp validate_key(key, opts) when is_binary(key) do
    with :ok <- validate_key_bytes(key),
         :ok <- validate_key_path(key),
         :ok <- validate_key_namespace(key, opts) do
      {:ok, key}
    end
  end

  defp validate_key(_key, _opts), do: {:error, :invalid_key}

  defp validate_key_bytes(key) do
    cond do
      key == "" -> {:error, :invalid_key}
      not String.valid?(key) -> {:error, :invalid_key}
      String.contains?(key, <<0>>) -> {:error, :invalid_key}
      String.contains?(key, "\\") -> {:error, :invalid_key}
      true -> :ok
    end
  end

  defp validate_key_path(key) do
    cond do
      Path.type(key) != :relative -> {:error, :invalid_key}
      invalid_segments?(key) -> {:error, :invalid_key}
      true -> :ok
    end
  end

  defp validate_key_namespace(key, opts) do
    allow_conditional_copy? = Keyword.get(opts, :allow_conditional_copy, false)

    if allow_conditional_copy? or @conditional_copy_directory not in Path.split(key),
      do: :ok,
      else: {:error, :invalid_key}
  end

  defp invalid_segments?(key) do
    key
    |> Path.split()
    |> Enum.any?(&(&1 in [".", ".."]))
  end

  defp path_inside?(path, root) do
    path == root or String.starts_with?(path, root <> "/")
  end
end

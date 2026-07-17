defmodule Storyarn.Assets.Storage.Local do
  @moduledoc """
  Local file storage adapter for development.

  Stores files in priv/static/uploads and serves them through authenticated media routes.
  """

  @behaviour Storyarn.Assets.Storage

  require Logger

  @stream_chunk_size 1_048_576

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
    with {:ok, path} <- file_path(key) do
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
         :ok <- ensure_directory(dest_path),
         {:ok, result} <-
           File.open(source_path, [:read, :binary], fn source ->
             copy_open_source_if_absent(source, dest_path)
           end) do
      result
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

  defp file_path(key) do
    with {:ok, key} <- validate_key(key) do
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
  defp copy_open_source_if_absent(source, dest_path) do
    temporary_path = temporary_copy_path(dest_path)

    case File.open(temporary_path, [:write, :binary, :exclusive], fn destination ->
           {:copy_result, copy_chunks(source, destination)}
         end) do
      {:ok, {:copy_result, :ok}} ->
        publish_temporary_copy(temporary_path, dest_path)

      {:ok, {:copy_result, {:error, reason}}} ->
        cleanup_partial_copy(temporary_path, reason)

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
  defp publish_temporary_copy(temporary_path, dest_path) do
    case File.ln(temporary_path, dest_path) do
      :ok ->
        discard_temporary_copy(temporary_path)
        {:ok, true}

      {:error, :eexist} ->
        discard_temporary_copy(temporary_path)
        {:ok, false}

      {:error, reason} ->
        cleanup_partial_copy(temporary_path, reason)
    end
  end

  defp temporary_copy_path(dest_path) do
    suffix = 12 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    "#{dest_path}.storyarn-copy-#{suffix}"
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp discard_temporary_copy(temporary_path) do
    case File.rm(temporary_path) do
      :ok ->
        :ok

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        Logger.warning("Could not remove local conditional-copy temporary file error=#{inspect(reason)}")
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp cleanup_partial_copy(temporary_path, copy_reason) do
    case File.rm(temporary_path) do
      :ok -> {:error, copy_reason}
      {:error, :enoent} -> {:error, copy_reason}
      {:error, cleanup_reason} -> {:error, {:copy_failed_cleanup_failed, copy_reason, cleanup_reason}}
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

  defp validate_key(key) when is_binary(key) do
    cond do
      key == "" ->
        {:error, :invalid_key}

      not String.valid?(key) ->
        {:error, :invalid_key}

      String.contains?(key, <<0>>) or String.contains?(key, "\\") ->
        {:error, :invalid_key}

      Path.type(key) != :relative ->
        {:error, :invalid_key}

      invalid_segments?(key) ->
        {:error, :invalid_key}

      true ->
        {:ok, key}
    end
  end

  defp validate_key(_key), do: {:error, :invalid_key}

  defp invalid_segments?(key) do
    key
    |> Path.split()
    |> Enum.any?(&(&1 in [".", ".."]))
  end

  defp path_inside?(path, root) do
    path == root or String.starts_with?(path, root <> "/")
  end
end

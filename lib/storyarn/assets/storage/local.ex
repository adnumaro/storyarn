defmodule Storyarn.Assets.Storage.Local do
  @moduledoc """
  Local file storage adapter for development.

  Stores files in priv/static/uploads and serves them through authenticated media routes.
  """

  @behaviour Storyarn.Assets.Storage

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
  def download(key) do
    with {:ok, path} <- file_path(key) do
      File.read(path)
    end
  end

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
  def presigned_upload_url(_key, _content_type, _opts) do
    # Local storage doesn't support presigned URLs
    # Files should be uploaded through the server
    {:error, :not_supported}
  end

  @impl true
  def presigned_download_url(_key, _opts) do
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

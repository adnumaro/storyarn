defmodule Storyarn.Assets.Storage.Local do
  @moduledoc """
  Local file storage adapter for development.

  Stores files in priv/static/uploads and serves them via the static plug.
  """

  @behaviour Storyarn.Assets.Storage

  @impl true
  def upload(key, data, _content_type) do
    path = file_path(key)

    with :ok <- ensure_directory(path),
         :ok <- File.write(path, data) do
      {:ok, get_url(key)}
    end
  end

  @impl true
  def delete(key) do
    path = file_path(key)

    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      error -> error
    end
  end

  @impl true
  def get_url(key) do
    public_path = config()[:public_path] || "/uploads"
    "#{public_path}/#{key}"
  end

  @impl true
  def presigned_upload_url(_key, _content_type, _opts) do
    # Local storage doesn't support presigned URLs
    # Files should be uploaded through the server
    {:error, :not_supported}
  end

  defp file_path(key) do
    upload_dir = config()[:upload_dir] || "priv/static/uploads"
    Path.join([upload_dir, key])
  end

  defp ensure_directory(path) do
    path
    |> Path.dirname()
    |> File.mkdir_p()
  end

  defp config do
    Application.get_env(:storyarn, :storage, [])
  end
end

defmodule Storyarn.FailingStreamStorage do
  @moduledoc false

  @behaviour Storyarn.Projects.Assets.Storage

  @impl true
  defdelegate list_prefix(prefix, opts), to: Storyarn.Projects.Assets.Storage.Local

  @impl true
  def stat(_key), do: {:ok, %{size: 8, etag: nil, content_type: "application/octet-stream"}}

  @impl true
  def stream(_key, _offset, _length, _opts), do: {:ok, [{:ok, "partial"}, {:error, :storage_timeout}]}

  @impl true
  def upload(_key, _data, _content_type), do: {:error, :unsupported}

  @impl true
  def upload_stream(_key, _chunks, _content_type), do: {:error, :unsupported}

  @impl true
  def put_if_absent(_key, _data, _content_type), do: {:error, :unsupported}

  @impl true
  def delete(_key), do: {:error, :unsupported}

  @impl true
  def delete_if_matches(_key, _identity), do: {:error, :unsupported}

  @impl true
  def namespace_fingerprint, do: {:ok, String.duplicate("a", 64)}

  @impl true
  def get_url(_key), do: ""

  @impl true
  def download(_key), do: {:error, :unsupported}

  @impl true
  def presigned_upload_url(_key, _content_type, _opts), do: {:error, :unsupported}

  @impl true
  def presigned_download_url(_key, _content_type, _opts), do: {:error, :not_supported}

  @impl true
  def copy(_source_key, _dest_key), do: {:error, :unsupported}

  @impl true
  def copy_if_absent(_source_key, _dest_key), do: {:error, :unsupported}

  @impl true
  def key_from_url(_url), do: {:error, :invalid_url}
end

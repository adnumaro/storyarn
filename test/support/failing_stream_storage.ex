defmodule Storyarn.FailingStreamStorage do
  @moduledoc false

  @behaviour Storyarn.Assets.Storage

  @impl true
  def stat(_key), do: {:ok, %{size: 8, etag: nil, content_type: "application/octet-stream"}}

  @impl true
  def stream(_key, _offset, _length, _opts), do: {:ok, [{:ok, "partial"}, {:error, :storage_timeout}]}

  @impl true
  def upload(_key, _data, _content_type), do: {:error, :unsupported}

  @impl true
  def put_if_absent(_key, _data, _content_type), do: {:error, :unsupported}

  @impl true
  def delete(_key), do: {:error, :unsupported}

  @impl true
  def get_url(_key), do: ""

  @impl true
  def download(_key), do: {:error, :unsupported}

  @impl true
  def presigned_upload_url(_key, _content_type, _opts), do: {:error, :unsupported}

  @impl true
  def copy(_source_key, _dest_key), do: {:error, :unsupported}

  @impl true
  def copy_if_absent(_source_key, _dest_key), do: {:error, :unsupported}

  @impl true
  def key_from_url(_url), do: {:error, :invalid_url}
end

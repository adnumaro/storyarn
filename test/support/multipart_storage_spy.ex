defmodule Storyarn.MultipartStorageSpy do
  @moduledoc false

  @behaviour Storyarn.Platform.ObjectStorage

  def upload(_key, _data, _content_type), do: {:error, :not_implemented}
  def upload_stream(_key, _chunks, _content_type), do: {:error, :not_implemented}

  def abort_incomplete_multipart_uploads(key, opts) do
    send(self(), {:multipart_abort_dispatched, key, opts})
    {:ok, 17}
  end

  def incomplete_multipart_upload_count(key, opts) do
    send(self(), {:multipart_inventory_dispatched, key, opts})
    {:ok, 23}
  end

  def incomplete_multipart_upload_summary(prefix, opts) do
    send(self(), {:multipart_summary_dispatched, prefix, opts})

    Process.get(
      {__MODULE__, :multipart_summary_result},
      {:ok,
       %{
         count: 29,
         oldest_initiated_at: ~U[2026-09-01 12:00:00Z],
         inventory_complete: true
       }}
    )
  end

  def put_if_absent(_key, _data, _content_type), do: {:error, :not_implemented}
  def delete(_key), do: {:error, :not_implemented}
  def delete_if_matches(_key, _identity), do: {:error, :not_implemented}
  def namespace_fingerprint, do: {:error, :not_implemented}
  def get_url(_key), do: ""
  def download(_key), do: {:error, :not_implemented}
  def stat(_key), do: {:error, :not_implemented}
  def stream(_key, _offset, _length, _opts), do: {:error, :not_implemented}
  def presigned_upload_url(_key, _content_type, _opts), do: {:error, :not_implemented}
  def presigned_download_url(_key, _content_type, _opts), do: {:error, :not_implemented}
  def copy(_source_key, _destination_key), do: {:error, :not_implemented}
  def copy_if_absent(_source_key, _destination_key), do: {:error, :not_implemented}
  def key_from_url(_url), do: {:error, :invalid_url}
  def list_prefix(_prefix, _opts), do: {:error, :not_implemented}
  def list_prefix_metadata(_prefix, _opts), do: {:error, :not_implemented}
end

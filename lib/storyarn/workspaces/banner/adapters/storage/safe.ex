defmodule Storyarn.Workspaces.Banner.Adapters.Storage.Safe do
  @moduledoc false

  alias Storyarn.Workspaces.Banner.Adapters.Storage.Port

  @spec upload(String.t(), binary(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def upload(key, binary, content_type, opts) do
    Port.upload(key, binary, content_type, opts)
  rescue
    error -> {:error, {:storage_exception, error}}
  end

  @spec delete(String.t(), keyword()) :: :ok | {:error, term()}
  def delete(key, opts) do
    case Port.delete(key, opts) do
      :ok -> :ok
      {:error, _reason} = error -> error
      result -> {:error, {:unexpected_storage_delete_result, result}}
    end
  rescue
    error -> {:error, {:storage_exception, error}}
  end

  @spec key_from_url(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def key_from_url(url, opts) do
    case Port.key_from_url(url, opts) do
      {:ok, key} when is_binary(key) -> {:ok, key}
      {:error, _reason} = error -> error
      result -> {:error, {:unexpected_key_from_url_result, result}}
    end
  rescue
    error -> {:error, {:storage_exception, error}}
  end
end

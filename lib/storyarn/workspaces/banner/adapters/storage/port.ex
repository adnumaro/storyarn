defmodule Storyarn.Workspaces.Banner.Adapters.Storage.Port do
  @moduledoc """
  Technical storage port used by the Workspace banner capability.

  The configured adapter stores, deletes, and resolves opaque objects. It does
  not authorize users or decide which keys belong to a Workspace.
  """

  @type key :: String.t()
  @type url :: String.t()

  @callback upload(key(), binary(), String.t()) :: {:ok, url()} | {:error, term()}
  @callback delete(key()) :: :ok | {:error, term()}
  @callback key_from_url(url()) :: {:ok, key()} | {:error, term()}

  @spec upload(key(), binary(), String.t(), keyword()) :: {:ok, url()} | {:error, term()}
  def upload(key, binary, content_type, opts \\ []) do
    adapter(opts).upload(key, binary, content_type)
  end

  @spec delete(key(), keyword()) :: :ok | {:error, term()}
  def delete(key, opts \\ []) do
    adapter(opts).delete(key)
  end

  @spec key_from_url(url(), keyword()) :: {:ok, key()} | {:error, term()}
  def key_from_url(url, opts \\ []) do
    adapter(opts).key_from_url(url)
  end

  defp adapter(opts) do
    Keyword.get_lazy(opts, :storage, fn ->
      :storyarn
      |> Application.fetch_env!(__MODULE__)
      |> Keyword.fetch!(:adapter)
    end)
  end
end

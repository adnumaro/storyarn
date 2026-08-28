defmodule Storyarn.Workspaces.Banner.Rules.StorageKey do
  @moduledoc false

  @spec new(String.t(), String.t()) :: String.t()
  def new(workspace_slug, filename) do
    "workspaces/#{workspace_slug}/banner/#{Ecto.UUID.generate()}#{Path.extname(filename)}"
  end

  @spec owned?(String.t(), String.t()) :: boolean()
  def owned?(workspace_slug, key) when is_binary(workspace_slug) and is_binary(key) do
    prefix = "workspaces/#{workspace_slug}/banner/"

    with true <- String.valid?(key),
         true <- String.starts_with?(key, prefix),
         filename = String.replace_prefix(key, prefix, ""),
         true <- filename not in ["", ".", ".."],
         false <- String.contains?(filename, [<<0>>, "/", "\\"]) do
      true
    else
      _ -> false
    end
  end

  def owned?(_workspace_slug, _key), do: false

  @spec workspace_slug(String.t()) :: {:ok, String.t()} | {:error, :invalid_banner_key}
  def workspace_slug(key) when is_binary(key) do
    case String.split(key, "/", parts: 4) do
      ["workspaces", workspace_slug, "banner", filename]
      when workspace_slug != "" and filename != "" ->
        if owned?(workspace_slug, key),
          do: {:ok, workspace_slug},
          else: {:error, :invalid_banner_key}

      _invalid ->
        {:error, :invalid_banner_key}
    end
  end

  def workspace_slug(_key), do: {:error, :invalid_banner_key}
end

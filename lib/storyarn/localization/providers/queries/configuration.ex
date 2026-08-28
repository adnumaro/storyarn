defmodule Storyarn.Localization.Providers.Queries.Configuration do
  @moduledoc false

  alias Storyarn.Localization.ProviderConfig
  alias Storyarn.Repo

  @spec get(pos_integer(), String.t()) :: ProviderConfig.t() | nil
  def get(project_id, provider \\ "deepl") do
    Repo.get_by(ProviderConfig, project_id: project_id, provider: provider)
  end

  @spec fetch_active(pos_integer(), String.t()) ::
          {:ok, ProviderConfig.t()}
          | {:error, :no_provider_configured | :provider_disabled | :no_api_key}
  def fetch_active(project_id, provider \\ "deepl") do
    case get(project_id, provider) do
      nil -> {:error, :no_provider_configured}
      %{is_active: false} -> {:error, :provider_disabled}
      %{api_key_encrypted: nil} -> {:error, :no_api_key}
      config -> {:ok, config}
    end
  end

  @spec active?(pos_integer(), String.t()) :: boolean()
  def active?(project_id, provider \\ "deepl") do
    case get(project_id, provider) do
      %{is_active: true, api_key_encrypted: key} when not is_nil(key) -> true
      _config -> false
    end
  end
end

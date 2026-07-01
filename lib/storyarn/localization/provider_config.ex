defmodule Storyarn.Localization.ProviderConfig do
  @moduledoc """
  Schema for translation provider configurations.

  Stores per-project API credentials and settings for translation providers.
  The API key is encrypted at rest using Cloak.

  Fields:
  - `provider` - Provider identifier (e.g., "deepl")
  - `api_key_encrypted` - Encrypted API key
  - `api_endpoint` - API base URL (differs for DeepL free vs pro tiers)
  - `settings` - Provider-specific settings (JSON map)
  - `is_active` - Whether this provider is enabled
  - `deepl_glossary_ids` - Map of language pairs to DeepL glossary IDs
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Projects.Project

  @default_api_endpoint "https://api-free.deepl.com"
  @supported_api_endpoints [@default_api_endpoint, "https://api.deepl.com"]
  @api_endpoint_error "must be a supported DeepL API endpoint"

  @type t :: %__MODULE__{
          id: integer() | nil,
          project_id: integer() | nil,
          project: Project.t() | Ecto.Association.NotLoaded.t() | nil,
          provider: String.t(),
          api_key_encrypted: binary() | nil,
          api_endpoint: String.t() | nil,
          settings: map(),
          is_active: boolean(),
          deepl_glossary_ids: map(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "translation_provider_configs" do
    field :provider, :string, default: "deepl"
    field :api_key_encrypted, Storyarn.Shared.EncryptedBinary
    field :api_endpoint, :string
    field :settings, :map, default: %{}
    field :is_active, :boolean, default: true
    field :deepl_glossary_ids, :map, default: %{}

    belongs_to :project, Project

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a provider config.
  """
  def changeset(config, attrs) do
    config
    |> cast(attrs, [
      :provider,
      :api_key_encrypted,
      :api_endpoint,
      :settings,
      :is_active,
      :deepl_glossary_ids
    ])
    |> validate_required([:provider])
    |> validate_inclusion(:provider, ["deepl"])
    |> update_change(:api_endpoint, &normalize_api_endpoint/1)
    |> validate_api_endpoint()
    |> unique_constraint([:project_id, :provider])
    |> foreign_key_constraint(:project_id)
  end

  @doc "Returns the default DeepL API endpoint."
  @spec default_api_endpoint() :: String.t()
  def default_api_endpoint, do: @default_api_endpoint

  @doc "Returns the supported DeepL API endpoints."
  @spec supported_api_endpoints() :: [String.t()]
  def supported_api_endpoints, do: @supported_api_endpoints

  @doc """
  Resolves a stored endpoint to a supported DeepL API endpoint.

  Unsafe stored values return `{:error, :unsupported_api_endpoint}` so callers
  do not send API credentials to arbitrary hosts.
  """
  @spec api_endpoint_or_default(t() | String.t() | nil) ::
          {:ok, String.t()} | {:error, :unsupported_api_endpoint}
  def api_endpoint_or_default(%__MODULE__{api_endpoint: endpoint}) do
    api_endpoint_or_default(endpoint)
  end

  def api_endpoint_or_default(nil), do: {:ok, @default_api_endpoint}

  def api_endpoint_or_default(endpoint) when is_binary(endpoint) do
    endpoint = normalize_api_endpoint(endpoint)

    cond do
      is_nil(endpoint) -> {:ok, @default_api_endpoint}
      endpoint in @supported_api_endpoints -> {:ok, endpoint}
      true -> {:error, :unsupported_api_endpoint}
    end
  end

  def api_endpoint_or_default(_endpoint), do: {:error, :unsupported_api_endpoint}

  defp validate_api_endpoint(changeset) do
    case api_endpoint_or_default(get_field(changeset, :api_endpoint)) do
      {:ok, _endpoint} -> changeset
      {:error, :unsupported_api_endpoint} -> add_error(changeset, :api_endpoint, @api_endpoint_error)
    end
  end

  defp normalize_api_endpoint(endpoint) when is_binary(endpoint) do
    case endpoint |> String.trim() |> String.trim_trailing("/") do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_api_endpoint(endpoint), do: endpoint
end

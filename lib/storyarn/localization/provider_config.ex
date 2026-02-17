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
    |> unique_constraint([:project_id, :provider])
    |> foreign_key_constraint(:project_id)
  end
end

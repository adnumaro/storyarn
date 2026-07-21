defmodule Storyarn.Repo.Migrations.CreateAiIntegrations do
  use Ecto.Migration

  def change do
    create table(:ai_integrations) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :api_key_encrypted, :binary, null: false
      add :key_last_four, :string, null: false
      add :account_email, :string
      add :account_display_name, :string
      add :connected_at, :utc_datetime, null: false
      add :last_validated_at, :utc_datetime
      add :last_used_at, :utc_datetime
      add :revoked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:ai_integrations, [:user_id])

    # Only one active integration per (user, provider). Revoked rows are kept
    # for audit history and do not block a new connection to the same provider.
    create unique_index(
             :ai_integrations,
             [:user_id, :provider],
             where: "revoked_at IS NULL",
             name: :ai_integrations_user_provider_active_index
           )
  end
end

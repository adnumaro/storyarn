defmodule Storyarn.Repo.Migrations.CreateUserIdentities do
  use Ecto.Migration

  def change do
    create table(:user_identities) do
      add :provider, :string, null: false
      add :provider_id, :string, null: false
      add :provider_email, :string
      add :provider_name, :string
      add :provider_avatar, :string
      add :provider_token, :text
      add :provider_refresh_token, :text
      add :provider_meta, :map, default: %{}
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:user_identities, [:user_id])
    create unique_index(:user_identities, [:provider, :provider_id])
    create unique_index(:user_identities, [:user_id, :provider])
  end
end

defmodule Storyarn.Repo.Migrations.CreateAiIntegrationAudits do
  use Ecto.Migration

  def change do
    create table(:ai_integration_audits) do
      # We keep the row when the user is deleted so security investigations
      # can still reconstruct history. The FK is nilified instead of cascaded.
      add :user_id, references(:users, on_delete: :nilify_all)
      add :provider, :string, null: false
      add :action, :string, null: false
      add :metadata, :map, default: %{}, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:ai_integration_audits, [:user_id, :inserted_at])
    create index(:ai_integration_audits, [:provider, :inserted_at])
  end
end

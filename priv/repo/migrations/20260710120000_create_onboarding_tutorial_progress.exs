defmodule Storyarn.Repo.Migrations.CreateOnboardingTutorialProgress do
  use Ecto.Migration

  def change do
    create table(:onboarding_tutorial_progress) do
      add :tutorial, :string, null: false
      add :guide_version, :integer, null: false, default: 1
      add :completed_at, :utc_datetime
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:onboarding_tutorial_progress, [:user_id, :tutorial],
             name: :onboarding_tutorial_progress_user_id_tutorial_index
           )
  end
end

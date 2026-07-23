defmodule Storyarn.Repo.Migrations.AddPersonalByokLane do
  use Ecto.Migration

  def up do
    drop constraint(:ai_route_options, :ai_route_options_price_units_positive)

    alter table(:ai_route_options) do
      modify :price_units, :bigint, null: true
    end

    create constraint(:ai_route_options, :ai_route_options_lane_price,
             check:
               "(lane = 'managed' AND price_id IS NOT NULL AND price_version IS NOT NULL AND price_units IS NOT NULL AND price_units > 0) OR " <>
                 "(lane <> 'managed' AND price_id IS NULL AND price_version IS NULL AND price_units IS NULL)"
           )

    create table(:ai_personal_consents) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :integration_id, references(:ai_integrations, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :capability, :string, null: false
      add :cost_class, :string, null: false
      add :policy_text_version, :string, null: false
      add :granted_at, :utc_datetime, null: false
      add :revoked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:ai_personal_consents, [:user_id, :workspace_id])
    create index(:ai_personal_consents, [:integration_id])

    create unique_index(
             :ai_personal_consents,
             [
               :user_id,
               :workspace_id,
               :integration_id,
               :capability,
               :cost_class,
               :policy_text_version
             ],
             where: "revoked_at IS NULL",
             name: :ai_personal_consents_active_scope_index
           )

    create constraint(:ai_personal_consents, :ai_personal_consents_capability,
             check: "capability IN ('translation', 'suggestions', 'tasks', 'images')"
           )
  end

  def down do
    drop table(:ai_personal_consents)
    drop constraint(:ai_route_options, :ai_route_options_lane_price)

    execute """
    UPDATE ai_route_options
    SET price_units = 1
    WHERE price_units IS NULL
    """

    alter table(:ai_route_options) do
      modify :price_units, :bigint, null: false
    end

    create constraint(:ai_route_options, :ai_route_options_price_units_positive,
             check: "price_units > 0"
           )
  end
end

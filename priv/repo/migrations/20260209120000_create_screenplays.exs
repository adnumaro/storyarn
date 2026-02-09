defmodule Storyarn.Repo.Migrations.CreateScreenplays do
  use Ecto.Migration

  def change do
    create table(:screenplays) do
      add :name, :string, null: false
      add :shortcut, :string
      add :description, :string
      add :position, :integer, default: 0
      add :deleted_at, :utc_datetime

      # Relationships
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :parent_id, references(:screenplays, on_delete: :nilify_all)
      add :linked_flow_id, references(:flows, on_delete: :nilify_all)

      # Draft support (see FUTURE_FEATURES.md — Copy-Based Drafts)
      # null = original, non-null = this is a draft of the referenced screenplay
      add :draft_of_id, references(:screenplays, on_delete: :delete_all)
      add :draft_label, :string
      add :draft_status, :string, default: "active"

      timestamps(type: :utc_datetime)
    end

    create index(:screenplays, [:project_id])
    create index(:screenplays, [:parent_id])
    create index(:screenplays, [:project_id, :parent_id, :position])
    create index(:screenplays, [:deleted_at])
    create index(:screenplays, [:linked_flow_id])
    create index(:screenplays, [:draft_of_id])

    create unique_index(:screenplays, [:project_id, :shortcut],
             where: "shortcut IS NOT NULL AND deleted_at IS NULL",
             name: :screenplays_project_shortcut_unique
           )

    # Prevent multiple screenplays from linking to the same flow (Edge Case A)
    create unique_index(:screenplays, [:linked_flow_id],
             where: "linked_flow_id IS NOT NULL AND deleted_at IS NULL",
             name: :screenplays_linked_flow_unique
           )

    # -------------------------------------------------------

    create table(:screenplay_elements) do
      add :type, :string, null: false
      add :position, :integer, default: 0, null: false
      add :content, :text, default: ""
      add :data, :map, default: %{}
      add :depth, :integer, default: 0
      add :branch, :string

      # NOTE: No group_id column — dialogue groups computed from adjacency (Edge Case F)

      add :screenplay_id, references(:screenplays, on_delete: :delete_all), null: false
      add :linked_node_id, references(:flow_nodes, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:screenplay_elements, [:screenplay_id])
    create index(:screenplay_elements, [:screenplay_id, :position])
    create index(:screenplay_elements, [:linked_node_id])
  end
end

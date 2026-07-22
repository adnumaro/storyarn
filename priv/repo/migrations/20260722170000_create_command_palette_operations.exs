defmodule Storyarn.Repo.Migrations.CreateCommandPaletteOperations do
  use Ecto.Migration

  def change do
    create table(:command_palette_operations) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :event, :string, null: false
      add :operation_id, :string, null: false
      add :result, :map, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create constraint(:command_palette_operations, :command_palette_operations_event_check,
             check: "event IN ('palette_create', 'palette_delete')"
           )

    create constraint(
             :command_palette_operations,
             :command_palette_operations_id_length_check,
             check: "char_length(operation_id) BETWEEN 1 AND 64"
           )

    create constraint(
             :command_palette_operations,
             :command_palette_operations_result_object_check,
             check: "jsonb_typeof(result) = 'object'"
           )

    create unique_index(
             :command_palette_operations,
             [:user_id, :event, :operation_id],
             name: :command_palette_operations_actor_event_id_unique
           )

    create index(:command_palette_operations, [:user_id, :inserted_at],
             name: :command_palette_operations_actor_recency_idx
           )
  end
end

defmodule Storyarn.Repo.Migrations.AddAiContextProvenance do
  use Ecto.Migration

  def change do
    alter table(:ai_route_options) do
      add :context_hash, :string
      add :context_manifest, :map
      add :context_subject, :map
    end

    alter table(:ai_operations) do
      add :context_hash, :string
      add :context_manifest, :map
      add :context_subject, :map
    end

    alter table(:ai_results) do
      add :context_hash, :string
      add :context_manifest, :map
    end

    create constraint(:ai_route_options, :ai_route_options_context_complete,
             check:
               "(context_hash IS NULL AND context_manifest IS NULL AND context_subject IS NULL) OR " <>
                 "(context_hash IS NOT NULL AND context_manifest IS NOT NULL)"
           )

    create constraint(:ai_operations, :ai_operations_context_complete,
             check:
               "(context_hash IS NULL AND context_manifest IS NULL AND context_subject IS NULL) OR " <>
                 "(context_hash IS NOT NULL AND context_manifest IS NOT NULL)"
           )

    create constraint(:ai_results, :ai_results_context_complete,
             check:
               "(context_hash IS NULL AND context_manifest IS NULL) OR " <>
                 "(context_hash IS NOT NULL AND context_manifest IS NOT NULL)"
           )
  end
end

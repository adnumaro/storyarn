defmodule Storyarn.Repo.Migrations.DropNonpersistableContextScope do
  use Ecto.Migration

  # `structural_finding` was the only context scope whose subject could not be
  # persisted (its id was a string, so it never fit `subject_id`). Slice 7.1a.0
  # removed the scope, so the DB must stop accepting a context row with a null
  # subject — otherwise the CHECK constraint permits a shape the application can
  # no longer produce, and the schema and `PersistenceContract` disagree about
  # what is valid.
  #
  # Only `ai_route_options` and `ai_operations` carried the scope branch;
  # `ai_results_context_complete` never did.

  @tables [
    {:ai_route_options, :ai_route_options_context_complete},
    {:ai_operations, :ai_operations_context_complete}
  ]

  @persistable "(context_hash IS NOT NULL AND context_manifest IS NOT NULL AND " <>
                 "COALESCE(context_manifest->>'scope', '') IN ('dialogue', 'flow_neighborhood', 'sheet') AND " <>
                 "context_subject IS NOT NULL)"

  @with_nonpersistable "(context_hash IS NOT NULL AND context_manifest IS NOT NULL AND (" <>
                         "(COALESCE(context_manifest->>'scope', '') = 'structural_finding' AND context_subject IS NULL) OR " <>
                         "(COALESCE(context_manifest->>'scope', '') IN ('dialogue', 'flow_neighborhood', 'sheet') AND context_subject IS NOT NULL)" <>
                         "))"

  @empty "(context_hash IS NULL AND context_manifest IS NULL AND context_subject IS NULL)"

  def up do
    for {table, name} <- @tables do
      drop constraint(table, name)
      create constraint(table, name, check: "#{@empty} OR #{@persistable}")
    end
  end

  def down do
    for {table, name} <- @tables do
      drop constraint(table, name)
      create constraint(table, name, check: "#{@empty} OR #{@with_nonpersistable}")
    end
  end
end

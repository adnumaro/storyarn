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

  # Any row written while the scope existed fails the narrower constraint, and
  # PostgreSQL validates every existing row on ADD CONSTRAINT — so on a database
  # that ran the explanation even once, this migration aborts and the deploy with
  # it. Verified against a real row before writing this guard.
  #
  # Neutralized rather than deleted: `ai_operations` is referenced `on_delete:
  # :restrict` from four allowance and settlement columns, so a paid operation
  # cannot be deleted and must not be — the spend record outlives the feature.
  # Nulling the three context columns puts the row in the all-null branch the
  # constraint already permits, dropping only the provenance of a task that no
  # longer exists and that nothing can read: it is unregistered, so
  # `Context.operation_current?/3` can never rebuild its package.
  #
  # NOT VALID was the alternative and is wrong here: it would leave rows the
  # application can neither produce nor interpret, which is the exact
  # schema-vs-`PersistenceContract` disagreement this migration exists to end.
  # These tables are small, so there is no lock-duration argument for it either.
  def up do
    for {table, name} <- @tables do
      execute("""
      UPDATE #{table}
      SET context_hash = NULL, context_manifest = NULL, context_subject = NULL
      WHERE COALESCE(context_manifest->>'scope', '') = 'structural_finding'
      """)

      drop constraint(table, name)
      create constraint(table, name, check: "#{@empty} OR #{@persistable}")
    end
  end

  # Restores the permissive constraint, NOT the data: `up` discards the context
  # of the affected rows and nothing here can bring it back. Acceptable because
  # the scope has no producer to roll back to — rolling this migration back
  # re-opens the shape, it does not resurrect the feature.
  def down do
    for {table, name} <- @tables do
      drop constraint(table, name)
      create constraint(table, name, check: "#{@empty} OR #{@with_nonpersistable}")
    end
  end
end

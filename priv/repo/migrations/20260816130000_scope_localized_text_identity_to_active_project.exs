defmodule Storyarn.Repo.Migrations.ScopeLocalizedTextIdentityToActiveProject do
  @moduledoc """
  Scopes active localized-text identity to its owning project.

  Exact snapshot restore archives the displaced localization rows before it
  materializes the captured rows. Archived history must therefore be able to
  coexist with the new active row without either row changing ownership.

  This is a quiesced cutover: all application writers from the previous
  release must be stopped before `up/0` runs. They use the retired global
  `ON CONFLICT` target and cannot write after this migration commits.
  """

  use Ecto.Migration

  @index_name :localized_texts_source_locale_unique

  def up do
    lock_identity_contract()

    execute("DROP INDEX #{@index_name}")

    execute("""
    CREATE UNIQUE INDEX #{@index_name}
    ON localized_texts (project_id, source_type, source_id, source_field, locale_code)
    WHERE archived_at IS NULL
    """)
  end

  def down do
    lock_identity_contract()
    assert_historical_contract_representable!()

    execute("DROP INDEX #{@index_name}")

    execute("""
    CREATE UNIQUE INDEX #{@index_name}
    ON localized_texts (source_type, source_id, source_field, locale_code)
    """)
  end

  defp lock_identity_contract do
    repo().query!("LOCK TABLE localized_texts IN ACCESS EXCLUSIVE MODE")
  end

  defp assert_historical_contract_representable! do
    case repo().query!("""
         SELECT EXISTS (
           SELECT 1
           FROM localized_texts
           GROUP BY source_type, source_id, source_field, locale_code
           HAVING count(*) > 1
         )
         """).rows do
      [[false]] ->
        :ok

      [[true]] ->
        raise Ecto.MigrationError,
              "ScopeLocalizedTextIdentityToActiveProject cannot be rolled back after project or archived identities coexist"
    end
  end
end

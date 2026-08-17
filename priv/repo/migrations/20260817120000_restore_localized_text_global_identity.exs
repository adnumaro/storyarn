defmodule Storyarn.Repo.Migrations.RestoreLocalizedTextGlobalIdentity do
  @moduledoc """
  Restores the single global localized-text identity used by the current runtime.

  Run this migration with application writers stopped. It refuses to change the
  index if rows created under the temporary project-scoped contract cannot be
  represented by the global identity.
  """

  use Ecto.Migration

  @index_name :localized_texts_source_locale_unique

  def up do
    repo().query!("LOCK TABLE localized_texts IN ACCESS EXCLUSIVE MODE")
    assert_global_identity_representable!()

    execute("DROP INDEX #{@index_name}")

    execute("""
    CREATE UNIQUE INDEX #{@index_name}
    ON localized_texts (source_type, source_id, source_field, locale_code)
    """)
  end

  def down do
    raise Ecto.MigrationError,
          "RestoreLocalizedTextGlobalIdentity is irreversible after the global identity is restored"
  end

  defp assert_global_identity_representable! do
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
              "localized text identities created by the temporary project-scoped contract must be cleaned before this migration"
    end
  end
end

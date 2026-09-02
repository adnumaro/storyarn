defmodule Storyarn.Repo.Migrations.MakeImportFormatConstraintsRegistryNeutral do
  use Ecto.Migration

  @format_check "format ~ '^[a-z][a-z0-9_]{0,29}$'"

  def up do
    replace_format_constraint(
      :project_import_attempts,
      :project_import_attempts_format_check,
      @format_check
    )

    replace_format_constraint(
      :import_plan_cleanup_requests,
      :import_plan_cleanup_requests_format_check,
      @format_check
    )
  end

  def down do
    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM project_import_attempts WHERE format NOT IN ('yarn', 'storyarn')
        UNION ALL
        SELECT 1 FROM import_plan_cleanup_requests WHERE format NOT IN ('yarn', 'storyarn')
      ) THEN
        RAISE EXCEPTION
          'cannot restore the historical import format constraint while newer format rows exist';
      END IF;
    END
    $$
    """)

    replace_format_constraint(
      :project_import_attempts,
      :project_import_attempts_format_check,
      "format IN ('yarn', 'storyarn')"
    )

    replace_format_constraint(
      :import_plan_cleanup_requests,
      :import_plan_cleanup_requests_format_check,
      "format IN ('yarn', 'storyarn')"
    )
  end

  defp replace_format_constraint(table, name, check) do
    drop constraint(table, name)
    create constraint(table, name, check: check)
  end
end

defmodule Storyarn.Repo.Migrations.AllowCancelledIdeationRounds do
  use Ecto.Migration

  def change do
    execute(
      """
      ALTER TABLE ideation_rounds
        DROP CONSTRAINT ideation_rounds_lifecycle_valid,
        ADD CONSTRAINT ideation_rounds_lifecycle_valid CHECK (
          (status IN ('planned', 'cancelled') AND started_at IS NULL AND closed_at IS NULL) OR
          (status = 'active' AND started_at IS NOT NULL AND closed_at IS NULL) OR
          (status = 'closed' AND started_at IS NOT NULL AND closed_at IS NOT NULL AND closed_at >= started_at)
        )
      """,
      """
      ALTER TABLE ideation_rounds
        DROP CONSTRAINT ideation_rounds_lifecycle_valid,
        ADD CONSTRAINT ideation_rounds_lifecycle_valid CHECK (
          (status = 'planned' AND started_at IS NULL AND closed_at IS NULL) OR
          (status = 'active' AND started_at IS NOT NULL AND closed_at IS NULL) OR
          (status = 'closed' AND started_at IS NOT NULL AND closed_at IS NOT NULL AND closed_at >= started_at)
        )
      """
    )
  end
end

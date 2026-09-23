defmodule Storyarn.Repo.Migrations.IndexDecisionRevisionTargets do
  use Ecto.Migration

  # Content finds the decisions that name it in Affects by containment on the
  # pinned target list.
  def change do
    create index(:ideation_decision_revisions, ["targets jsonb_path_ops"],
             using: :gin,
             name: :ideation_decision_revisions_targets_index
           )
  end
end

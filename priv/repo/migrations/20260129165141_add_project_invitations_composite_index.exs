defmodule Storyarn.Repo.Migrations.AddProjectInvitationsCompositeIndex do
  use Ecto.Migration

  def change do
    create_if_not_exists index(:project_invitations, [:project_id, :email])
  end
end

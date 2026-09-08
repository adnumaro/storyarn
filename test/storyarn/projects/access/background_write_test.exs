defmodule Storyarn.Projects.BackgroundWriteTest do
  use Storyarn.DataCase, async: true

  import Ecto.Changeset
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects

  test "background bookkeeping lock requires a transaction and does not grant access" do
    project = project_fixture(user_fixture())
    stranger = user_scope_fixture()
    assert {:error, :background_write_transaction_required} = Projects.lock_background_write(project.id)

    assert {:ok, :locked} =
             Repo.transact(fn ->
               assert :ok = Projects.lock_background_write(project.id)
               assert {:error, :not_found} = Projects.authorize_locked(stranger, project.id, :edit_content)
               {:ok, :locked}
             end)

    for id <- [nil, -1, "1", 9_223_372_036_854_775_808] do
      assert {:error, :not_found} = Projects.lock_background_write(id)
    end
  end

  test "soft-deleted projects remain inside the consistency boundary" do
    owner = user_scope_fixture()
    project = project_fixture(owner.user)
    project |> change(deleted_at: TimeHelpers.now()) |> Repo.update!()

    assert {:ok, :locked} =
             Repo.transact(fn ->
               assert :ok = Projects.lock_background_write(project.id)
               assert {:error, :not_found} = Projects.authorize_locked(owner, project.id, :edit_content)
               {:ok, :locked}
             end)
  end
end

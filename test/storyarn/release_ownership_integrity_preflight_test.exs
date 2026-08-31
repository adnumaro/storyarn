defmodule Storyarn.ReleaseOwnershipIntegrityPreflightTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Platform.Release
  alias Storyarn.Repo
  alias Storyarn.Workspaces.WorkspaceMembership

  test "the candidate release audits ownership after its migrations and before succeeding" do
    owner = Storyarn.AccountsFixtures.user_fixture()
    workspace = Storyarn.WorkspacesFixtures.workspace_fixture(owner)

    assert_raise RuntimeError, ~r/Ownership integrity preflight failed/, fn ->
      Release.run_migrations_with_ownership_preflight(Repo, fn ->
        {1, _rows} =
          WorkspaceMembership
          |> where(
            [membership],
            membership.workspace_id == ^workspace.id and membership.role == "owner"
          )
          |> Repo.update_all(set: [role: "member"])

        :migrated
      end)
    end
  end

  test "Storyarn.Repo runs the preflight inside the candidate release with_repo callback" do
    source =
      "../../lib/storyarn/release.ex"
      |> Path.expand(__DIR__)
      |> File.read!()

    assert source =~ "Ecto.Migrator.with_repo(repo, &migrate_storyarn_repo/1)"
    assert source =~ ~r/defp migrate_storyarn_repo\(repo\).*run_migrations_with_ownership_preflight\(repo/s
  end
end

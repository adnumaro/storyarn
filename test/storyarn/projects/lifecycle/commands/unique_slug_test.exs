defmodule Storyarn.Projects.Lifecycle.Commands.UniqueSlugTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Projects.Lifecycle.Commands.UniqueSlug
  alias Storyarn.Workspaces.Workspace

  describe "generate/4" do
    test "generates slug from name when no collision" do
      assert UniqueSlug.generate(Workspace, [], "My Workspace") == "my-workspace"
    end

    test "generates slug with suffix on collision" do
      import Storyarn.WorkspacesFixtures

      user = Storyarn.AccountsFixtures.user_fixture()
      _workspace = workspace_fixture(user, %{name: "Test Workspace"})

      slug = UniqueSlug.generate(Workspace, [], "Test Workspace")

      assert String.starts_with?(slug, "test-workspace")
      assert slug != "test-workspace"
    end

    test "generates slug with scope filtering" do
      import Storyarn.WorkspacesFixtures

      user = Storyarn.AccountsFixtures.user_fixture()
      workspace = workspace_fixture(user, %{name: "Scoped Workspace"})

      assert UniqueSlug.generate(Workspace, [], "Unique Name") == "unique-name"
      assert workspace.slug == "scoped-workspace"
    end
  end
end

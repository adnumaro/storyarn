defmodule Storyarn.ProjectsFixturesTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  describe "unique_project_name/0" do
    test "generates unique names" do
      name1 = unique_project_name()
      name2 = unique_project_name()
      assert name1 != name2
      assert String.starts_with?(name1, "Project ")
    end
  end

  describe "valid_project_attributes/1" do
    test "returns default attrs" do
      attrs = valid_project_attributes()
      assert is_binary(attrs.name)
      assert attrs.description == "A test project description"
    end

    test "merges custom attrs" do
      attrs = valid_project_attributes(%{name: "Custom", description: "Custom desc"})
      assert attrs.name == "Custom"
      assert attrs.description == "Custom desc"
    end
  end

  describe "project_fixture/2" do
    test "creates a project with default user" do
      project = project_fixture()
      assert project.id
      assert project.name
      assert project.workspace_id
    end

    test "creates a project for given user" do
      user = user_fixture()
      project = project_fixture(user)
      assert project.id

      # User should be owner
      membership =
        Repo.get_by(Storyarn.Projects.ProjectMembership, project_id: project.id, user_id: user.id)

      assert membership
      assert membership.role == "owner"
    end

    test "uses provided workspace" do
      user = user_fixture()
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})
      assert project.workspace_id == workspace.id
    end

    test "creates workspace when not provided" do
      user = user_fixture()
      project = project_fixture(user)
      assert project.workspace_id != nil
    end

    test "accepts custom name" do
      project = project_fixture(nil, %{name: "Custom Project"})
      assert project.name == "Custom Project"
    end
  end

  describe "membership_fixture/3" do
    test "creates editor membership by default" do
      user = user_fixture()
      project = project_fixture()
      membership = membership_fixture(project, user)
      assert membership.role == "editor"
      assert membership.project_id == project.id
      assert membership.user_id == user.id
    end

    test "creates membership with custom role" do
      user = user_fixture()
      project = project_fixture()
      membership = membership_fixture(project, user, "viewer")
      assert membership.role == "viewer"
    end
  end

  describe "invitation_fixture/4" do
    test "creates invitation with default email" do
      user = user_fixture()
      project = project_fixture(user)
      invitation = invitation_fixture(project, user)
      assert invitation.id
      assert invitation.email
      assert invitation.role == "editor"
    end

    test "creates invitation with custom email and role" do
      user = user_fixture()
      project = project_fixture(user)
      invitation = invitation_fixture(project, user, "test@example.com", "viewer")
      assert invitation.email == "test@example.com"
      assert invitation.role == "viewer"
    end
  end

  describe "create_invitation_with_token/4" do
    test "returns encoded token and invitation" do
      user = user_fixture()
      project = project_fixture(user)
      {token, invitation} = create_invitation_with_token(project, user, "test@example.com")
      assert is_binary(token)
      assert invitation.id
      assert invitation.email == "test@example.com"
    end

    test "token can be used to look up invitation" do
      user = user_fixture()
      project = project_fixture(user)
      {token, _invitation} = create_invitation_with_token(project, user, "lookup@example.com")

      # Token should be decodable
      assert {:ok, decoded} = Base.url_decode64(token, padding: false)
      assert byte_size(decoded) > 0
    end

    test "creates with default editor role" do
      user = user_fixture()
      project = project_fixture(user)
      {_token, invitation} = create_invitation_with_token(project, user, "role@example.com")
      assert invitation.role == "editor"
    end

    test "creates with custom role" do
      user = user_fixture()
      project = project_fixture(user)

      {_token, invitation} =
        create_invitation_with_token(project, user, "viewer@example.com", "viewer")

      assert invitation.role == "viewer"
    end

    test "invitation token is persisted in database" do
      user = user_fixture()
      project = project_fixture(user)
      {_token, invitation} = create_invitation_with_token(project, user, "hash@example.com")

      # Verify the invitation has a token stored
      assert invitation.token
      assert byte_size(invitation.token) > 0
    end

    test "different invitations produce different tokens" do
      user = user_fixture()
      project = project_fixture(user)
      {token1, _inv1} = create_invitation_with_token(project, user, "first@example.com")
      {token2, _inv2} = create_invitation_with_token(project, user, "second@example.com")

      assert token1 != token2
    end
  end

  describe "extract_invitation_token/1" do
    test "returns error when function returns error" do
      result = extract_invitation_token(fn -> {:error, :some_reason} end)
      assert result == {:error, :some_reason}
    end
  end

  describe "membership roles" do
    test "creates owner membership" do
      user = user_fixture()
      project = project_fixture()
      membership = membership_fixture(project, user, "owner")
      assert membership.role == "owner"
    end

    test "creates viewer membership" do
      user = user_fixture()
      project = project_fixture()
      membership = membership_fixture(project, user, "viewer")
      assert membership.role == "viewer"
    end
  end
end

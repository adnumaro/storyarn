defmodule Storyarn.WorkspacesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Storyarn.Workspaces` context.
  """

  alias Storyarn.AccountsFixtures
  alias Storyarn.Workspaces

  def unique_workspace_name, do: "Workspace #{System.unique_integer([:positive])}"

  def valid_workspace_attributes(attrs \\ %{}) do
    name = attrs[:name] || unique_workspace_name()

    Enum.into(attrs, %{
      name: name,
      slug: Workspaces.generate_slug(name),
      description: "A test workspace description"
    })
  end

  @doc """
  Creates a workspace with the given user as owner.
  """
  def workspace_fixture(user \\ nil, attrs \\ %{}) do
    user = user || AccountsFixtures.user_fixture()
    scope = AccountsFixtures.user_scope_fixture(user)

    {:ok, workspace} =
      attrs
      |> valid_workspace_attributes()
      |> then(&Workspaces.create_workspace(scope, &1))

    workspace
  end

  @doc """
  Creates a workspace membership for the given user and workspace.
  """
  def workspace_membership_fixture(workspace, user, role \\ "member") do
    {:ok, membership} =
      %Storyarn.Workspaces.WorkspaceMembership{}
      |> Storyarn.Workspaces.WorkspaceMembership.changeset(%{
        workspace_id: workspace.id,
        user_id: user.id,
        role: role
      })
      |> Storyarn.Repo.insert()

    membership
  end

  @doc """
  Gets the default workspace created during user registration.
  """
  def get_user_default_workspace(user) do
    Workspaces.get_default_workspace(user)
  end
end

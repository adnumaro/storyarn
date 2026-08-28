defmodule Storyarn.WorkspacesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Storyarn.Workspaces` context.
  """

  alias Storyarn.AccountsFixtures
  alias Storyarn.Repo
  alias Storyarn.Workspaces
  alias Storyarn.Workspaces.Invitations.Tokens.Issuer
  alias Storyarn.Workspaces.WorkspaceMembership

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
  Returns the user's default workspace (created during registration).

  For tests that need a workspace, this reuses the existing default workspace
  rather than creating a new one, which respects the free plan's 1-workspace limit.
  If attrs are provided (e.g., name), the workspace is updated with them.
  """
  def workspace_fixture(user \\ nil, attrs \\ %{}) do
    user = user || AccountsFixtures.user_fixture()
    workspace = Workspaces.get_default_workspace(user)

    if attrs == %{} or attrs == [] do
      workspace
    else
      update_attrs = Map.delete(attrs, :workspace_id)

      # Also update slug if name is provided (update_changeset doesn't cast slug)
      update_attrs =
        if Map.has_key?(update_attrs, :name) and not Map.has_key?(update_attrs, :slug) do
          Map.put(update_attrs, :slug, Workspaces.generate_slug(update_attrs[:name]))
        else
          update_attrs
        end

      # Use direct changeset to also update slug (Workspaces.update_workspace ignores slug)
      workspace
      |> Ecto.Changeset.change(update_attrs)
      |> Repo.update!()
    end
  end

  @doc """
  Creates a workspace membership for the given user and workspace.
  """
  def workspace_membership_fixture(workspace, user, role \\ "member") do
    {:ok, membership} =
      %WorkspaceMembership{}
      |> WorkspaceMembership.changeset(%{
        workspace_id: workspace.id,
        user_id: user.id,
        role: role
      })
      |> Repo.insert()

    membership
  end

  @doc "Creates a persisted workspace invitation and returns its public token."
  def workspace_invitation_fixture(workspace, invited_by, email, role \\ "member") do
    {encoded_token, invitation_struct} = Issuer.issue(workspace, invited_by, email, role)
    invitation = Repo.insert!(invitation_struct)

    {encoded_token, invitation}
  end

  @doc """
  Gets the default workspace created during user registration.
  """
  def get_user_default_workspace(user) do
    Workspaces.get_default_workspace(user)
  end
end

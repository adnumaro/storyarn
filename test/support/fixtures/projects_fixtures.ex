defmodule Storyarn.ProjectsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Storyarn.Projects` context.
  """

  alias Storyarn.AccountsFixtures
  alias Storyarn.Projects
  alias Storyarn.Projects.ProjectInvitation
  alias Storyarn.WorkspacesFixtures

  def unique_project_name, do: "Project #{System.unique_integer([:positive])}"

  def valid_project_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: unique_project_name(),
      description: "A test project description"
    })
  end

  @doc """
  Creates a project with the given user as owner.
  Also creates a workspace for the project if not provided.
  """
  def project_fixture(user \\ nil, attrs \\ %{}) do
    user = user || AccountsFixtures.user_fixture()
    scope = AccountsFixtures.user_scope_fixture(user)

    # Get or create a workspace for the project
    workspace = attrs[:workspace] || WorkspacesFixtures.workspace_fixture(user)

    {:ok, project} =
      attrs
      |> valid_project_attributes()
      |> Map.put(:workspace_id, workspace.id)
      |> then(&Projects.create_project(scope, &1))

    project
  end

  @doc """
  Creates a project membership for the given user and project.
  """
  def membership_fixture(project, user, role \\ "editor") do
    {:ok, membership} =
      %Storyarn.Projects.ProjectMembership{}
      |> Storyarn.Projects.ProjectMembership.changeset(%{
        project_id: project.id,
        user_id: user.id,
        role: role
      })
      |> Storyarn.Repo.insert()

    membership
  end

  @doc """
  Creates a project invitation.
  """
  def invitation_fixture(project, invited_by, email \\ nil, role \\ "editor") do
    email = email || AccountsFixtures.unique_user_email()

    {:ok, invitation} =
      Projects.create_invitation(project, invited_by, email, role)

    invitation
  end

  @doc """
  Creates an invitation and returns the encoded token for testing.

  This bypasses the email delivery and directly creates the invitation,
  returning the token that would be in the email URL.
  """
  def create_invitation_with_token(project, invited_by, email, role \\ "editor") do
    {encoded_token, invitation} =
      ProjectInvitation.build_invitation(project, invited_by, email, role)

    case Storyarn.Repo.insert(invitation) do
      {:ok, invitation} -> {encoded_token, invitation}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Extracts the invitation token from a sent email.

  The function should call the invitation creation and this will
  extract the token from the sent email via Swoosh test adapter.

  ## Example

      token = extract_invitation_token(fn ->
        Projects.create_invitation(project, owner, email, "editor")
      end)
  """
  def extract_invitation_token(fun) do
    # Call the function - it should send an email
    result = fun.()

    case result do
      {:ok, _invitation} ->
        # Wait a bit for the email to be delivered to the test mailbox
        :timer.sleep(10)

        # For Swoosh.Adapters.Test, emails are stored in the process mailbox
        receive do
          {:delivered_email, email} ->
            extract_token_from_email(email)

          {:swoosh, :delivered_email, email} ->
            extract_token_from_email(email)
        after
          100 ->
            # Fall back to checking Swoosh.Adapters.Test's internal state
            # This shouldn't happen in normal test setup
            raise "Could not extract invitation token - no email received"
        end

      error ->
        error
    end
  end

  defp extract_token_from_email(email) do
    [_, token | _] = String.split(email.text_body, "/projects/invitations/")
    token |> String.split("\n") |> hd()
  end
end

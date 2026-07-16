defmodule Storyarn.ProjectsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Storyarn.Projects` context.
  """

  import Ecto.Query

  alias Storyarn.AccountsFixtures
  alias Storyarn.Projects
  alias Storyarn.Projects.ProjectInvitation
  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.Repo
  alias Storyarn.Shared.EncryptedBinary
  alias Storyarn.Workers.DeliverInvitationWorker
  alias Storyarn.WorkspacesFixtures

  def unique_project_name, do: "Project #{System.unique_integer([:positive])}"

  def valid_project_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: unique_project_name(),
      description: "A test project description",
      project_type: "game",
      project_subtype: "rpg"
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
      %ProjectMembership{}
      |> ProjectMembership.changeset(%{
        project_id: project.id,
        user_id: user.id,
        role: role
      })
      |> Repo.insert()

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

    case Repo.insert(invitation) do
      {:ok, invitation} -> {encoded_token, invitation}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Extracts the invitation token from the durable delivery job.

  The function should create an invitation through the context. The token is
  decrypted from the Oban payload without performing external email delivery.

  ## Example

      token = extract_invitation_token(fn ->
        Projects.create_invitation(project, owner, email, "editor")
      end)
  """
  def extract_invitation_token(fun) do
    result = fun.()

    case result do
      {:ok, _invitation} ->
        DeliverInvitationWorker
        |> latest_delivery_job()
        |> decrypt_job_token()

      error ->
        error
    end
  end

  defp latest_delivery_job(worker) do
    Repo.one!(
      from(job in Oban.Job,
        where: job.worker == ^inspect(worker),
        order_by: [desc: job.id],
        limit: 1
      )
    )
  end

  defp decrypt_job_token(job) do
    with {:ok, encrypted_binary} <- Base.decode64(job.args["encrypted_token"]),
         {:ok, token} <- EncryptedBinary.load(encrypted_binary) do
      token
    else
      _ -> raise "Could not decrypt invitation token from delivery job"
    end
  end
end

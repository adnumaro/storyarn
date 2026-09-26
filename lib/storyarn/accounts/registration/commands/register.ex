defmodule Storyarn.Accounts.Registration.Commands.Register do
  @moduledoc false

  alias Storyarn.Accounts.Registration.Events.UserSignedUp
  alias Storyarn.Accounts.Registration.Rules.DefaultWorkspace
  alias Storyarn.Accounts.User
  alias Storyarn.Commercial
  alias Storyarn.Repo
  alias Storyarn.Workspaces

  @doc """
  Registers a user, creates the account's subscription and a default workspace.

  The default workspace is named "{name}'s workspace" (localized).

  Note: This function depends on the Workspaces context. In a future refactor,
  this cross-context operation should move to a Service module.
  """
  def register_user(attrs) do
    register_with_default_workspace(attrs, &insert_user/1)
  end

  @doc """
  Registers a public user with a password and creates a default workspace.

  Public registrations are confirmed immediately because password-based sign
  up is the account verification step currently exposed by the product.
  """
  def register_user_with_password(attrs) do
    result = register_with_default_workspace(attrs, &insert_public_user/1)

    case result do
      {:ok, user} ->
        UserSignedUp.emit(user, "password")
        {:ok, user}

      error ->
        error
    end
  end

  @doc """
  Returns a changeset for public user registration.
  """
  def change_user_registration(%User{} = user, attrs \\ %{}, opts \\ []) do
    User.registration_changeset(user, attrs, opts)
  end

  defp insert_user(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> Repo.insert()
  end

  defp insert_public_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> User.confirm_changeset()
    |> Repo.insert()
  end

  defp register_with_default_workspace(attrs, insert_user) do
    Repo.transact(fn ->
      with {:ok, user} <- insert_user.(attrs),
           :ok <- create_account_subscription(user),
           {:ok, _workspace} <- create_default_workspace(user) do
        {:ok, user}
      else
        {:error, :limit_reached, _details} -> {:error, :workspace_limit_reached}
        {:error, _} = error -> error
      end
    end)
  end

  # The plan belongs to the account, so it exists before any workspace takes its
  # limits from it.
  defp create_account_subscription(user) do
    case subscription_provisioner().(user) do
      {:ok, _receipt} -> :ok
      {:error, _commercial_error} -> {:error, :account_provisioning_failed}
    end
  end

  # The configurable function is a narrow failure-test seam. Production keeps
  # the explicit cross-context dependency on Commercial's public facade.
  defp subscription_provisioner do
    :storyarn
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:subscription_provisioner, &Commercial.create_account_subscription/1)
  end

  defp create_default_workspace(user) do
    name = DefaultWorkspace.name_for(user)
    slug = Workspaces.generate_slug(name)

    Workspaces.create_workspace_with_owner(user, %{
      name: name,
      slug: slug
    })
  end
end

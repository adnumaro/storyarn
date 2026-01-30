defmodule Storyarn.Accounts.Registration do
  @moduledoc false

  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Accounts.User
  alias Storyarn.Repo
  alias Storyarn.Workspaces

  @doc """
  Registers a user and creates a default workspace.

  The default workspace is named "{name}'s workspace" (localized).

  Note: This function depends on the Workspaces context. In a future refactor,
  this cross-context operation should move to a Service module.
  """
  def register_user(attrs) do
    Repo.transact(fn ->
      with {:ok, user} <- insert_user(attrs),
           {:ok, _workspace} <- create_default_workspace(user) do
        {:ok, user}
      end
    end)
  end

  @doc """
  Registers a user without creating a default workspace.

  Used by OAuth flow and services that handle workspace creation separately.
  """
  def register_user_only(attrs) do
    insert_user(attrs)
  end

  defp insert_user(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> Repo.insert()
  end

  defp create_default_workspace(user) do
    name = default_workspace_name(user)
    slug = Workspaces.generate_slug(name)

    Workspaces.create_workspace_with_owner(user, %{
      name: name,
      slug: slug
    })
  end

  defp default_workspace_name(user) do
    display_name = user.display_name || extract_name_from_email(user.email)
    gettext("%{name}'s workspace", name: display_name)
  end

  defp extract_name_from_email(email) do
    email
    |> String.split("@")
    |> List.first()
    |> String.capitalize()
  end
end

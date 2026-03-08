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
      else
        {:error, :limit_reached, _details} -> {:error, :workspace_limit_reached}
        {:error, _} = error -> error
      end
    end)
  end

  @doc """
  Finds an existing user by email, or registers and auto-confirms a new one.

  Used for invitation acceptance where the user must be able to log in immediately.
  Returns `{:ok, user}` or `{:error, changeset}`.
  """
  def find_or_register_confirmed_user(email) do
    case Repo.get_by(User, email: String.downcase(email)) do
      %User{} = user ->
        {:ok, user}

      nil ->
        with {:ok, user} <- register_user(%{"email" => email}) do
          Repo.update(User.confirm_changeset(user))
        end
    end
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
    dgettext("identity", "%{name}'s workspace", name: display_name)
  end

  defp extract_name_from_email(email) do
    email
    |> String.split("@")
    |> List.first()
    |> String.capitalize()
  end
end

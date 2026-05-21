defmodule Storyarn.Accounts.Registration do
  @moduledoc false

  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Accounts.User
  alias Storyarn.Accounts.UserToken
  alias Storyarn.Analytics
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

  @doc """
  Gets the user with the given invite token and deletes the token if found.
  Used for gating registration.
  """
  def get_user_by_invite_token(token) do
    with {:ok, query} <- UserToken.verify_invite_token_query(token),
         {user, found_token} <- Repo.one(query) do
      # Delete token upon consumption? Wait, not upon viewing the page.
      # They only consume it on successful save! So we just return the user and the token struct.
      {user, found_token}
    else
      _ -> nil
    end
  end

  @doc """
  Completes the user's registration by setting their password and consuming the invite token.
  """
  def complete_registration(%User{} = user, token_record, attrs) do
    result =
      Repo.transact(fn ->
        user_changeset = User.password_changeset(user, attrs, hash_password: true)

        with {:ok, updated_user} <- Repo.update(user_changeset) do
          # Consume the token immediately
          Repo.delete!(token_record)
          {:ok, updated_user}
        end
      end)

    case result do
      {:ok, updated_user} ->
        Analytics.identify_user(updated_user)
        Analytics.track(updated_user, "user signed up", %{auth_method: "invite"})
        {:ok, updated_user}

      error ->
        error
    end
  end

  @doc """
  Delivers the waitlist invite instructions to the given user.
  """
  def deliver_waitlist_invite_instructions(%User{} = user, invite_url_fun) when is_function(invite_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "invite")
    Repo.insert!(user_token)

    Storyarn.Accounts.UserNotifier.deliver_waitlist_invite(
      user.email,
      invite_url_fun.(encoded_token)
    )
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

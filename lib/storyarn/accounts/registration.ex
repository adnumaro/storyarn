defmodule Storyarn.Accounts.Registration do
  @moduledoc false

  use Gettext, backend: Storyarn.Gettext

  import Ecto.Query, warn: false

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
  Registers a public user with a password and creates a default workspace.

  Public registrations are confirmed immediately because password-based sign
  up is the account verification step currently exposed by the product.
  """
  def register_user_with_password(attrs) do
    result =
      Repo.transact(fn ->
        with {:ok, user} <- insert_public_user(attrs),
             {:ok, _workspace} <- create_default_workspace(user) do
          {:ok, user}
        else
          {:error, :limit_reached, _details} -> {:error, :workspace_limit_reached}
          {:error, _} = error -> error
        end
      end)

    case result do
      {:ok, user} ->
        Analytics.identify_user(user)
        Analytics.track(user, "user signed up", %{auth_method: "password"})
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
  Finds or creates a user for a workspace/project invitation.

  Users with passwords can accept the invitation immediately. New users, and
  existing passwordless users, must complete password setup before the invitation
  is accepted.
  """
  def prepare_invitation_user(email) do
    email = String.downcase(email)

    case Repo.get_by(User, email: email) do
      %User{hashed_password: hashed_password} = user when is_binary(hashed_password) ->
        {:ok, {:ready, user}}

      %User{} = user ->
        create_registration_invite_token(user)

      nil ->
        with {:ok, user} <- register_user(%{"email" => email}) do
          create_registration_invite_token(user)
        end
    end
  end

  @doc """
  Gets the passwordless user with the given invite token.

  Used for gating registration. The token is consumed only after password setup
  succeeds.
  """
  def get_user_by_invite_token(token) do
    with {:ok, query} <- UserToken.verify_invite_token_query(token),
         {%User{hashed_password: nil} = user, found_token} <- Repo.one(query) do
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
        user_changeset =
          user
          |> User.confirm_changeset()
          |> User.password_changeset(attrs, hash_password: true)

        with {1, nil} <- delete_registration_invite_token(token_record, user),
             {:ok, updated_user} <- Repo.update(user_changeset) do
          # Consume all registration tokens for this user immediately.
          delete_registration_invite_tokens(token_record.user_id)
          {:ok, updated_user}
        else
          {0, nil} -> {:error, :stale_invite_token}
          {:error, _reason} = error -> error
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

  defp create_registration_invite_token(%User{} = user) do
    Repo.transact(fn ->
      delete_registration_invite_tokens(user.id)

      {encoded_token, user_token} = UserToken.build_email_token(user, "invite")

      with {:ok, _user_token} <- Repo.insert(user_token) do
        {:ok, {:registration_required, encoded_token}}
      end
    end)
  end

  defp delete_registration_invite_token(%UserToken{} = token_record, %User{} = user) do
    Repo.delete_all(
      from(t in UserToken,
        where: t.id == ^token_record.id,
        where: t.user_id == ^user.id,
        where: t.context == "invite"
      )
    )
  end

  defp delete_registration_invite_tokens(user_id) do
    Repo.delete_all(from(t in UserToken, where: t.user_id == ^user_id and t.context == "invite"))
  end
end

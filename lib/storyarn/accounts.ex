defmodule Storyarn.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Accounts.{User, UserIdentity, UserNotifier, UserToken}
  alias Storyarn.Repo
  alias Storyarn.Workspaces

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user and creates a default workspace.

  The default workspace is named "{name}'s workspace" (localized).

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    Repo.transact(fn ->
      with {:ok, user} <- insert_user(attrs),
           {:ok, _workspace} <- create_default_workspace(user) do
        {:ok, user}
      end
    end)
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

  ## OAuth

  @doc """
  Finds or creates a user from OAuth provider data.

  If an identity with the provider+provider_id exists, returns the associated user.
  If the email matches an existing user, links the identity to that user.
  Otherwise, creates a new user and identity.
  """
  def find_or_create_user_from_oauth(provider, %Ueberauth.Auth{} = auth) do
    provider_id = to_string(auth.uid)

    Repo.transact(fn ->
      case get_identity_by_provider(provider, provider_id) do
        %UserIdentity{} = identity ->
          identity = Repo.preload(identity, :user)
          update_identity_from_auth(identity, auth)
          {:ok, identity.user}

        nil ->
          create_user_from_oauth(provider, auth)
      end
    end)
  end

  @doc """
  Gets an identity by provider and provider_id.
  """
  def get_identity_by_provider(provider, provider_id) do
    Repo.get_by(UserIdentity, provider: to_string(provider), provider_id: to_string(provider_id))
  end

  @doc """
  Gets all identities for a user.
  """
  def list_user_identities(user) do
    UserIdentity
    |> where(user_id: ^user.id)
    |> Repo.all()
  end

  @doc """
  Links an OAuth identity to an existing user.
  """
  def link_oauth_identity(user, provider, %Ueberauth.Auth{} = auth) do
    attrs = identity_attrs_from_auth(provider, auth)

    %UserIdentity{}
    |> UserIdentity.changeset(Map.put(attrs, :user_id, user.id))
    |> Repo.insert()
  end

  @doc """
  Unlinks an OAuth identity from a user.

  Will not unlink if it's the user's only authentication method
  (no password and only one identity).
  """
  def unlink_oauth_identity(user, provider) do
    identity = Repo.get_by(UserIdentity, user_id: user.id, provider: to_string(provider))

    identities_count =
      Repo.aggregate(from(i in UserIdentity, where: i.user_id == ^user.id), :count)

    cond do
      is_nil(identity) ->
        {:error, :not_found}

      is_nil(user.hashed_password) and identities_count <= 1 ->
        {:error, :cannot_unlink_only_auth_method}

      true ->
        Repo.delete(identity)
    end
  end

  defp create_user_from_oauth(provider, auth) do
    email = get_email_from_auth(auth)

    case get_user_by_email(email) do
      %User{} = user ->
        link_identity_to_user(user, provider, auth)

      nil ->
        create_new_user_with_identity(email, provider, auth)
    end
  end

  defp link_identity_to_user(user, provider, auth) do
    case link_oauth_identity(user, provider, auth) do
      {:ok, _identity} -> {:ok, user}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp create_new_user_with_identity(email, provider, auth) do
    with {:ok, user} <- register_user(%{email: email}),
         {:ok, user} <- confirm_oauth_user(user),
         {:ok, _identity} <- link_oauth_identity(user, provider, auth) do
      {:ok, user}
    end
  end

  defp confirm_oauth_user(user) do
    user
    |> User.confirm_changeset()
    |> Repo.update()
  end

  defp update_identity_from_auth(identity, auth) do
    attrs = %{
      provider_email: get_email_from_auth(auth),
      provider_name: get_name_from_auth(auth),
      provider_avatar: get_avatar_from_auth(auth),
      provider_token: auth.credentials.token,
      provider_refresh_token: auth.credentials.refresh_token
    }

    identity
    |> UserIdentity.changeset(attrs)
    |> Repo.update()
  end

  defp identity_attrs_from_auth(provider, auth) do
    %{
      provider: to_string(provider),
      provider_id: to_string(auth.uid),
      provider_email: get_email_from_auth(auth),
      provider_name: get_name_from_auth(auth),
      provider_avatar: get_avatar_from_auth(auth),
      provider_token: auth.credentials.token,
      provider_refresh_token: auth.credentials.refresh_token,
      provider_meta: %{}
    }
  end

  defp get_email_from_auth(%Ueberauth.Auth{info: info}) do
    info.email
  end

  defp get_name_from_auth(%Ueberauth.Auth{info: info}) do
    info.name || info.nickname
  end

  defp get_avatar_from_auth(%Ueberauth.Auth{info: info}) do
    info.image
  end

  ## Profile

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user profile.

  ## Examples

      iex> change_user_profile(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_profile(user, attrs \\ %{}) do
    User.profile_changeset(user, attrs)
  end

  @doc """
  Updates the user profile.

  ## Examples

      iex> update_user_profile(user, %{display_name: "New Name"})
      {:ok, %User{}}

      iex> update_user_profile(user, %{display_name: invalid})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_profile(user, attrs) do
    user
    |> User.profile_changeset(attrs)
    |> Repo.update()
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `Storyarn.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `Storyarn.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end

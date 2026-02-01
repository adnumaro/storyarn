defmodule Storyarn.Accounts do
  @moduledoc """
  The Accounts context handles user management, authentication,
  and identity operations.

  This module serves as a facade, delegating to specialized submodules:
  - `Users` - User lookups and queries
  - `Registration` - User registration with default workspace
  - `OAuth` - OAuth identity management
  - `Sessions` - Session token management
  - `MagicLinks` - Magic link authentication
  - `Emails` - Email change operations
  - `Passwords` - Password management
  - `Profiles` - User profile and sudo mode
  """

  alias Storyarn.Accounts.{
    Emails,
    MagicLinks,
    OAuth,
    Passwords,
    Profiles,
    Registration,
    Sessions,
    User,
    UserIdentity,
    Users,
    UserToken
  }

  # =============================================================================
  # Type Definitions
  # =============================================================================

  @type user :: User.t()
  @type user_identity :: UserIdentity.t()
  @type user_token :: UserToken.t()
  @type changeset :: Ecto.Changeset.t()
  @type attrs :: map()

  # =============================================================================
  # Users
  # =============================================================================

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil
  """
  @spec get_user_by_email(String.t()) :: user() | nil
  defdelegate get_user_by_email(email), to: Users

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil
  """
  @spec get_user_by_email_and_password(String.t(), String.t()) :: user() | nil
  defdelegate get_user_by_email_and_password(email, password), to: Users

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.
  """
  @spec get_user!(integer()) :: user()
  defdelegate get_user!(id), to: Users

  # =============================================================================
  # Registration
  # =============================================================================

  @doc """
  Registers a user and creates a default workspace.

  The default workspace is named "{name}'s workspace" (localized).
  """
  @spec register_user(attrs()) :: {:ok, user()} | {:error, changeset()}
  defdelegate register_user(attrs), to: Registration

  @doc """
  Registers a user without creating a default workspace.

  Used by OAuth flow and services that handle workspace creation separately.
  """
  @spec register_user_only(attrs()) :: {:ok, user()} | {:error, changeset()}
  defdelegate register_user_only(attrs), to: Registration

  # =============================================================================
  # OAuth
  # =============================================================================

  @doc """
  Finds or creates a user from OAuth provider data.

  If an identity with the provider+provider_id exists, returns the associated user.
  If the email matches an existing user, links the identity to that user.
  Otherwise, creates a new user and identity.
  """
  @spec find_or_create_user_from_oauth(String.t(), map()) ::
          {:ok, user()} | {:error, changeset()}
  def find_or_create_user_from_oauth(provider, auth) do
    OAuth.find_or_create_user_from_oauth(provider, auth, &register_user/1)
  end

  @doc """
  Gets an identity by provider and provider_id.
  """
  @spec get_identity_by_provider(String.t(), String.t()) :: user_identity() | nil
  defdelegate get_identity_by_provider(provider, provider_id), to: OAuth

  @doc """
  Gets all identities for a user.
  """
  @spec list_user_identities(user()) :: [user_identity()]
  defdelegate list_user_identities(user), to: OAuth

  @doc """
  Links an OAuth identity to an existing user.
  """
  @spec link_oauth_identity(user(), String.t(), map()) ::
          {:ok, user_identity()} | {:error, changeset()}
  defdelegate link_oauth_identity(user, provider, auth), to: OAuth

  @doc """
  Unlinks an OAuth identity from a user.

  Will not unlink if it's the user's only authentication method
  (no password and only one identity).
  """
  @spec unlink_oauth_identity(user(), String.t()) ::
          {:ok, user_identity()} | {:error, :only_auth_method}
  defdelegate unlink_oauth_identity(user, provider), to: OAuth

  # =============================================================================
  # Sessions
  # =============================================================================

  @doc """
  Generates a session token.
  """
  @spec generate_user_session_token(user()) :: binary()
  defdelegate generate_user_session_token(user), to: Sessions

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  @spec get_user_by_session_token(binary()) :: {user(), DateTime.t()} | nil
  defdelegate get_user_by_session_token(token), to: Sessions

  @doc """
  Deletes the signed token with the given context.
  """
  @spec delete_user_session_token(binary()) :: :ok
  defdelegate delete_user_session_token(token), to: Sessions

  # =============================================================================
  # Magic Links
  # =============================================================================

  @doc """
  Gets the user with the given magic link token.
  """
  @spec get_user_by_magic_link_token(String.t()) :: user() | nil
  defdelegate get_user_by_magic_link_token(token), to: MagicLinks

  @doc """
  Logs the user in by magic link.
  """
  @spec login_user_by_magic_link(String.t()) :: {:ok, user()} | :error
  defdelegate login_user_by_magic_link(token), to: MagicLinks

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  @spec deliver_login_instructions(user(), (String.t() -> String.t())) :: {:ok, map()}
  defdelegate deliver_login_instructions(user, magic_link_url_fun), to: MagicLinks

  # =============================================================================
  # Emails
  # =============================================================================

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.
  """
  @spec change_user_email(user(), attrs(), keyword()) :: changeset()
  defdelegate change_user_email(user, attrs \\ %{}, opts \\ []), to: Emails

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  @spec update_user_email(user(), String.t()) :: :ok | :error
  defdelegate update_user_email(user, token), to: Emails

  @doc ~S"""
  Delivers the update email instructions to the given user.
  """
  @spec deliver_user_update_email_instructions(user(), String.t(), (String.t() -> String.t())) ::
          {:ok, map()}
  defdelegate deliver_user_update_email_instructions(user, current_email, update_email_url_fun),
    to: Emails

  # =============================================================================
  # Passwords
  # =============================================================================

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.
  """
  @spec change_user_password(user(), attrs(), keyword()) :: changeset()
  defdelegate change_user_password(user, attrs \\ %{}, opts \\ []), to: Passwords

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.
  """
  @spec update_user_password(user(), attrs()) ::
          {:ok, user(), [user_token()]} | {:error, changeset()}
  defdelegate update_user_password(user, attrs), to: Passwords

  # =============================================================================
  # Profiles
  # =============================================================================

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user profile.
  """
  @spec change_user_profile(user(), attrs()) :: changeset()
  defdelegate change_user_profile(user, attrs \\ %{}), to: Profiles

  @doc """
  Updates the user profile.
  """
  @spec update_user_profile(user(), attrs()) :: {:ok, user()} | {:error, changeset()}
  defdelegate update_user_profile(user, attrs), to: Profiles

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  @spec sudo_mode?(user(), integer()) :: boolean()
  defdelegate sudo_mode?(user, minutes \\ -20), to: Profiles
end

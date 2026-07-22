defmodule Storyarn.Accounts do
  @moduledoc """
  The Accounts context handles user management, authentication,
  and identity operations.

  This module serves as a facade, delegating to specialized submodules:
  - `Users` - User lookups and queries
  - `Registration` - User registration with default workspace
  - `Sessions` - Session token management
  - `MagicLinks` - Magic link authentication
  - `Emails` - Email change operations
  - `Passwords` - Password management
  - `Profiles` - User profile and sudo mode
  """

  alias Storyarn.Accounts.Emails
  alias Storyarn.Accounts.Passwords
  alias Storyarn.Accounts.Profiles
  alias Storyarn.Accounts.Registration
  alias Storyarn.Accounts.Scope
  alias Storyarn.Accounts.Sessions
  alias Storyarn.Accounts.User
  alias Storyarn.Accounts.Users
  alias Storyarn.Accounts.UserToken

  # =============================================================================
  # Type Definitions
  # =============================================================================

  @type user :: User.t()
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
  Registers a public user with a password and creates a default workspace.
  """
  @spec register_user_with_password(attrs()) :: {:ok, user()} | {:error, changeset()}
  defdelegate register_user_with_password(attrs), to: Registration

  @doc """
  Returns an `%Ecto.Changeset{}` for public registration.
  """
  @spec change_user_registration(user(), attrs(), keyword()) :: changeset()
  defdelegate change_user_registration(user, attrs \\ %{}, opts \\ []), to: Registration

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
  Re-authenticates the scoped user's active session without elevating the session token.
  """
  @spec reauthenticate_user_session(Scope.t(), binary(), String.t()) ::
          {:ok, user()} | {:error, :invalid_credentials | :invalid_session}
  defdelegate reauthenticate_user_session(current_scope, token, password), to: Sessions

  @doc "Returns whether the token is an active session owned by the scoped user."
  @spec session_token_active?(Scope.t(), binary()) :: boolean()
  defdelegate session_token_active?(current_scope, token), to: Sessions

  @doc """
  Deletes the signed token with the given context.
  """
  @spec delete_user_session_token(binary()) :: :ok
  defdelegate delete_user_session_token(token), to: Sessions

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
  @spec update_user_email(user(), String.t()) :: {:ok, user()} | {:error, :transaction_aborted}
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
          {:ok, {user(), [user_token()]}} | {:error, changeset()}
  defdelegate update_user_password(user, attrs), to: Passwords

  @doc """
  Queues reset password instructions for the given user.
  """
  @spec deliver_user_reset_password_instructions(user(), (String.t() -> String.t())) ::
          {:ok, :queued} | {:error, term()}
  defdelegate deliver_user_reset_password_instructions(user, reset_password_url_fun), to: Passwords

  @doc """
  Queues a reset request without synchronously revealing whether the email exists.
  """
  @spec request_user_reset_password_instructions(String.t(), (String.t() -> String.t())) ::
          {:ok, :queued} | {:error, term()}
  defdelegate request_user_reset_password_instructions(email, reset_password_url_fun), to: Passwords

  @doc false
  @spec process_user_reset_password_request(String.t(), String.t()) ::
          :ok | {:ok, :queued} | {:error, term()}
  defdelegate process_user_reset_password_request(email, reset_url_template), to: Passwords

  @doc false
  @spec decrypt_reset_password_url(String.t()) :: {:ok, String.t()} | {:error, :invalid_reset_password_url}
  defdelegate decrypt_reset_password_url(encrypted_reset_url), to: Passwords

  @doc """
  Gets the user for a valid reset password token.
  """
  @spec get_user_by_reset_password_token(String.t()) :: user() | nil
  defdelegate get_user_by_reset_password_token(token), to: Passwords

  @doc """
  Resets the user password using reset-password semantics.
  """
  @spec reset_user_password(user(), attrs()) ::
          {:ok, {user(), [user_token()]}} | {:error, changeset()}
  defdelegate reset_user_password(user, attrs), to: Passwords

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

  @doc """
  Gets the user with the given invite token and deletes the token if found.
  Used for gating registration.
  """
  defdelegate get_user_by_invite_token(token), to: Registration

  @doc """
  Completes the user's registration by setting their password and consuming the invite token.
  """
  defdelegate complete_registration(user, token, attrs), to: Registration

  @doc """
  Finds an existing user by email, or registers and auto-confirms a new one.
  Used for invitation acceptance.
  """
  defdelegate find_or_register_confirmed_user(email), to: Registration

  @doc """
  Prepares a user for workspace/project invitation acceptance.

  Password users can accept immediately. New or passwordless users receive a
  registration token and must set a password first.
  """
  defdelegate prepare_invitation_user(email), to: Registration
end

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
  alias Storyarn.Accounts.Sessions
  alias Storyarn.Accounts.User
  alias Storyarn.Accounts.UserNotifier
  alias Storyarn.Accounts.Users
  alias Storyarn.Accounts.UserToken

  # =============================================================================
  # Type Definitions
  # =============================================================================

  alias Storyarn.Accounts.WaitlistEntry

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

  ## Waitlist

  @doc """
  Adds an email to the beta waitlist. Returns `{:ok, entry}` or `{:error, changeset}`.
  """
  def join_waitlist(attrs) do
    changeset = WaitlistEntry.email_changeset(%WaitlistEntry{}, attrs)

    case Storyarn.Repo.insert(changeset) do
      {:ok, entry} ->
        {:ok, entry}

      {:error, changeset} ->
        if email_unique_constraint_error?(changeset) do
          get_existing_waitlist_entry(attrs, changeset)
        else
          {:error, changeset}
        end
    end
  end

  @doc """
  Adds optional qualification details to an existing waitlist entry.
  """
  def update_waitlist_details(email, attrs) when is_binary(email) do
    email =
      email
      |> String.trim()
      |> String.downcase()

    case Storyarn.Repo.get_by(WaitlistEntry, email: email) do
      %WaitlistEntry{} = entry ->
        entry
        |> WaitlistEntry.details_changeset(attrs)
        |> Storyarn.Repo.update()

      nil ->
        {:error, :not_found}
    end
  end

  defp get_existing_waitlist_entry(attrs, fallback_changeset) do
    email =
      (attrs[:email] || attrs["email"])
      |> String.trim()
      |> String.downcase()

    case Storyarn.Repo.get_by(WaitlistEntry, email: email) do
      %WaitlistEntry{} = entry ->
        {:ok, entry}

      nil ->
        {:error, fallback_changeset}
    end
  end

  defp email_unique_constraint_error?(changeset) do
    Enum.any?(Keyword.get_values(changeset.errors, :email), fn {_message, opts} ->
      opts[:constraint] == :unique
    end)
  end

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
  Delivers the waitlist invite instructions to the given user.
  """
  defdelegate deliver_waitlist_invite_instructions(user, invite_url_fun), to: Registration

  @doc """
  Notifies the admin about a member invitation request.
  """
  def notify_admin_invitation_request(request_info) do
    UserNotifier.deliver_admin_invitation_request(request_info)
  end

  @doc """
  Notifies the admin about a new waitlist signup.
  """
  def notify_admin_waitlist_signup(email, signup_info \\ %{}) do
    UserNotifier.deliver_admin_waitlist_notification(email, signup_info)
  end

  @doc """
  Notifies the admin about a new waitlist signup without blocking the caller.
  """
  def notify_admin_waitlist_signup_async(email, signup_info \\ %{}) do
    case Process.whereis(Storyarn.TaskSupervisor) do
      nil ->
        notify_admin_waitlist_signup(email, signup_info)
        :ok

      _pid ->
        Task.Supervisor.start_child(Storyarn.TaskSupervisor, fn ->
          notify_admin_waitlist_signup(email, signup_info)
        end)

        :ok
    end
  end
end

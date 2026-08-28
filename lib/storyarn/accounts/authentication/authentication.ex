defmodule Storyarn.Accounts.Authentication do
  @moduledoc """
  Public capability boundary for credentials, sessions, sudo, and recovery.

  The root Accounts facade delegates here while commands, queries, token
  policies, delivery workflows, and technical adapters remain private.
  """

  alias Storyarn.Accounts.Authentication.Adapters.Encryption.ResetUrl
  alias Storyarn.Accounts.Authentication.Commands.EmailChange
  alias Storyarn.Accounts.Authentication.Commands.PasswordReset
  alias Storyarn.Accounts.Authentication.Commands.Passwords
  alias Storyarn.Accounts.Authentication.Commands.SessionTokens
  alias Storyarn.Accounts.Authentication.Commands.SudoHandoff
  alias Storyarn.Accounts.Authentication.Delivery.PasswordReset.Handler, as: PasswordResetHandler
  alias Storyarn.Accounts.Authentication.Events.UserLoggedIn
  alias Storyarn.Accounts.Authentication.Queries.Credentials
  alias Storyarn.Accounts.Authentication.Queries.PasswordReset, as: PasswordResetQuery
  alias Storyarn.Accounts.Authentication.Queries.Sessions
  alias Storyarn.Accounts.Authentication.Queries.SudoHandoff, as: SudoHandoffQuery
  alias Storyarn.Accounts.Authentication.RateLimits
  alias Storyarn.Accounts.Authentication.Rules.SudoWindow
  alias Storyarn.Accounts.Scope

  defdelegate check_login_rate(ip_address), to: RateLimits, as: :check_login
  defdelegate check_sudo_rate(user_id, ip_address), to: RateLimits, as: :check_sudo
  defdelegate check_registration_rate(ip_address), to: RateLimits, as: :check_registration

  defdelegate check_password_reset_rate(ip_address, email),
    to: RateLimits,
    as: :check_password_reset

  defdelegate get_user_by_email_and_password(email, password), to: Credentials, as: :authenticate
  defdelegate user_logged_in(user, auth_method), to: UserLoggedIn, as: :publish
  defdelegate scope_for_user(user), to: Scope, as: :for_user

  defdelegate generate_user_session_token(user), to: SessionTokens, as: :generate
  defdelegate get_user_by_session_token(token), to: Sessions, as: :get
  defdelegate reauthenticate_user_session(scope, token, password), to: Sessions, as: :reauthenticate
  defdelegate session_token_active?(scope, token), to: Sessions, as: :active?
  defdelegate delete_user_session_token(token), to: SessionTokens, as: :delete

  defdelegate generate_sudo_handoff_nonce(user), to: SudoHandoff, as: :generate
  defdelegate sudo_handoff_nonce_active?(scope, nonce), to: SudoHandoffQuery, as: :active?
  defdelegate consume_sudo_handoff_nonce(scope, nonce), to: SudoHandoff, as: :consume
  defdelegate sudo_mode?(user, minutes \\ -20), to: SudoWindow, as: :active?

  defdelegate change_user_email(user, attrs \\ %{}, opts \\ []), to: EmailChange, as: :change
  defdelegate update_user_email(user, token), to: EmailChange, as: :update

  defdelegate deliver_user_update_email_instructions(user, current_email, update_email_url_fun),
    to: EmailChange,
    as: :deliver_instructions

  defdelegate change_user_password(user, attrs \\ %{}, opts \\ []), to: Passwords, as: :change
  defdelegate update_user_password(user, attrs), to: Passwords, as: :update
  defdelegate reset_user_password(user, attrs), to: Passwords, as: :reset

  defdelegate deliver_user_reset_password_instructions(user, reset_password_url_fun),
    to: PasswordReset,
    as: :deliver

  defdelegate request_user_reset_password_instructions(email, reset_password_url_fun),
    to: PasswordReset,
    as: :request

  defdelegate process_user_reset_password_request(email, reset_url_template),
    to: PasswordReset,
    as: :process

  defdelegate decrypt_reset_password_url(encrypted_reset_url), to: ResetUrl, as: :decrypt
  defdelegate deliver_reset_password_instructions(email, reset_url), to: PasswordResetHandler, as: :deliver
  defdelegate get_user_by_reset_password_token(token), to: PasswordResetQuery, as: :get_user
end

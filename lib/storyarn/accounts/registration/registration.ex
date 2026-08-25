defmodule Storyarn.Accounts.Registration do
  @moduledoc false

  alias Storyarn.Accounts.Registration.Commands.CompleteInvitation
  alias Storyarn.Accounts.Registration.Commands.PrepareInvitation
  alias Storyarn.Accounts.Registration.Commands.Register
  alias Storyarn.Accounts.Registration.Queries.InvitationUser

  defdelegate register_user(attrs), to: Register
  defdelegate register_user_with_password(attrs), to: Register
  defdelegate change_user_registration(user, attrs \\ %{}, opts \\ []), to: Register

  defdelegate find_or_register_confirmed_user(email), to: PrepareInvitation
  defdelegate prepare_invitation_user(email), to: PrepareInvitation

  defdelegate get_user_by_invite_token(token), to: InvitationUser, as: :get
  defdelegate complete_registration(user, token_record, attrs), to: CompleteInvitation, as: :execute
end

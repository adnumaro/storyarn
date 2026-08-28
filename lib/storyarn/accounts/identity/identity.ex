defmodule Storyarn.Accounts.Identity do
  @moduledoc """
  Public capability boundary for account identity and profile operations.

  The root Accounts facade delegates identity reads and profile mutations here,
  while queries, commands, entities, and technical adapters remain private to
  the capability.
  """

  alias Storyarn.Accounts.Identity.Commands.Profile
  alias Storyarn.Accounts.Identity.Queries.Users
  alias Storyarn.Accounts.User

  defdelegate get_user_by_email(email), to: Users
  defdelegate get_user!(id), to: Users
  defdelegate validate_email_format(changeset), to: User

  def new_user, do: %User{}

  defdelegate change_user_profile(user, attrs \\ %{}), to: Profile
  defdelegate update_user_profile(user, attrs), to: Profile
end

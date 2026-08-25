defmodule Storyarn.Accounts.Identity.Commands.Profile do
  @moduledoc false

  alias Storyarn.Accounts.User
  alias Storyarn.Repo

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user profile.
  """
  def change_user_profile(user, attrs \\ %{}) do
    User.profile_changeset(user, attrs)
  end

  @doc """
  Updates the user profile.
  """
  def update_user_profile(user, attrs) do
    user
    |> User.profile_changeset(attrs)
    |> Repo.update()
  end
end

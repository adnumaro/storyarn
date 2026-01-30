defmodule Storyarn.Accounts.Profiles do
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
end

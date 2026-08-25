defmodule Storyarn.Accounts.Authentication.Rules.SudoWindow do
  @moduledoc false

  alias Storyarn.Accounts.User
  alias Storyarn.Platform.Shared.TimeHelpers

  @spec active?(User.t() | term(), integer()) :: boolean()
  def active?(user, minutes \\ -20)

  def active?(%User{authenticated_at: timestamp}, minutes) when is_struct(timestamp, DateTime) do
    DateTime.after?(timestamp, DateTime.add(TimeHelpers.now(), minutes, :minute))
  end

  def active?(_user, _minutes), do: false
end

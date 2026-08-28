defmodule Storyarn.Workspaces.Invitations.Rules.Policy do
  @moduledoc false

  @allowed_roles ~w(admin member viewer)
  @default_role "member"
  @invitation_validity_in_days 7
  @seconds_per_day 86_400

  def allowed_roles, do: @allowed_roles
  def default_role, do: @default_role
  def validity_in_days, do: @invitation_validity_in_days

  def expires_at(now) do
    DateTime.add(now, @invitation_validity_in_days, :day)
  end

  def remaining_days(expires_at, now) do
    remaining_seconds = DateTime.diff(expires_at, now, :second)
    div(max(remaining_seconds, 1) + @seconds_per_day - 1, @seconds_per_day)
  end
end

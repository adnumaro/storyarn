defimpl FunWithFlags.Actor, for: Storyarn.Accounts.User do
  @moduledoc """
  Enables per-user feature-flag targeting for `Storyarn.Accounts.User`.

  The prefix disambiguates users from other actor types the app may target in
  the future (workspaces, projects) so flags stored in FunWithFlags cannot
  collide across actor namespaces.
  """
  def id(%Storyarn.Accounts.User{id: id}), do: "user:#{id}"
end

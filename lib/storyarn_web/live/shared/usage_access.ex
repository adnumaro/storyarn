defmodule StoryarnWeb.Live.Shared.UsageAccess do
  @moduledoc """
  Who may see plan and usage figures, for the pages and notices that show them.

  A workspace's totals (storage, projects) go to the people who edit it: its
  owner, admins and members. Viewers and people who are only members of a
  project in it get none, and their errors say there is not enough space
  without figures. The account's plan belongs to the workspace owner alone,
  so only they get the link to Plan & billing.
  """

  use StoryarnWeb, :verified_routes

  alias Storyarn.Workspaces

  @doc "Whether the scope's user may see the totals of the workspace."
  @spec workspace_totals_visible?(map(), pos_integer()) :: boolean()
  def workspace_totals_visible?(scope, workspace_id) when is_integer(workspace_id) do
    match?({:ok, _workspace, _membership}, Workspaces.authorize(scope, workspace_id, :view_workspace_usage))
  end

  def workspace_totals_visible?(_scope, _workspace_id), do: false

  @doc "The workspace's Usage page, for those who may see its totals."
  @spec workspace_usage_path(map(), map()) :: String.t() | nil
  def workspace_usage_path(scope, %{id: workspace_id, slug: slug}) do
    if workspace_totals_visible?(scope, workspace_id),
      do: ~p"/users/settings/workspaces/#{slug}/usage"
  end

  @doc "The owner's Plan & billing page, only when the scope's user owns the workspace."
  @spec plan_path(map(), map()) :: String.t() | nil
  def plan_path(%{user: %{id: user_id}}, %{owner_id: user_id}), do: ~p"/users/settings/plan"
  def plan_path(_scope, _workspace), do: nil
end

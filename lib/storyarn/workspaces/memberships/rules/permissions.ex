defmodule Storyarn.Workspaces.Memberships.Rules.Permissions do
  @moduledoc false

  @roles ~w(owner admin member viewer)

  @spec roles() :: [String.t()]
  def roles, do: @roles

  @spec allowed?(String.t() | nil, atom()) :: boolean()
  def allowed?(role, action)

  def allowed?("owner", _action), do: true
  def allowed?("admin", :access_workspace_general_settings), do: true
  def allowed?("admin", :access_workspace_settings), do: true
  def allowed?("admin", :manage_members), do: true
  def allowed?("admin", :create_project), do: true
  def allowed?("admin", :use_ai), do: true
  def allowed?("admin", :view), do: true
  def allowed?("admin", :view_workspace_usage), do: true
  def allowed?("member", :access_workspace_general_settings), do: true
  def allowed?("member", :create_project), do: true
  def allowed?("member", :view), do: true
  # A workspace's totals (storage, projects) belong to the people who edit it.
  # Viewers and project-only members receive none.
  def allowed?("member", :view_workspace_usage), do: true
  def allowed?("viewer", :view), do: true
  def allowed?(_role, _action), do: false
end

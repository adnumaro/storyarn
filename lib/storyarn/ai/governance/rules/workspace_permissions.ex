defmodule Storyarn.AI.Governance.Rules.WorkspacePermissions do
  @moduledoc "AI's workspace-role interpretation for policy and execution decisions."

  @spec allowed?(String.t() | nil, atom()) :: boolean()
  def allowed?(role, action)

  def allowed?("owner", _action), do: true
  def allowed?("admin", :access_workspace_general_settings), do: true
  def allowed?("admin", :access_workspace_settings), do: true
  def allowed?("admin", :manage_members), do: true
  def allowed?("admin", :create_project), do: true
  def allowed?("admin", :use_ai), do: true
  def allowed?("admin", :view), do: true
  def allowed?("member", :access_workspace_general_settings), do: true
  def allowed?("member", :create_project), do: true
  def allowed?("member", :view), do: true
  def allowed?("viewer", :view), do: true
  def allowed?(_role, _action), do: false
end

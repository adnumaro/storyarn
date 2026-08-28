defmodule Storyarn.AI.Governance.Rules.ProjectPermissions do
  @moduledoc "AI's project-role interpretation for execution and result application."

  @workspace_to_project_role %{
    "owner" => "editor",
    "admin" => "editor",
    "member" => "editor",
    "viewer" => "viewer"
  }

  @spec allowed?(String.t() | nil, atom()) :: boolean()
  def allowed?(role, action)

  def allowed?("owner", _action), do: true
  def allowed?("editor", :edit_content), do: true
  def allowed?("editor", :use_ai), do: true
  def allowed?("editor", :view), do: true
  def allowed?("viewer", :view), do: true
  def allowed?(_role, _action), do: false

  @spec effective_role(String.t() | nil, String.t() | nil) :: String.t() | nil
  def effective_role(nil, nil), do: nil
  def effective_role(nil, workspace_role), do: Map.get(@workspace_to_project_role, workspace_role, "viewer")
  def effective_role(project_role, _workspace_role), do: project_role
end

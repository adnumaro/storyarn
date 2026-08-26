defmodule Storyarn.Localization.Access.Rules.EffectiveMembership do
  @moduledoc false

  @workspace_to_project_role %{
    "owner" => "editor",
    "admin" => "editor",
    "member" => "editor",
    "viewer" => "viewer"
  }

  @spec project_role(String.t()) :: String.t()
  def project_role(workspace_role) do
    Map.get(@workspace_to_project_role, workspace_role, "viewer")
  end
end

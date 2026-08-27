defmodule Storyarn.Projects.ProjectTemplates.AuthorizationRules do
  @moduledoc false

  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectTemplates.ProjectTemplate

  def ensure_private_visibility(attrs) do
    visibility = Map.get(attrs, :visibility) || Map.get(attrs, "visibility") || "private"

    if visibility == "private",
      do: :ok,
      else: {:error, :public_visibility_requires_admin}
  end

  def project_manager?(project_manager?, workspace_admin?) do
    project_manager? or workspace_admin?
  end

  def private_template_manager?(%ProjectTemplate{} = template, user_id, source_admin?) do
    template.owner_id == user_id or source_admin?
  end

  def ensure_template_source(%ProjectTemplate{source_project_id: project_id}, %Project{id: project_id}), do: :ok

  def ensure_template_source(%ProjectTemplate{}, %Project{}), do: {:error, :invalid_source_project}

  def visibility_authorized?(%ProjectTemplate{status: "active", visibility: "private"}, manager?), do: manager?

  def visibility_authorized?(%ProjectTemplate{status: "active", visibility: "public"}, _manager?), do: true

  def visibility_authorized?(%ProjectTemplate{}, _manager?), do: false
end

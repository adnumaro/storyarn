defmodule Storyarn.ProjectTemplates.Authorization do
  @moduledoc false

  alias Storyarn.Accounts.Scope
  alias Storyarn.Projects
  alias Storyarn.Projects.Project
  alias Storyarn.ProjectTemplates.ProjectTemplate

  def ensure_private_visibility(attrs) do
    visibility = Map.get(attrs, :visibility) || Map.get(attrs, "visibility") || "private"

    if visibility == "private" do
      :ok
    else
      {:error, :public_visibility_requires_admin}
    end
  end

  def authorize_source_project(%Scope{user: user} = scope, %Project{id: project_id}) when not is_nil(user) do
    case Projects.get_project(scope, project_id) do
      {:ok, project, membership} ->
        if Projects.can?(membership.role, :manage_project) do
          {:ok, project}
        else
          {:error, :unauthorized}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def authorize_source_project(_scope, _project), do: {:error, :unauthorized}

  def ensure_template_source(%ProjectTemplate{source_project_id: project_id}, %Project{id: project_id}), do: :ok
  def ensure_template_source(%ProjectTemplate{}, %Project{}), do: {:error, :invalid_source_project}

  def authorize_template_owner(%Scope{user: %{id: user_id}}, %ProjectTemplate{owner_id: user_id, visibility: "private"}) do
    :ok
  end

  def authorize_template_owner(_scope, _template), do: {:error, :unauthorized}

  def authorize_template_visibility(%Scope{user: %{id: user_id}}, %ProjectTemplate{
        status: "active",
        visibility: "private",
        owner_id: user_id
      }) do
    :ok
  end

  def authorize_template_visibility(%Scope{user: %{}}, %ProjectTemplate{status: "active", visibility: "public"}) do
    :ok
  end

  def authorize_template_visibility(%Scope{}, %ProjectTemplate{status: "archived"}), do: {:error, :archived}

  def authorize_template_visibility(_scope, _template), do: {:error, :unauthorized}
end

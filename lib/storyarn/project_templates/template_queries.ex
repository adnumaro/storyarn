defmodule Storyarn.ProjectTemplates.TemplateQueries do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.Scope
  alias Storyarn.ProjectTemplates.Authorization
  alias Storyarn.ProjectTemplates.ProjectTemplate
  alias Storyarn.ProjectTemplates.ProjectTemplateInstall
  alias Storyarn.ProjectTemplates.ProjectTemplatePublication
  alias Storyarn.ProjectTemplates.ProjectTemplateVersion
  alias Storyarn.Repo

  @publication_preloads [:source_project, :project_template, :project_template_version]

  def publication_preloads, do: @publication_preloads

  def list_templates(%Scope{user: %{id: user_id}}, opts \\ []) do
    status = Keyword.get(opts, :status, "active")
    source_project_id = Keyword.get(opts, :source_project_id)

    ProjectTemplate
    |> visible_templates_query(user_id)
    |> where([template], template.status == ^status)
    |> maybe_filter_source_project(source_project_id)
    |> preload([:owner, :source_project, :current_version])
    |> order_by([template], asc: template.visibility, asc: template.name, asc: template.id)
    |> Repo.all()
  end

  def get_template(%Scope{user: %{id: user_id}}, id) do
    user_id
    |> visible_template_by_id_query(id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      template -> {:ok, template}
    end
  end

  def get_template!(%Scope{user: %{id: user_id}}, id) do
    user_id
    |> visible_template_by_id_query(id)
    |> Repo.one!()
  end

  def list_template_versions(%Scope{} = scope, %ProjectTemplate{} = template) do
    case Authorization.authorize_template_visibility(scope, template) do
      :ok ->
        ProjectTemplateVersion
        |> where([version], version.project_template_id == ^template.id)
        |> preload([:published_by])
        |> order_by([version], desc: version.version_number)
        |> Repo.all()

      {:error, _reason} ->
        []
    end
  end

  def list_template_installs(scope, template, opts \\ [])

  def list_template_installs(%Scope{user: %{id: user_id}}, %ProjectTemplate{owner_id: user_id} = template, opts) do
    limit = Keyword.get(opts, :limit, 10)

    ProjectTemplateInstall
    |> join(:inner, [install], version in assoc(install, :project_template_version))
    |> where([_install, version], version.project_template_id == ^template.id)
    |> order_by([install, _version], desc: install.installed_at, desc: install.id)
    |> limit(^limit)
    |> preload([_install, version], [:user, :workspace, :project, project_template_version: version])
    |> Repo.all()
  end

  def list_template_installs(%Scope{}, %ProjectTemplate{}, _opts), do: []

  def list_template_publications(%Scope{user: %{id: user_id}}, opts \\ []) do
    ProjectTemplatePublication
    |> where([publication], publication.owner_id == ^user_id)
    |> maybe_filter_publication_source_project(Keyword.get(opts, :source_project_id))
    |> maybe_filter_publication_template(Keyword.get(opts, :project_template_id))
    |> preload(^@publication_preloads)
    |> order_by([publication], desc: publication.inserted_at, desc: publication.id)
    |> maybe_limit(Keyword.get(opts, :limit, 20))
    |> Repo.all()
  end

  def get_template_publication!(%Scope{user: %{id: user_id}}, id) do
    ProjectTemplatePublication
    |> where([publication], publication.owner_id == ^user_id)
    |> where([publication], publication.id == ^id)
    |> preload(^@publication_preloads)
    |> Repo.one!()
  end

  def preload_template(template) do
    Repo.preload(template, [:owner, :source_project, :current_version], force: true)
  end

  def next_version_number(template_id) do
    ProjectTemplateVersion
    |> where([version], version.project_template_id == ^template_id)
    |> select([version], coalesce(max(version.version_number), 0) + 1)
    |> Repo.one()
  end

  defp visible_template_by_id_query(user_id, id) do
    ProjectTemplate
    |> visible_templates_query(user_id)
    |> where([template], template.id == ^id)
    |> where([template], template.status == "active")
    |> preload([:owner, :source_project, :current_version])
  end

  defp visible_templates_query(query, user_id) do
    from template in query,
      where:
        (template.visibility == "private" and template.owner_id == ^user_id) or
          template.visibility == "public"
  end

  defp maybe_filter_source_project(query, nil), do: query

  defp maybe_filter_source_project(query, source_project_id) do
    where(query, [template], template.source_project_id == ^source_project_id)
  end

  defp maybe_filter_publication_source_project(query, nil), do: query

  defp maybe_filter_publication_source_project(query, source_project_id) do
    where(query, [publication], publication.source_project_id == ^source_project_id)
  end

  defp maybe_filter_publication_template(query, nil), do: query

  defp maybe_filter_publication_template(query, template_id) do
    where(query, [publication], publication.project_template_id == ^template_id)
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit_value), do: limit(query, ^limit_value)
end

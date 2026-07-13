defmodule Storyarn.ProjectTemplates.TemplateQueries do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.Scope
  alias Storyarn.Projects.Project
  alias Storyarn.ProjectTemplates.Authorization
  alias Storyarn.ProjectTemplates.ProjectTemplate
  alias Storyarn.ProjectTemplates.ProjectTemplateInstall
  alias Storyarn.ProjectTemplates.ProjectTemplatePublication
  alias Storyarn.ProjectTemplates.ProjectTemplateVersion
  alias Storyarn.Repo
  alias Storyarn.Shared.SearchHelpers
  alias Storyarn.Workspaces.WorkspaceMembership

  @publication_preloads [:source_project, :project_template, :project_template_version]
  @default_per_page 12
  @max_per_page 48

  def publication_preloads, do: @publication_preloads

  def list_templates(%Scope{user: %{id: user_id}}, opts \\ []) do
    status = Keyword.get(opts, :status, "active")
    source_project_id = Keyword.get(opts, :source_project_id)
    visibility = Keyword.get(opts, :visibility)
    search = normalize_search(Keyword.get(opts, :search))

    ProjectTemplate
    |> visible_templates_query(user_id)
    |> where([template], template.status == ^status)
    |> maybe_filter_source_project(source_project_id)
    |> maybe_filter_visibility(visibility)
    |> maybe_filter_search(search)
    |> preload([:owner, :current_version])
    |> order_by([template], asc: template.visibility, asc: template.name, asc: template.id)
    |> Repo.all()
  end

  def paginate_templates(%Scope{user: %{id: user_id}}, opts \\ []) do
    status = Keyword.get(opts, :status, "active")
    source_project_id = Keyword.get(opts, :source_project_id)
    visibility = Keyword.get(opts, :visibility)
    search = normalize_search(Keyword.get(opts, :search))
    per_page = normalize_per_page(Keyword.get(opts, :per_page))

    query =
      ProjectTemplate
      |> visible_templates_query(user_id)
      |> where([template], template.status == ^status)
      |> maybe_filter_source_project(source_project_id)
      |> maybe_filter_visibility(visibility)
      |> maybe_filter_search(search)

    total_count = Repo.one(from(template in query, select: count(template.id)))
    total_pages = total_pages(total_count, per_page)
    page = opts |> Keyword.get(:page) |> normalize_positive_integer(1) |> max(1) |> min(total_pages)

    entries =
      query
      |> preload([:owner, :current_version])
      |> order_by([template], asc: template.visibility, asc: template.name, asc: template.id)
      |> limit(^per_page)
      |> offset(^((page - 1) * per_page))
      |> Repo.all()

    %{
      entries: entries,
      page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_pages
    }
  end

  def get_template(scope, id, opts \\ [])

  def get_template(%Scope{user: %{id: user_id}} = scope, id, opts) do
    status = Keyword.get(opts, :status, "active")

    user_id
    |> visible_template_by_id_query(id, status)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      template -> {:ok, preload_template(template, scope)}
    end
  end

  def get_template!(%Scope{user: %{id: user_id}}, id) do
    user_id
    |> visible_template_by_id_query(id, "active")
    |> Repo.one!()
  end

  def list_template_versions(%Scope{} = scope, %ProjectTemplate{} = template) do
    case Authorization.authorize_template_visibility(scope, template) do
      :ok ->
        preloads =
          if Authorization.can_manage_template?(scope, template) do
            [:published_by]
          else
            []
          end

        ProjectTemplateVersion
        |> where([version], version.project_template_id == ^template.id)
        |> preload(^preloads)
        |> order_by([version], desc: version.version_number)
        |> Repo.all()

      {:error, _reason} ->
        []
    end
  end

  def list_template_installs(scope, template, opts \\ [])

  def list_template_installs(%Scope{} = scope, %ProjectTemplate{} = template, opts) do
    limit = Keyword.get(opts, :limit, 10)

    if Authorization.can_manage_template?(scope, template) do
      ProjectTemplateInstall
      |> join(:inner, [install], version in assoc(install, :project_template_version))
      |> where([_install, version], version.project_template_id == ^template.id)
      |> where([install], install.status == "completed")
      |> order_by([install, _version], desc: install.installed_at, desc: install.id)
      |> limit(^limit)
      |> preload([_install, version], project_template_version: version)
      |> Repo.all()
    else
      []
    end
  end

  def list_template_publications(%Scope{user: %{id: user_id}}, opts \\ []) do
    ProjectTemplatePublication
    |> visible_publications_query(user_id)
    |> maybe_filter_publication_source_project(Keyword.get(opts, :source_project_id))
    |> maybe_filter_publication_template(Keyword.get(opts, :project_template_id))
    |> preload(^@publication_preloads)
    |> order_by([publication], desc: publication.inserted_at, desc: publication.id)
    |> maybe_limit(Keyword.get(opts, :limit, 20))
    |> Repo.all()
  end

  def get_template_publication!(%Scope{user: %{id: user_id}}, id) do
    ProjectTemplatePublication
    |> visible_publications_query(user_id)
    |> where([publication], publication.id == ^id)
    |> preload(^@publication_preloads)
    |> Repo.one!()
  end

  def preload_template(template, scope \\ nil)

  def preload_template(template, %Scope{} = scope) do
    preloads =
      if Authorization.can_manage_template?(scope, template) do
        [:owner, :source_project, :current_version]
      else
        [:owner, :current_version]
      end

    Repo.preload(template, preloads, force: true)
  end

  def preload_template(template, _scope) do
    Repo.preload(template, [:owner, :current_version], force: true)
  end

  def next_version_number(template_id) do
    ProjectTemplateVersion
    |> where([version], version.project_template_id == ^template_id)
    |> select([version], coalesce(max(version.version_number), 0) + 1)
    |> Repo.one()
  end

  defp visible_template_by_id_query(user_id, id, status) do
    query =
      ProjectTemplate
      |> visible_templates_query(user_id)
      |> where([template], template.id == ^id)
      |> preload([:owner, :current_version])

    maybe_filter_status(query, status)
  end

  defp maybe_filter_status(query, :any), do: query
  defp maybe_filter_status(query, status), do: where(query, [template], template.status == ^status)

  defp visible_templates_query(query, user_id) do
    from template in query,
      left_join: source_project in Project,
      on: source_project.id == template.source_project_id,
      left_join: source_membership in WorkspaceMembership,
      on:
        source_membership.workspace_id == source_project.workspace_id and source_membership.user_id == ^user_id and
          source_membership.role in ["owner", "admin"],
      where:
        (template.visibility == "public" and template.status == "active") or
          (template.visibility == "private" and
             (template.owner_id == ^user_id or not is_nil(source_membership.id)))
  end

  defp visible_publications_query(query, user_id) do
    from publication in query,
      join: source_project in Project,
      on: source_project.id == publication.source_project_id,
      left_join: source_membership in WorkspaceMembership,
      on:
        source_membership.workspace_id == source_project.workspace_id and source_membership.user_id == ^user_id and
          source_membership.role in ["owner", "admin"],
      where: publication.owner_id == ^user_id or not is_nil(source_membership.id)
  end

  defp maybe_filter_source_project(query, nil), do: query

  defp maybe_filter_source_project(query, source_project_id) do
    where(query, [template], template.source_project_id == ^source_project_id)
  end

  defp maybe_filter_visibility(query, visibility) when visibility in ["private", "public"] do
    where(query, [template], template.visibility == ^visibility)
  end

  defp maybe_filter_visibility(query, _visibility), do: query

  defp maybe_filter_search(query, ""), do: query

  defp maybe_filter_search(query, search) do
    search_term = "%#{SearchHelpers.sanitize_like_query(search)}%"
    where(query, [template], ilike(template.name, ^search_term) or ilike(template.description, ^search_term))
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

  defp normalize_search(search) when is_binary(search), do: String.trim(search)
  defp normalize_search(_search), do: ""

  defp normalize_per_page(per_page) do
    per_page
    |> normalize_positive_integer(@default_per_page)
    |> max(1)
    |> min(@max_per_page)
  end

  defp normalize_positive_integer(value, _default) when is_integer(value) and value >= 0, do: value

  defp normalize_positive_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer >= 0 -> integer
      _ -> default
    end
  end

  defp normalize_positive_integer(_value, default), do: default

  defp total_pages(0, _per_page), do: 1
  defp total_pages(total_count, per_page), do: div(total_count + per_page - 1, per_page)
end

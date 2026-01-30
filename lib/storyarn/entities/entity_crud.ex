defmodule Storyarn.Entities.EntityCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Entities.{Entity, EntityTemplate}
  alias Storyarn.Projects.Project
  alias Storyarn.Repo

  @doc """
  Lists entities for a project with optional filtering.

  ## Options

    * `:template_id` - Filter by template ID
    * `:type` - Filter by entity type (via template)
    * `:search` - Search by display_name or technical_name

  """
  def list_entities(project_id, opts \\ []) do
    query =
      from(e in Entity,
        where: e.project_id == ^project_id,
        preload: [:template]
      )

    query =
      case Keyword.get(opts, :template_id) do
        nil -> query
        template_id -> where(query, [e], e.template_id == ^template_id)
      end

    query =
      case Keyword.get(opts, :type) do
        nil ->
          query

        type ->
          from(e in query,
            join: t in assoc(e, :template),
            where: t.type == ^type
          )
      end

    query =
      case Keyword.get(opts, :search) do
        nil ->
          query

        "" ->
          query

        search ->
          search_term = "%#{search}%"

          where(
            query,
            [e],
            ilike(e.display_name, ^search_term) or ilike(e.technical_name, ^search_term)
          )
      end

    query
    |> order_by([e], asc: e.display_name)
    |> Repo.all()
  end

  @doc """
  Gets a single entity by ID within a project.

  Returns `nil` if the entity doesn't exist or doesn't belong to the project.
  """
  def get_entity(project_id, entity_id) do
    Entity
    |> where(project_id: ^project_id, id: ^entity_id)
    |> preload(:template)
    |> Repo.one()
  end

  @doc """
  Gets a single entity by ID within a project.

  Raises `Ecto.NoResultsError` if not found.
  """
  def get_entity!(project_id, entity_id) do
    Entity
    |> where(project_id: ^project_id, id: ^entity_id)
    |> preload(:template)
    |> Repo.one!()
  end

  @doc """
  Creates an entity from a template.
  """
  def create_entity(%Project{} = project, %EntityTemplate{} = template, attrs) do
    %Entity{project_id: project.id, template_id: template.id}
    |> Entity.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an entity.
  """
  def update_entity(%Entity{} = entity, attrs) do
    entity
    |> Entity.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an entity.
  """
  def delete_entity(%Entity{} = entity) do
    Repo.delete(entity)
  end

  @doc """
  Returns a changeset for tracking entity changes.
  """
  def change_entity(%Entity{} = entity, attrs \\ %{}) do
    Entity.update_changeset(entity, attrs)
  end

  @doc """
  Counts entities by template.

  Returns a map of template_id => count.
  """
  def count_entities_by_template(project_id) do
    from(e in Entity,
      where: e.project_id == ^project_id,
      group_by: e.template_id,
      select: {e.template_id, count(e.id)}
    )
    |> Repo.all()
    |> Map.new()
  end
end

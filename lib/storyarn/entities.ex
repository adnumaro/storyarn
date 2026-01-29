defmodule Storyarn.Entities do
  @moduledoc """
  The Entities context.

  Handles entity templates, entities (characters, locations, items), and variables
  within a project.
  """

  import Ecto.Query, warn: false
  alias Storyarn.Repo

  alias Storyarn.Entities.{Entity, EntityTemplate, Variable}
  alias Storyarn.Projects.Project

  ## Entity Templates

  @doc """
  Lists all templates for a project.
  """
  def list_templates(project_id) do
    EntityTemplate
    |> where(project_id: ^project_id)
    |> order_by([t], asc: t.type, asc: t.name)
    |> Repo.all()
  end

  @doc """
  Lists templates for a project, optionally filtered by type.
  """
  def list_templates(project_id, opts) when is_list(opts) do
    query = from(t in EntityTemplate, where: t.project_id == ^project_id)

    query =
      case Keyword.get(opts, :type) do
        nil -> query
        type -> where(query, [t], t.type == ^type)
      end

    query
    |> order_by([t], asc: t.type, asc: t.name)
    |> Repo.all()
  end

  @doc """
  Gets a single template by ID within a project.

  Returns `nil` if the template doesn't exist or doesn't belong to the project.
  """
  def get_template(project_id, template_id) do
    EntityTemplate
    |> where(project_id: ^project_id, id: ^template_id)
    |> Repo.one()
  end

  @doc """
  Gets a single template by ID within a project.

  Raises `Ecto.NoResultsError` if not found.
  """
  def get_template!(project_id, template_id) do
    EntityTemplate
    |> where(project_id: ^project_id, id: ^template_id)
    |> Repo.one!()
  end

  @doc """
  Creates an entity template.
  """
  def create_template(%Project{} = project, attrs) do
    %EntityTemplate{project_id: project.id}
    |> EntityTemplate.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an entity template.
  """
  def update_template(%EntityTemplate{} = template, attrs) do
    template
    |> EntityTemplate.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an entity template.

  Will fail if entities exist using this template.
  """
  def delete_template(%EntityTemplate{} = template) do
    Repo.delete(template)
  end

  @doc """
  Returns a changeset for tracking template changes.
  """
  def change_template(%EntityTemplate{} = template, attrs \\ %{}) do
    EntityTemplate.update_changeset(template, attrs)
  end

  @doc """
  Creates default templates for a project (one for each type).
  """
  def create_default_templates(%Project{} = project) do
    Repo.transact(fn ->
      results =
        Enum.map(EntityTemplate.types(), fn type ->
          create_template(project, %{
            name: String.capitalize(type),
            type: type,
            is_default: true
          })
        end)

      case Enum.find(results, &match?({:error, _}, &1)) do
        nil -> {:ok, Enum.map(results, fn {:ok, t} -> t end)}
        error -> error
      end
    end)
  end

  ## Entities

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

  ## Variables

  @doc """
  Lists variables for a project with optional filtering.

  ## Options

    * `:category` - Filter by category
    * `:type` - Filter by variable type

  """
  def list_variables(project_id, opts \\ []) do
    query = from(v in Variable, where: v.project_id == ^project_id)

    query =
      case Keyword.get(opts, :category) do
        nil -> query
        category -> where(query, [v], v.category == ^category)
      end

    query =
      case Keyword.get(opts, :type) do
        nil -> query
        type -> where(query, [v], v.type == ^type)
      end

    query
    |> order_by([v], asc: v.category, asc: v.name)
    |> Repo.all()
  end

  @doc """
  Gets a single variable by ID within a project.

  Returns `nil` if the variable doesn't exist or doesn't belong to the project.
  """
  def get_variable(project_id, variable_id) do
    Variable
    |> where(project_id: ^project_id, id: ^variable_id)
    |> Repo.one()
  end

  @doc """
  Gets a single variable by ID within a project.

  Raises `Ecto.NoResultsError` if not found.
  """
  def get_variable!(project_id, variable_id) do
    Variable
    |> where(project_id: ^project_id, id: ^variable_id)
    |> Repo.one!()
  end

  @doc """
  Creates a variable.
  """
  def create_variable(%Project{} = project, attrs) do
    %Variable{project_id: project.id}
    |> Variable.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a variable.
  """
  def update_variable(%Variable{} = variable, attrs) do
    variable
    |> Variable.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a variable.
  """
  def delete_variable(%Variable{} = variable) do
    Repo.delete(variable)
  end

  @doc """
  Returns a changeset for tracking variable changes.
  """
  def change_variable(%Variable{} = variable, attrs \\ %{}) do
    Variable.update_changeset(variable, attrs)
  end

  @doc """
  Lists all unique categories for variables in a project.
  """
  def list_variable_categories(project_id) do
    from(v in Variable,
      where: v.project_id == ^project_id,
      where: not is_nil(v.category),
      where: v.category != "",
      distinct: true,
      select: v.category,
      order_by: v.category
    )
    |> Repo.all()
  end
end

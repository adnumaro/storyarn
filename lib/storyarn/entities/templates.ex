defmodule Storyarn.Entities.Templates do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Entities.EntityTemplate
  alias Storyarn.Projects.Project
  alias Storyarn.Repo

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
end

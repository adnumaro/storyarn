defmodule Storyarn.Entities.Variables do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Entities.Variable
  alias Storyarn.Projects.Project
  alias Storyarn.Repo

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

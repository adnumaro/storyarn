defmodule Storyarn.EntitiesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Storyarn.Entities` context.
  """

  alias Storyarn.Entities
  alias Storyarn.ProjectsFixtures

  def unique_template_name, do: "Template #{System.unique_integer([:positive])}"
  def unique_entity_name, do: "Entity #{System.unique_integer([:positive])}"
  def unique_variable_name, do: "var_#{System.unique_integer([:positive])}"

  def valid_template_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: unique_template_name(),
      type: "character",
      description: "A test template",
      color: "#3b82f6",
      icon: "hero-user"
    })
  end

  def valid_entity_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      display_name: unique_entity_name(),
      description: "A test entity",
      data: %{}
    })
  end

  def valid_variable_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: unique_variable_name(),
      type: "boolean",
      default_value: "false",
      description: "A test variable",
      category: "test"
    })
  end

  @doc """
  Creates an entity template.
  """
  def template_fixture(project \\ nil, attrs \\ %{}) do
    project = project || ProjectsFixtures.project_fixture()

    {:ok, template} =
      attrs
      |> valid_template_attributes()
      |> then(&Entities.create_template(project, &1))

    template
  end

  @doc """
  Creates an entity.
  """
  def entity_fixture(project \\ nil, template \\ nil, attrs \\ %{}) do
    project = project || ProjectsFixtures.project_fixture()
    template = template || template_fixture(project)

    {:ok, entity} =
      attrs
      |> valid_entity_attributes()
      |> then(&Entities.create_entity(project, template, &1))

    entity
  end

  @doc """
  Creates a variable.
  """
  def variable_fixture(project \\ nil, attrs \\ %{}) do
    project = project || ProjectsFixtures.project_fixture()

    {:ok, variable} =
      attrs
      |> valid_variable_attributes()
      |> then(&Entities.create_variable(project, &1))

    variable
  end
end

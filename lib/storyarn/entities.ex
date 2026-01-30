defmodule Storyarn.Entities do
  @moduledoc """
  The Entities context.

  Handles entity templates, entities (characters, locations, items), and variables
  within a project.

  This module serves as a facade, delegating to specialized submodules:
  - `Templates` - Template CRUD operations
  - `TemplateSchema` - Schema field management
  - `EntityCrud` - Entity CRUD operations
  - `Variables` - Variable CRUD operations
  """

  alias Storyarn.Entities.{EntityCrud, Templates, TemplateSchema, Variables}

  # =============================================================================
  # Entity Templates
  # =============================================================================

  @doc """
  Lists all templates for a project.
  """
  defdelegate list_templates(project_id), to: Templates

  @doc """
  Lists templates for a project, optionally filtered by type.
  """
  defdelegate list_templates(project_id, opts), to: Templates

  @doc """
  Gets a single template by ID within a project.

  Returns `nil` if the template doesn't exist or doesn't belong to the project.
  """
  defdelegate get_template(project_id, template_id), to: Templates

  @doc """
  Gets a single template by ID within a project.

  Raises `Ecto.NoResultsError` if not found.
  """
  defdelegate get_template!(project_id, template_id), to: Templates

  @doc """
  Creates an entity template.
  """
  defdelegate create_template(project, attrs), to: Templates

  @doc """
  Updates an entity template.
  """
  defdelegate update_template(template, attrs), to: Templates

  @doc """
  Deletes an entity template.

  Will fail if entities exist using this template.
  """
  defdelegate delete_template(template), to: Templates

  @doc """
  Returns a changeset for tracking template changes.
  """
  defdelegate change_template(template, attrs \\ %{}), to: Templates

  @doc """
  Creates default templates for a project (one for each type).
  """
  defdelegate create_default_templates(project), to: Templates

  # =============================================================================
  # Template Schema Management
  # =============================================================================

  @doc """
  Adds a field to a template's schema.

  Returns `{:ok, template}` on success, `{:error, reason}` on failure.
  """
  defdelegate add_schema_field(template, field_attrs), to: TemplateSchema

  @doc """
  Updates a field in a template's schema by name.

  Returns `{:ok, template}` on success, `{:error, reason}` on failure.
  """
  defdelegate update_schema_field(template, field_name, field_attrs), to: TemplateSchema

  @doc """
  Removes a field from a template's schema by name.

  Returns `{:ok, template}` on success.
  """
  defdelegate remove_schema_field(template, field_name), to: TemplateSchema

  @doc """
  Reorders schema fields by a list of field names.

  The `field_names` list should contain all field names in the desired order.
  Returns `{:ok, template}` on success, `{:error, reason}` on failure.
  """
  defdelegate reorder_schema_fields(template, field_names), to: TemplateSchema

  # =============================================================================
  # Entities
  # =============================================================================

  @doc """
  Lists entities for a project with optional filtering.

  ## Options

    * `:template_id` - Filter by template ID
    * `:type` - Filter by entity type (via template)
    * `:search` - Search by display_name or technical_name

  """
  defdelegate list_entities(project_id, opts \\ []), to: EntityCrud

  @doc """
  Gets a single entity by ID within a project.

  Returns `nil` if the entity doesn't exist or doesn't belong to the project.
  """
  defdelegate get_entity(project_id, entity_id), to: EntityCrud

  @doc """
  Gets a single entity by ID within a project.

  Raises `Ecto.NoResultsError` if not found.
  """
  defdelegate get_entity!(project_id, entity_id), to: EntityCrud

  @doc """
  Creates an entity from a template.
  """
  defdelegate create_entity(project, template, attrs), to: EntityCrud

  @doc """
  Updates an entity.
  """
  defdelegate update_entity(entity, attrs), to: EntityCrud

  @doc """
  Deletes an entity.
  """
  defdelegate delete_entity(entity), to: EntityCrud

  @doc """
  Returns a changeset for tracking entity changes.
  """
  defdelegate change_entity(entity, attrs \\ %{}), to: EntityCrud

  @doc """
  Counts entities by template.

  Returns a map of template_id => count.
  """
  defdelegate count_entities_by_template(project_id), to: EntityCrud

  # =============================================================================
  # Variables
  # =============================================================================

  @doc """
  Lists variables for a project with optional filtering.

  ## Options

    * `:category` - Filter by category
    * `:type` - Filter by variable type

  """
  defdelegate list_variables(project_id, opts \\ []), to: Variables

  @doc """
  Gets a single variable by ID within a project.

  Returns `nil` if the variable doesn't exist or doesn't belong to the project.
  """
  defdelegate get_variable(project_id, variable_id), to: Variables

  @doc """
  Gets a single variable by ID within a project.

  Raises `Ecto.NoResultsError` if not found.
  """
  defdelegate get_variable!(project_id, variable_id), to: Variables

  @doc """
  Creates a variable.
  """
  defdelegate create_variable(project, attrs), to: Variables

  @doc """
  Updates a variable.
  """
  defdelegate update_variable(variable, attrs), to: Variables

  @doc """
  Deletes a variable.
  """
  defdelegate delete_variable(variable), to: Variables

  @doc """
  Returns a changeset for tracking variable changes.
  """
  defdelegate change_variable(variable, attrs \\ %{}), to: Variables

  @doc """
  Lists all unique categories for variables in a project.
  """
  defdelegate list_variable_categories(project_id), to: Variables
end

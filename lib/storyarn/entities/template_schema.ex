defmodule Storyarn.Entities.TemplateSchema do
  @moduledoc false

  alias Storyarn.Entities.{EntityTemplate, Templates}

  @doc """
  Adds a field to a template's schema.

  Returns `{:ok, template}` on success, `{:error, reason}` on failure.
  """
  def add_schema_field(%EntityTemplate{} = template, field_attrs) do
    field = EntityTemplate.build_field(field_attrs)

    case EntityTemplate.validate_schema_field(field) do
      :ok ->
        new_schema = (template.schema || []) ++ [field]

        case EntityTemplate.validate_schema(new_schema) do
          :ok -> Templates.update_template(template, %{schema: new_schema})
          error -> error
        end

      error ->
        error
    end
  end

  @doc """
  Updates a field in a template's schema by name.

  Returns `{:ok, template}` on success, `{:error, reason}` on failure.
  """
  def update_schema_field(%EntityTemplate{} = template, field_name, field_attrs) do
    schema = template.schema || []

    with {:ok, index} <- find_field_index(schema, field_name),
         updated_field <- merge_field_attrs(schema, index, field_attrs),
         :ok <- EntityTemplate.validate_schema_field(updated_field),
         new_schema <- List.replace_at(schema, index, updated_field),
         :ok <- EntityTemplate.validate_schema(new_schema) do
      Templates.update_template(template, %{schema: new_schema})
    end
  end

  @doc """
  Removes a field from a template's schema by name.

  Returns `{:ok, template}` on success.
  """
  def remove_schema_field(%EntityTemplate{} = template, field_name) do
    schema = template.schema || []
    new_schema = Enum.reject(schema, fn f -> Map.get(f, "name") == field_name end)

    if length(new_schema) == length(schema) do
      {:error, "field not found"}
    else
      Templates.update_template(template, %{schema: new_schema})
    end
  end

  @doc """
  Reorders schema fields by a list of field names.

  The `field_names` list should contain all field names in the desired order.
  Returns `{:ok, template}` on success, `{:error, reason}` on failure.
  """
  def reorder_schema_fields(%EntityTemplate{} = template, field_names)
      when is_list(field_names) do
    schema = template.schema || []

    with :ok <- validate_field_names_match(schema, field_names) do
      new_schema = reorder_by_names(schema, field_names)
      Templates.update_template(template, %{schema: new_schema})
    end
  end

  # Private helpers

  defp find_field_index(schema, field_name) do
    case Enum.find_index(schema, fn f -> Map.get(f, "name") == field_name end) do
      nil -> {:error, "field not found"}
      index -> {:ok, index}
    end
  end

  defp merge_field_attrs(schema, index, field_attrs) do
    existing_field = Enum.at(schema, index)
    Map.merge(existing_field, field_attrs)
  end

  defp validate_field_names_match(schema, field_names) do
    current_names = Enum.map(schema, &Map.get(&1, "name"))

    if Enum.sort(field_names) == Enum.sort(current_names) do
      :ok
    else
      {:error, "field names don't match existing fields"}
    end
  end

  defp reorder_by_names(schema, field_names) do
    Enum.map(field_names, fn name ->
      Enum.find(schema, fn f -> Map.get(f, "name") == name end)
    end)
  end
end

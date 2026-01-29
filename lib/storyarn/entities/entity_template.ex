defmodule Storyarn.Entities.EntityTemplate do
  @moduledoc """
  Schema for entity templates.

  An entity template defines the structure and custom fields for a type of entity
  (character, location, item, or custom). Templates belong to a project and
  entities are created from them.

  ## Schema Field Format

  The `schema` field is an array of field definitions, each with:
    - `name` - Field name (snake_case, required)
    - `type` - Field type (string, text, integer, boolean, select, asset_reference)
    - `label` - Display label (required)
    - `required` - Whether the field is required (default: false)
    - `default` - Default value
    - `description` - Field description
    - `options` - Options for select type (list of strings)

  Example:
      [
        %{"name" => "age", "type" => "integer", "label" => "Age", "required" => true},
        %{"name" => "bio", "type" => "text", "label" => "Biography", "required" => false}
      ]
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Entities.Entity
  alias Storyarn.Projects.Project

  @types ~w(character location item custom)

  @field_types ~w(string text integer boolean select asset_reference)

  @default_colors %{
    "character" => "#3b82f6",
    "location" => "#22c55e",
    "item" => "#f59e0b",
    "custom" => "#8b5cf6"
  }

  @default_icons %{
    "character" => "hero-user",
    "location" => "hero-map-pin",
    "item" => "hero-cube",
    "custom" => "hero-puzzle-piece"
  }

  schema "entity_templates" do
    field :name, :string
    field :type, :string
    field :description, :string
    field :color, :string
    field :icon, :string
    field :schema, {:array, :map}, default: []
    field :is_default, :boolean, default: false

    belongs_to :project, Project
    has_many :entities, Entity, foreign_key: :template_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Returns the list of valid entity types.
  """
  def types, do: @types

  @doc """
  Returns the list of valid field types for schema fields.
  """
  def field_types, do: @field_types

  @doc """
  Returns the default color for an entity type.
  """
  def default_color(type), do: Map.get(@default_colors, type, "#6b7280")

  @doc """
  Returns the default icon for an entity type.
  """
  def default_icon(type), do: Map.get(@default_icons, type, "hero-puzzle-piece")

  @doc """
  Validates a single schema field definition.

  Returns `:ok` if valid, `{:error, reason}` if invalid.
  """
  def validate_schema_field(field) when is_map(field) do
    with :ok <- validate_field_name(field),
         :ok <- validate_field_type(field),
         :ok <- validate_field_label(field) do
      validate_field_options(field)
    end
  end

  def validate_schema_field(_), do: {:error, "field must be a map"}

  defp validate_field_name(%{"name" => name}) when is_binary(name) do
    if Regex.match?(~r/^[a-z][a-z0-9_]*$/, name) do
      :ok
    else
      {:error, "name must be snake_case starting with a letter"}
    end
  end

  defp validate_field_name(_), do: {:error, "name is required and must be a string"}

  defp validate_field_type(%{"type" => type}) when type in @field_types, do: :ok
  defp validate_field_type(%{"type" => _}), do: {:error, "invalid field type"}
  defp validate_field_type(_), do: {:error, "type is required"}

  defp validate_field_label(%{"label" => label}) when is_binary(label) and label != "", do: :ok
  defp validate_field_label(_), do: {:error, "label is required and must be a non-empty string"}

  defp validate_field_options(%{"type" => "select", "options" => [_ | _] = options}) do
    if Enum.all?(options, &is_binary/1) do
      :ok
    else
      {:error, "select type requires at least one string option"}
    end
  end

  defp validate_field_options(%{"type" => "select", "options" => []}) do
    {:error, "select type requires at least one string option"}
  end

  defp validate_field_options(%{"type" => "select"}),
    do: {:error, "select type requires options"}

  defp validate_field_options(_), do: :ok

  @doc """
  Validates an entire schema (array of field definitions).

  Returns `:ok` if all fields are valid, `{:error, reason}` for the first invalid field.
  """
  def validate_schema(schema) when is_list(schema) do
    with :ok <- validate_no_duplicate_names(schema) do
      validate_all_fields(schema)
    end
  end

  def validate_schema(_), do: {:error, "schema must be a list"}

  defp validate_no_duplicate_names(schema) do
    names = Enum.map(schema, &Map.get(&1, "name"))

    if names == Enum.uniq(names) do
      :ok
    else
      {:error, "duplicate field names are not allowed"}
    end
  end

  defp validate_all_fields(schema) do
    Enum.reduce_while(schema, :ok, fn field, :ok ->
      case validate_schema_field(field) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  @doc """
  Builds a new schema field with defaults.
  """
  def build_field(attrs \\ %{}) do
    %{
      "name" => Map.get(attrs, "name", ""),
      "type" => Map.get(attrs, "type", "string"),
      "label" => Map.get(attrs, "label", ""),
      "required" => Map.get(attrs, "required", false),
      "default" => Map.get(attrs, "default"),
      "description" => Map.get(attrs, "description"),
      "options" => Map.get(attrs, "options")
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc """
  Changeset for creating a new entity template.
  """
  def create_changeset(template, attrs) do
    template
    |> cast(attrs, [:name, :type, :description, :color, :icon, :schema, :is_default])
    |> validate_required([:name, :type])
    |> validate_inclusion(:type, @types)
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:description, max: 1000)
    |> set_defaults()
    |> unique_constraint([:project_id, :name], error_key: :name)
  end

  @doc """
  Changeset for updating an entity template.
  """
  def update_changeset(template, attrs) do
    template
    |> cast(attrs, [:name, :description, :color, :icon, :schema, :is_default])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:description, max: 1000)
    |> unique_constraint([:project_id, :name], error_key: :name)
  end

  defp set_defaults(changeset) do
    type = get_field(changeset, :type)

    changeset
    |> maybe_set_default(:color, default_color(type))
    |> maybe_set_default(:icon, default_icon(type))
  end

  defp maybe_set_default(changeset, field, default) do
    case get_field(changeset, field) do
      nil -> put_change(changeset, field, default)
      "" -> put_change(changeset, field, default)
      _ -> changeset
    end
  end
end

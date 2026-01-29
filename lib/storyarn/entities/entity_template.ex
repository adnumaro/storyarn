defmodule Storyarn.Entities.EntityTemplate do
  @moduledoc """
  Schema for entity templates.

  An entity template defines the structure and custom fields for a type of entity
  (character, location, item, or custom). Templates belong to a project and
  entities are created from them.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Entities.Entity
  alias Storyarn.Projects.Project

  @types ~w(character location item custom)

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
    field :schema, :map, default: %{}
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
  Returns the default color for an entity type.
  """
  def default_color(type), do: Map.get(@default_colors, type, "#6b7280")

  @doc """
  Returns the default icon for an entity type.
  """
  def default_icon(type), do: Map.get(@default_icons, type, "hero-puzzle-piece")

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

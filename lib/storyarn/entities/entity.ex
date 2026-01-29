defmodule Storyarn.Entities.Entity do
  @moduledoc """
  Schema for entities.

  An entity represents a character, location, item, or custom object in a project.
  Entities are created from templates and store their custom data in a JSONB field.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Entities.EntityTemplate
  alias Storyarn.Projects.Project

  @technical_name_format ~r/^[a-z][a-z0-9_]*$/

  schema "entities" do
    field :display_name, :string
    field :technical_name, :string
    field :color, :string
    field :description, :string
    field :data, :map, default: %{}

    belongs_to :project, Project
    belongs_to :template, EntityTemplate

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new entity.
  """
  def create_changeset(entity, attrs) do
    entity
    |> cast(attrs, [:display_name, :technical_name, :color, :description, :data])
    |> validate_required([:display_name])
    |> maybe_generate_technical_name()
    |> validate_required([:technical_name])
    |> validate_technical_name()
    |> validate_length(:display_name, min: 1, max: 200)
    |> validate_length(:description, max: 2000)
    |> unique_constraint([:project_id, :technical_name], error_key: :technical_name)
  end

  @doc """
  Changeset for updating an entity.
  """
  def update_changeset(entity, attrs) do
    entity
    |> cast(attrs, [:display_name, :technical_name, :color, :description, :data])
    |> validate_required([:display_name, :technical_name])
    |> validate_technical_name()
    |> validate_length(:display_name, min: 1, max: 200)
    |> validate_length(:description, max: 2000)
    |> unique_constraint([:project_id, :technical_name], error_key: :technical_name)
  end

  @doc """
  Generates a technical name from a display name.

  ## Examples

      iex> generate_technical_name("John Doe")
      "john_doe"

      iex> generate_technical_name("My Cool Item!")
      "my_cool_item"
  """
  def generate_technical_name(display_name) when is_binary(display_name) do
    display_name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.replace(~r/^_+|_+$/, "")
    |> ensure_starts_with_letter()
  end

  def generate_technical_name(_), do: ""

  defp ensure_starts_with_letter(""), do: ""

  defp ensure_starts_with_letter(<<first, _rest::binary>> = name) when first in ?a..?z do
    name
  end

  defp ensure_starts_with_letter(name), do: "entity_" <> name

  defp maybe_generate_technical_name(changeset) do
    case get_field(changeset, :technical_name) do
      nil ->
        display_name = get_field(changeset, :display_name)
        put_change(changeset, :technical_name, generate_technical_name(display_name))

      "" ->
        display_name = get_field(changeset, :display_name)
        put_change(changeset, :technical_name, generate_technical_name(display_name))

      _ ->
        changeset
    end
  end

  defp validate_technical_name(changeset) do
    changeset
    |> validate_format(:technical_name, @technical_name_format,
      message:
        "must start with a letter and contain only lowercase letters, numbers, and underscores"
    )
    |> validate_length(:technical_name, min: 1, max: 100)
  end
end

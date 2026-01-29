defmodule Storyarn.Entities.Variable do
  @moduledoc """
  Schema for variables.

  Variables are project-wide state that can be used in flows and conditions.
  They have a type (boolean, integer, float, string) and a default value.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Projects.Project

  @types ~w(boolean integer float string)
  @name_format ~r/^[a-z][a-z0-9_]*$/

  schema "variables" do
    field :name, :string
    field :type, :string
    field :default_value, :string
    field :description, :string
    field :category, :string

    belongs_to :project, Project

    timestamps(type: :utc_datetime)
  end

  @doc """
  Returns the list of valid variable types.
  """
  def types, do: @types

  @doc """
  Returns the default value for a variable type.
  """
  def default_for_type("boolean"), do: "false"
  def default_for_type("integer"), do: "0"
  def default_for_type("float"), do: "0.0"
  def default_for_type("string"), do: ""
  def default_for_type(_), do: ""

  @doc """
  Parses and validates a value for the given type.

  Returns `{:ok, value}` if valid, `{:error, message}` otherwise.
  """
  def parse_value("boolean", value) when value in ["true", "false"], do: {:ok, value}
  def parse_value("boolean", _), do: {:error, "must be 'true' or 'false'"}

  def parse_value("integer", value) do
    case Integer.parse(value) do
      {_int, ""} -> {:ok, value}
      _ -> {:error, "must be a valid integer"}
    end
  end

  def parse_value("float", value) do
    case Float.parse(value) do
      {_float, ""} -> {:ok, value}
      _ -> {:error, "must be a valid float"}
    end
  end

  def parse_value("string", value), do: {:ok, value}
  def parse_value(_, _), do: {:error, "unknown type"}

  @doc """
  Changeset for creating a new variable.
  """
  def create_changeset(variable, attrs) do
    variable
    |> cast(attrs, [:name, :type, :default_value, :description, :category])
    |> validate_required([:name, :type])
    |> validate_inclusion(:type, @types)
    |> validate_format(:name, @name_format,
      message:
        "must start with a letter and contain only lowercase letters, numbers, and underscores"
    )
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:description, max: 1000)
    |> validate_length(:category, max: 50)
    |> set_default_value()
    |> validate_default_value()
    |> unique_constraint([:project_id, :name], error_key: :name)
  end

  @doc """
  Changeset for updating a variable.
  """
  def update_changeset(variable, attrs) do
    variable
    |> cast(attrs, [:name, :default_value, :description, :category])
    |> validate_required([:name])
    |> validate_format(:name, @name_format,
      message:
        "must start with a letter and contain only lowercase letters, numbers, and underscores"
    )
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:description, max: 1000)
    |> validate_length(:category, max: 50)
    |> validate_default_value()
    |> unique_constraint([:project_id, :name], error_key: :name)
  end

  defp set_default_value(changeset) do
    type = get_field(changeset, :type)
    default = get_field(changeset, :default_value)

    if is_nil(default) or default == "" do
      put_change(changeset, :default_value, default_for_type(type))
    else
      changeset
    end
  end

  defp validate_default_value(changeset) do
    type = get_field(changeset, :type)
    default = get_field(changeset, :default_value)

    if type && default do
      case parse_value(type, default) do
        {:ok, _} -> changeset
        {:error, message} -> add_error(changeset, :default_value, message)
      end
    else
      changeset
    end
  end
end

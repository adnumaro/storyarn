defmodule Storyarn.Flows.Flow do
  @moduledoc """
  Schema for flows.

  A flow is a visual graph representing narrative structure, dialogue trees,
  or game logic. Each flow belongs to a project and contains nodes and connections.

  Flows are organized in a tree structure with:
  - `parent_id` - FK to parent flow (nil for root level)
  - `position` - Order among siblings
  - `description` - Rich text for annotations
  - `deleted_at` - Soft delete support

  Any flow can have children AND content (nodes). The UI adapts based on what
  the flow contains.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Association.NotLoaded
  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Platform.Shared.TimeHelpers

  @shortcut_format ~r/^[a-z0-9][a-z0-9.\-]*[a-z0-9]$|^[a-z0-9]$/

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          shortcut: String.t() | nil,
          description: String.t() | nil,
          position: integer() | nil,
          is_main: boolean(),
          settings: map(),
          scene_id: integer() | nil,
          project_id: integer() | nil,
          parent_id: integer() | nil,
          parent: t() | NotLoaded.t() | nil,
          children: [t()] | NotLoaded.t(),
          nodes: [FlowNode.t()] | NotLoaded.t(),
          connections: [FlowConnection.t()] | NotLoaded.t(),
          current_version_id: integer() | nil,
          deleted_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "flows" do
    field :name, :string
    field :shortcut, :string
    field :description, :string
    field :position, :integer, default: 0
    field :is_main, :boolean, default: false
    field :settings, :map, default: %{}
    field :project_id, :id
    field :scene_id, :id
    field :current_version_id, :id
    field :deleted_at, :utc_datetime

    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, foreign_key: :parent_id
    has_many :nodes, FlowNode
    has_many :connections, FlowConnection

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new flow.
  """
  def create_changeset(flow, attrs) do
    flow
    |> cast(attrs, [
      :name,
      :shortcut,
      :description,
      :is_main,
      :settings,
      :parent_id,
      :position,
      :scene_id
    ])
    |> validate_core_fields()
    |> validate_description()
    |> validate_shortcut()
    |> validate_single_main_flow()
    |> foreign_key_constraint(:parent_id)
    |> foreign_key_constraint(:scene_id)
  end

  @doc """
  Changeset for updating a flow.
  """
  def update_changeset(flow, attrs) do
    flow
    |> cast(attrs, [
      :name,
      :shortcut,
      :description,
      :is_main,
      :settings,
      :parent_id,
      :position,
      :scene_id
    ])
    |> validate_core_fields()
    |> validate_description()
    |> validate_shortcut()
    |> validate_single_main_flow()
    |> foreign_key_constraint(:parent_id)
    |> foreign_key_constraint(:scene_id)
  end

  @doc """
  Changeset for updating the scene reference.
  """
  def scene_changeset(flow, attrs) do
    flow
    |> cast(attrs, [:scene_id])
    |> foreign_key_constraint(:scene_id)
  end

  @doc """
  Changeset for moving a flow (changing parent or position).
  """
  def move_changeset(flow, attrs) do
    flow
    |> cast(attrs, [:parent_id, :position])
    |> foreign_key_constraint(:parent_id)
  end

  @doc """
  Changeset for soft deleting a flow.
  """
  def delete_changeset(flow), do: change(flow, %{deleted_at: TimeHelpers.now()})

  @doc """
  Changeset for restoring a soft-deleted flow.
  """
  def restore_changeset(flow), do: change(flow, %{deleted_at: nil})

  @doc """
  Changeset for updating the current version pointer.
  """
  def version_changeset(flow, attrs) do
    flow
    |> cast(attrs, [:current_version_id])
    |> foreign_key_constraint(:current_version_id)
  end

  @doc """
  Returns true if the flow is soft-deleted.
  """
  def deleted?(%__MODULE__{deleted_at: deleted_at}), do: not is_nil(deleted_at)

  # Private functions

  # `flows_project_id_is_main_index` is a partial unique index over active
  # `(project_id, is_main)` rows where `is_main = true`. Without a matching
  # `unique_constraint` the database raises `Ecto.ConstraintError` instead of
  # returning a changeset error — which is how a second import into a project
  # that already had a main flow produced a raw 500 with no usable message.
  defp validate_single_main_flow(changeset) do
    unique_constraint(changeset, :is_main,
      name: :flows_project_id_is_main_index,
      message: "this project already has a main flow"
    )
  end

  defp validate_shortcut(changeset) do
    changeset
    |> validate_length(:shortcut, min: 1, max: 50)
    |> validate_format(:shortcut, @shortcut_format,
      message: "must be lowercase, alphanumeric, with dots or hyphens (e.g., chapter-1)"
    )
    |> unique_constraint(:shortcut,
      name: :flows_project_shortcut_unique,
      message: "is already taken in this project"
    )
  end

  defp validate_core_fields(changeset) do
    changeset
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 200)
  end

  defp validate_description(changeset), do: validate_length(changeset, :description, max: 2000)
end

defmodule Storyarn.Drafts.Draft do
  @moduledoc """
  Schema for drafts.

  A draft is a private copy of a flow, sheet, or scene for experimentation.
  Only the creator can see and edit their drafts. The cloned entity is linked
  back to this draft record via `draft_id` on the entity table.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Accounts.User
  alias Storyarn.Projects.Project
  alias Storyarn.Shared.TimeHelpers

  @type t :: %__MODULE__{
          id: integer() | nil,
          entity_type: String.t() | nil,
          source_entity_id: integer() | nil,
          source_version_number: integer() | nil,
          name: String.t() | nil,
          status: String.t(),
          merged_at: DateTime.t() | nil,
          last_edited_at: DateTime.t() | nil,
          baseline_entity_ids: map(),
          source_name: String.t() | nil,
          project_id: integer() | nil,
          project: Project.t() | Ecto.Association.NotLoaded.t() | nil,
          created_by_id: integer() | nil,
          created_by: User.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @valid_entity_types ~w(sheet flow scene)

  schema "drafts" do
    field :entity_type, :string
    field :source_entity_id, :integer
    field :source_version_number, :integer
    field :name, :string
    field :status, :string, default: "active"
    field :merged_at, :utc_datetime
    field :last_edited_at, :utc_datetime
    field :baseline_entity_ids, :map, default: %{}
    field :source_name, :string, virtual: true

    belongs_to :project, Project
    belongs_to :created_by, User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new draft.
  """
  def create_changeset(draft, attrs) do
    draft
    |> cast(attrs, [:entity_type, :source_entity_id, :source_version_number, :name])
    |> validate_required([:entity_type, :source_entity_id, :name])
    |> validate_inclusion(:entity_type, @valid_entity_types)
    |> validate_length(:name, min: 1, max: 200)
    |> put_change(:last_edited_at, TimeHelpers.now())
  end

  @doc """
  Changeset for renaming a draft.
  """
  def rename_changeset(draft, attrs) do
    draft
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 200)
  end

  @doc """
  Changeset for discarding a draft.
  """
  def discard_changeset(draft) do
    draft
    |> change(%{status: "discarded"})
  end

  @doc """
  Changeset for marking a draft as merged.
  Only valid when current status is "active".
  """
  def merge_changeset(%__MODULE__{status: "active"} = draft) do
    {:ok,
     draft
     |> change(%{status: "merged", merged_at: TimeHelpers.now()})}
  end

  def merge_changeset(%__MODULE__{}), do: {:error, :not_active}
end

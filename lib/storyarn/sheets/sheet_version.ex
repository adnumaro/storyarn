defmodule Storyarn.Sheets.SheetVersion do
  @moduledoc """
  Schema for sheet version history.

  Each version is a snapshot of a sheet's state at a point in time,
  including its name, shortcut, avatar, banner, and all blocks.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Accounts.User
  alias Storyarn.Sheets.Sheet

  @type t :: %__MODULE__{
          id: integer() | nil,
          version_number: integer(),
          title: String.t() | nil,
          description: String.t() | nil,
          snapshot: map(),
          change_summary: String.t() | nil,
          sheet_id: integer() | nil,
          sheet: Sheet.t() | Ecto.Association.NotLoaded.t() | nil,
          changed_by_id: integer() | nil,
          changed_by: User.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "sheet_versions" do
    field :version_number, :integer
    field :title, :string
    field :description, :string
    field :snapshot, :map
    field :change_summary, :string

    belongs_to :sheet, Sheet
    belongs_to :changed_by, User

    timestamps(updated_at: false)
  end

  @doc """
  Changeset for creating a new sheet version.
  """
  def changeset(version, attrs) do
    version
    |> cast(attrs, [
      :version_number,
      :title,
      :description,
      :snapshot,
      :change_summary,
      :sheet_id,
      :changed_by_id
    ])
    |> validate_required([:version_number, :snapshot, :sheet_id])
    |> validate_length(:title, max: 255)
    |> foreign_key_constraint(:sheet_id)
    |> foreign_key_constraint(:changed_by_id)
    |> unique_constraint([:sheet_id, :version_number], name: :sheet_versions_sheet_version_unique)
  end
end

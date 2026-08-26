defmodule Storyarn.Sheets.Editor.Data.ProjectRecord do
  @moduledoc """
  Project state required by Sheet editor transactions and associations.

  This consumer-local projection protects Sheet creation, movement, and
  automatic version decisions without importing the Projects domain model.
  """

  use Ecto.Schema

  alias Storyarn.Sheets.Editor.Data.WorkspaceRecord

  @type t :: %__MODULE__{}

  schema "projects" do
    field :name, :string
    field :slug, :string
    field :settings, :map, default: %{}
    field :auto_version_sheets, :boolean, default: true
    belongs_to :workspace, WorkspaceRecord
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end

defmodule Storyarn.Sheets.AI.Projections.SheetRecord do
  @moduledoc """
  AI-owned read model of a Sheet context subject or referenced Sheet.

  It projects only the authored metadata and lifecycle fields required to build
  deterministic context packages and acquire source locks.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "sheets" do
    field :name, :string
    field :shortcut, :string
    field :description, :string
    field :project_id, :id
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end

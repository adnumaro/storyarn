defmodule Storyarn.Sheets.Editor.Data.SceneRecord do
  @moduledoc """
  Minimal Scene projection used to count the shared project-item entitlement.

  The Sheet editor reads this foreign fact but never writes Scene state.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "scenes" do
    field :name, :string
    field :project_id, :id
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end

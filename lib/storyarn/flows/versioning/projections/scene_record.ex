defmodule Storyarn.Flows.Versioning.Projections.SceneRecord do
  @moduledoc """
  Versioning-owned Scene identity projection used to validate Flow snapshot references.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "scenes" do
    field :project_id, :id
    field :deleted_at, :utc_datetime
  end
end

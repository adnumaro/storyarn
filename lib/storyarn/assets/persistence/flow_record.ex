defmodule Storyarn.Assets.Persistence.FlowRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "flows" do
    field :name, :string
    field :project_id, :id
    field :deleted_at, :utc_datetime
  end
end

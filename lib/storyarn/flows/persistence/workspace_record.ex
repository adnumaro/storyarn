defmodule Storyarn.Flows.Persistence.WorkspaceRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "workspaces" do
    timestamps(type: :utc_datetime)
  end
end

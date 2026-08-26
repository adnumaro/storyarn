defmodule Storyarn.Flows.Versioning.Data.WorkspaceRecord do
  @moduledoc """
  Versioning-owned Workspace identity projection used for locking and storage accounting.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "workspaces" do
    timestamps(type: :utc_datetime)
  end
end

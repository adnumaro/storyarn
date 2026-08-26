defmodule Storyarn.AI.Operations.Data.WorkspaceRecord do
  @moduledoc "Consumer-local Workspace identity referenced by AI operations, results, and alerts."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "workspaces" do
    field :name, :string
    field :slug, :string
    field :source_locale, :string, default: "en"
    field :owner_id, :id

    timestamps(type: :utc_datetime)
  end
end

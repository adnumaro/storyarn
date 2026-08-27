defmodule Storyarn.AI.Routing.Projections.WorkspaceRecord do
  @moduledoc "Consumer-local Workspace identity used to bind an AI route option."

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

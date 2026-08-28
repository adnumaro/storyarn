defmodule Storyarn.AI.Governance.Projections.WorkspaceRecord do
  @moduledoc "Governance-owned projection of workspace identity needed by AI policy workflows."

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

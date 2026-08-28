defmodule Storyarn.Localization.Texts.Projections.WorkspaceRecord do
  @moduledoc """
  Consumer-local Workspace projection reachable through a Texts project preload.

  It is passive association data with no persistence behavior. Workspace
  lifecycle and ordinary writes remain owned by Workspaces.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          slug: String.t() | nil,
          source_locale: String.t() | nil
        }

  schema "workspaces" do
    field :name, :string
    field :slug, :string
    field :source_locale, :string
    timestamps(type: :utc_datetime)
  end
end

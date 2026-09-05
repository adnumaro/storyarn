defmodule Storyarn.Localization.Texts.Projections.FlowRecord do
  @moduledoc """
  Consumer-local Flow projection used to scope Texts queries to a project and
  to name the Flow a localized text was extracted from.

  It is passive data: Flow lifecycle and writes remain owned by Flows, and
  persistence I/O belongs to Texts commands or queries.
  """
  use Ecto.Schema

  schema "flows" do
    field :project_id, :id
    field :name, :string
    field :deleted_at, :utc_datetime
  end
end

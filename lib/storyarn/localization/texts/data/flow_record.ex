defmodule Storyarn.Localization.Texts.Data.FlowRecord do
  @moduledoc """
  Consumer-local Flow projection used to scope Texts queries to a project.

  It is passive data: Flow lifecycle and writes remain owned by Flows, and
  persistence I/O belongs to Texts commands or queries.
  """
  use Ecto.Schema

  schema "flows" do
    field :project_id, :id
    field :deleted_at, :utc_datetime
  end
end

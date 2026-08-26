defmodule Storyarn.Scenes.Editor.Data.FlowNodeRecord do
  @moduledoc """
  Editor-owned read projection used only to account for Flow nodes in the
  project-wide item entitlement.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "flow_nodes" do
    field :flow_id, :id
    field :deleted_at, :utc_datetime
  end
end

defmodule Storyarn.Localization.Texts.Projections.FlowNodeRecord do
  @moduledoc """
  Read-only projection of a Flow node used by Texts extraction and exports.

  It deliberately contains only runtime-localization fields and never owns Flow
  mutations.
  """
  use Ecto.Schema

  schema "flow_nodes" do
    field :type, :string
    field :data, :map, default: %{}
    field :word_count, :integer, default: 0
    field :flow_id, :id
    field :deleted_at, :utc_datetime
  end
end

defmodule Storyarn.Flows.SequenceVisualLayer do
  @moduledoc """
  A visual layer attached to a sequence flow node.

  Layers compose the Flow Player stage from the active sequence chain.
  Parent sequence layers render first; child sequence layers render above
  them. Geometry is normalized to the player stage so the same data can
  scale across viewports and later feed a 2D runtime.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Association.NotLoaded
  alias Storyarn.Assets.Asset
  alias Storyarn.Flows.FlowNode

  @kinds ~w(backdrop character prop overlay)
  @slots [
    "full",
    "left",
    "center",
    "right",
    "custom",
    "top-left",
    "top-center",
    "top-right",
    "middle-left",
    "middle-center",
    "middle-right",
    "bottom-left",
    "bottom-center",
    "bottom-right"
  ]
  @fits ~w(cover contain fill)

  @type t :: %__MODULE__{
          id: integer() | nil,
          flow_node_id: integer() | nil,
          flow_node: FlowNode.t() | NotLoaded.t() | nil,
          asset_id: integer() | nil,
          asset: Asset.t() | NotLoaded.t() | nil,
          kind: String.t() | nil,
          label: String.t() | nil,
          z_index: integer(),
          slot: String.t(),
          x: float(),
          y: float(),
          width: float(),
          height: float(),
          anchor_x: float(),
          anchor_y: float(),
          fit: String.t(),
          opacity: float(),
          visible: boolean(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "flow_node_sequence_visual_layers" do
    belongs_to :flow_node, FlowNode
    belongs_to :asset, Asset

    field :kind, :string
    field :label, :string
    field :z_index, :integer, default: 0
    field :slot, :string, default: "custom"

    field :x, :float, default: 0.0
    field :y, :float, default: 0.0
    field :width, :float, default: 1.0
    field :height, :float, default: 1.0
    field :anchor_x, :float, default: 0.0
    field :anchor_y, :float, default: 0.0

    field :fit, :string, default: "contain"
    field :opacity, :float, default: 1.0
    field :visible, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @doc "Returns valid visual layer kinds."
  @spec kinds() :: [String.t()]
  def kinds, do: @kinds

  @doc "Returns valid visual layer slots."
  @spec slots() :: [String.t()]
  def slots, do: @slots

  @doc "Returns valid visual layer fit modes."
  @spec fits() :: [String.t()]
  def fits, do: @fits

  def create_changeset(layer, attrs) do
    layer
    |> cast_layer(attrs)
    |> validate_required([:flow_node_id, :asset_id, :kind, :z_index, :slot, :fit])
    |> validate_layer()
    |> foreign_key_constraint(:flow_node_id)
    |> foreign_key_constraint(:asset_id)
  end

  def update_changeset(layer, attrs) do
    layer
    |> cast_layer(attrs)
    |> validate_layer()
    |> foreign_key_constraint(:asset_id)
  end

  defp cast_layer(layer, attrs) do
    cast(layer, attrs, [
      :flow_node_id,
      :asset_id,
      :kind,
      :label,
      :z_index,
      :slot,
      :x,
      :y,
      :width,
      :height,
      :anchor_x,
      :anchor_y,
      :fit,
      :opacity,
      :visible
    ])
  end

  defp validate_layer(changeset) do
    changeset
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:slot, @slots)
    |> validate_inclusion(:fit, @fits)
    |> validate_length(:label, max: 120)
    |> validate_normalized(:x)
    |> validate_normalized(:y)
    |> validate_normalized(:anchor_x)
    |> validate_normalized(:anchor_y)
    |> validate_number(:width, greater_than: 0, less_than_or_equal_to: 1)
    |> validate_number(:height, greater_than: 0, less_than_or_equal_to: 1)
    |> validate_normalized(:opacity)
  end

  defp validate_normalized(changeset, field) do
    validate_number(changeset, field, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
  end
end

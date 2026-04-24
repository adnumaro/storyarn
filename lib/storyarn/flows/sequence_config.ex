defmodule Storyarn.Flows.SequenceConfig do
  @moduledoc """
  Per-sequence configuration. 1:1 with `Storyarn.Flows.FlowNode` where
  `type='sequence'`.

  Sequences are flow_nodes rows with `type='sequence'`; this table holds
  the fields that are specific to sequences and don't apply to other node
  types:

    * `name` — display label.
    * `width` / `height` — container bounds on the canvas.
    * `background_asset_id` — image painted as the sequence backdrop
      during FlowPlay. Nullable when no backdrop is set. FK to
      `assets(id)` with `ON DELETE SET NULL`.
    * `background_position` — 9-value CSS-like enum (`top-left`,
      `top-center`, ..., `bottom-right`). Where to anchor the image
      inside the sequence canvas. Nullable; interpreted as `center`
      when absent.
    * `background_fit` — `cover` | `contain` | `fill`. CSS
      `background-size` analogue. Nullable; interpreted as `cover`.

  The `flow_node_id` is both the primary key and the foreign key to
  `flow_nodes(id)`. A DB trigger enforces that the referenced flow_node
  has `type='sequence'`.

  Audio tracks live in the separate `flow_node_sequence_tracks` table
  (schema `Storyarn.Flows.SequenceTrack`). See its moduledoc for
  rationale.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Association.NotLoaded
  alias Storyarn.Assets.Asset
  alias Storyarn.Flows.FlowNode

  @background_positions ~w(
    top-left top-center top-right
    center-left center center-right
    bottom-left bottom-center bottom-right
  )

  @background_fits ~w(cover contain fill)

  @type t :: %__MODULE__{
          flow_node_id: integer() | nil,
          flow_node: FlowNode.t() | NotLoaded.t() | nil,
          name: String.t() | nil,
          width: float(),
          height: float(),
          background_asset_id: integer() | nil,
          background_asset: Asset.t() | NotLoaded.t() | nil,
          background_position: String.t() | nil,
          background_fit: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key false
  schema "flow_node_sequence_configs" do
    belongs_to :flow_node, FlowNode, primary_key: true

    field :name, :string
    field :width, :float, default: 300.0
    field :height, :float, default: 200.0

    belongs_to :background_asset, Asset
    field :background_position, :string
    field :background_fit, :string

    timestamps(type: :utc_datetime)
  end

  @doc "Returns the 9 valid `background_position` values."
  @spec background_positions() :: [String.t()]
  def background_positions, do: @background_positions

  @doc "Returns the 3 valid `background_fit` values."
  @spec background_fits() :: [String.t()]
  def background_fits, do: @background_fits

  @doc """
  Changeset for creating a new sequence config. Media fields
  (background_asset_id, background_position, background_fit) can be
  seeded here but are optional — they're all nullable.
  """
  def create_changeset(sequence_config, attrs) do
    sequence_config
    |> cast(attrs, [
      :flow_node_id,
      :name,
      :width,
      :height,
      :background_asset_id,
      :background_position,
      :background_fit
    ])
    |> validate_required([:flow_node_id, :name])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_inclusion(:background_position, @background_positions)
    |> validate_inclusion(:background_fit, @background_fits)
    |> foreign_key_constraint(:flow_node_id)
    |> foreign_key_constraint(:background_asset_id)
  end

  @doc """
  Changeset for updating an existing sequence config. `flow_node_id` is
  immutable.
  """
  def update_changeset(sequence_config, attrs) do
    sequence_config
    |> cast(attrs, [
      :name,
      :width,
      :height,
      :background_asset_id,
      :background_position,
      :background_fit
    ])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_inclusion(:background_position, @background_positions)
    |> validate_inclusion(:background_fit, @background_fits)
    |> foreign_key_constraint(:background_asset_id)
  end
end

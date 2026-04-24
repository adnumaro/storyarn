defmodule Storyarn.Flows.SequenceTrack do
  @moduledoc """
  A single audio track attached to a sequence. N:1 with
  `Storyarn.Flows.FlowNode` where `type='sequence'`.

  Replaces the old `flow_sequences.tracks` jsonb (which was lost in
  phase 1 of the relational refactor). Three `kind` slots per sequence:

    * `background` — looping atmosphere layer. Typically the lowest
      in the mix.
    * `music` — melodic or rhythmic layer.
    * `ambient` — punctual or short-loop textures (footsteps, wind,
      etc.) that compose on top.

  When the FlowPlay runtime steps into a node whose ancestor chain
  includes multiple sequences, each kind mixes additively across
  layers (see `project_flow_sequences_scopes.md::Nesting + FlowPlay`).
  The resolver collects rows per kind walking the ancestor chain;
  inner tracks sit on top.

  A UNIQUE constraint on `(flow_node_id, kind)` enforces "3 slots per
  sequence" — one track row per kind. `position` exists for a future
  multi-layer extension; for now it's always 0 and the unique makes
  stacking impossible.

  `asset_id` is nullable because the DB-level row represents a slot
  that may hold a future asset; in practice the CRUD either creates
  the row when an asset is picked or deletes it when the slot is
  cleared. `start_time` / `end_time` are reserved for a future
  clip-trimming feature and stay null for now.

  `volume` is 0..1 with three decimals (plan spec).
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Association.NotLoaded
  alias Storyarn.Assets.Asset
  alias Storyarn.Flows.FlowNode

  @kinds ~w(background music ambient)

  @type t :: %__MODULE__{
          id: integer() | nil,
          flow_node_id: integer() | nil,
          flow_node: FlowNode.t() | NotLoaded.t() | nil,
          kind: String.t() | nil,
          position: integer(),
          asset_id: integer() | nil,
          asset: Asset.t() | NotLoaded.t() | nil,
          start_time: Decimal.t() | nil,
          end_time: Decimal.t() | nil,
          volume: Decimal.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "flow_node_sequence_tracks" do
    belongs_to :flow_node, FlowNode
    belongs_to :asset, Asset

    field :kind, :string
    field :position, :integer, default: 0

    field :start_time, :decimal
    field :end_time, :decimal
    field :volume, :decimal, default: Decimal.new("1.000")

    timestamps(type: :utc_datetime)
  end

  @doc "Returns the 3 valid `kind` values."
  @spec kinds() :: [String.t()]
  def kinds, do: @kinds

  @doc """
  Changeset for creating a new track. Requires `flow_node_id` +
  `kind`. The DB trigger `fn_validate_sequence_track_owner` enforces
  that `flow_node_id` references a sequence-typed flow_node.
  """
  def create_changeset(track, attrs) do
    track
    |> cast(attrs, [
      :flow_node_id,
      :kind,
      :position,
      :asset_id,
      :start_time,
      :end_time,
      :volume
    ])
    |> validate_required([:flow_node_id, :kind])
    |> validate_inclusion(:kind, @kinds)
    |> validate_volume()
    |> unique_constraint([:flow_node_id, :kind],
      name: :flow_node_sequence_tracks_flow_node_id_kind_index
    )
    |> foreign_key_constraint(:flow_node_id)
    |> foreign_key_constraint(:asset_id)
  end

  @doc """
  Changeset for updating an existing track. `flow_node_id` and `kind`
  are immutable — clearing or re-assigning a slot means deleting the
  row and inserting a new one.
  """
  def update_changeset(track, attrs) do
    track
    |> cast(attrs, [:position, :asset_id, :start_time, :end_time, :volume])
    |> validate_volume()
    |> foreign_key_constraint(:asset_id)
  end

  defp validate_volume(changeset) do
    validate_change(changeset, :volume, fn :volume, value ->
      case value do
        nil -> []
        %Decimal{} = v ->
          cond do
            Decimal.lt?(v, 0) -> [volume: "must be >= 0"]
            Decimal.gt?(v, 1) -> [volume: "must be <= 1"]
            true -> []
          end

        _ ->
          [volume: "must be a decimal between 0 and 1"]
      end
    end)
  end
end

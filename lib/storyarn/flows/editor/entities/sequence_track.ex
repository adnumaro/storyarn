defmodule Storyarn.Flows.SequenceTrack do
  @moduledoc """
  An audio-track definition or inherited-property patch attached to a
  sequence or dialogue composition owner.

  Local definitions use one `kind` slot per owner:

    * `music` — melodic or rhythmic layer.
    * `ambience` — looping atmosphere layer. Typically the lowest
      in the mix.
    * `sfx` — short-loop or punctual textures that compose on top.

  `track_key` is the stable identity composed through an explicit source
  chain. A partial unique index on `(flow_node_id, kind)` applies only to
  local definitions (`is_override = false`), so a property patch for an
  inherited track may coexist with a local track of the same kind.
  `overridden_fields` records the properties owned by a patch and `removed`
  represents a tombstone. Effective tracks still mix additively by logical
  key, including multiple tracks of the same kind from different owners.

  `asset_id` is nullable for empty local slots, asset-clearing patches, and
  tombstones. Deleting an asset sets it to null without deleting the track
  row. `start_time` / `end_time` are reserved for a future clip-trimming
  feature and stay null for now.

  `volume` is 0..1 with three decimals (plan spec).
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Association.NotLoaded
  alias Storyarn.Flows.Editor.Projections.AssetRecord
  alias Storyarn.Flows.FlowNode

  @kinds ~w(music ambience sfx)
  @property_fields ~w(position asset_id start_time end_time volume)

  @type t :: %__MODULE__{
          id: integer() | nil,
          flow_node_id: integer() | nil,
          flow_node: FlowNode.t() | NotLoaded.t() | nil,
          kind: String.t() | nil,
          position: integer(),
          asset_id: integer() | nil,
          asset: AssetRecord.t() | NotLoaded.t() | nil,
          track_key: String.t() | nil,
          is_override: boolean(),
          overridden_fields: [String.t()],
          removed: boolean(),
          start_time: Decimal.t() | nil,
          end_time: Decimal.t() | nil,
          volume: Decimal.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "flow_node_sequence_tracks" do
    belongs_to :flow_node, FlowNode
    belongs_to :asset, AssetRecord, where: [deleted_at: nil]

    field :track_key, :string
    field :is_override, :boolean, default: false
    field :overridden_fields, {:array, :string}, default: []
    field :removed, :boolean, default: false
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

  @doc "Returns the properties that can be overridden independently."
  @spec property_fields() :: [String.t()]
  def property_fields, do: @property_fields

  @doc """
  Changeset for creating a local track definition. Requires `flow_node_id` +
  `kind`. The DB trigger `fn_validate_sequence_track_owner` restricts owners
  to sequence or dialogue nodes.
  """
  def create_changeset(track, attrs) do
    attrs =
      attrs
      |> put_new_attr(:track_key, "track-#{Ecto.UUID.generate()}")
      |> put_new_attr(:overridden_fields, @property_fields)

    track
    |> cast(attrs, [
      :flow_node_id,
      :kind,
      :track_key,
      :is_override,
      :overridden_fields,
      :removed,
      :position,
      :asset_id,
      :start_time,
      :end_time,
      :volume
    ])
    |> validate_required([:flow_node_id, :kind, :track_key])
    |> validate_inclusion(:kind, @kinds)
    |> validate_volume()
    |> validate_override_fields()
    |> unique_constraint([:flow_node_id, :kind],
      name: :flow_node_sequence_tracks_local_kind_index
    )
    |> unique_constraint([:flow_node_id, :track_key])
    |> foreign_key_constraint(:flow_node_id)
    |> foreign_key_constraint(:asset_id)
  end

  @doc """
  Changeset for updating an existing track. `flow_node_id` and `kind`
  are immutable — clearing or re-assigning a slot means deleting the
  row and inserting a new one.
  """
  def update_changeset(track, attrs) do
    overridden_fields = merge_overridden_fields(track.overridden_fields, attrs)

    track
    |> cast(attrs, [:position, :asset_id, :start_time, :end_time, :volume])
    |> put_change(:overridden_fields, overridden_fields)
    |> validate_volume()
    |> validate_override_fields()
    |> foreign_key_constraint(:asset_id)
  end

  @doc "Builds an inherited-track patch with an explicit property mask."
  def override_changeset(track, attrs) do
    track
    |> cast(attrs, [
      :flow_node_id,
      :kind,
      :track_key,
      :is_override,
      :overridden_fields,
      :removed,
      :position,
      :asset_id,
      :start_time,
      :end_time,
      :volume
    ])
    |> validate_required([:flow_node_id, :kind, :track_key])
    |> validate_inclusion(:kind, @kinds)
    |> validate_volume()
    |> validate_override_fields()
    |> unique_constraint([:flow_node_id, :track_key])
    |> foreign_key_constraint(:flow_node_id)
    |> foreign_key_constraint(:asset_id)
  end

  @doc "Returns selected properties to their inherited values."
  def revert_fields_changeset(track, fields) when is_list(fields) do
    case normalize_requested_fields(fields) do
      {:ok, normalized_fields} ->
        track
        |> change(overridden_fields: List.wrap(track.overridden_fields) -- normalized_fields)
        |> validate_override_fields()

      {:error, message} ->
        track
        |> change()
        |> add_error(:overridden_fields, message)
    end
  end

  @doc "Marks or unmarks the logical track tombstone."
  def removal_changeset(track, removed) when is_boolean(removed), do: change(track, removed: removed)

  defp validate_volume(changeset) do
    validate_change(changeset, :volume, fn :volume, value ->
      case value do
        nil ->
          []

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

  defp validate_override_fields(changeset) do
    case get_field(changeset, :overridden_fields) do
      nil ->
        add_error(changeset, :overridden_fields, "must be a list of supported property names")

      _fields ->
        validate_change(changeset, :overridden_fields, fn :overridden_fields, fields ->
          normalized = normalize_fields(fields)

          cond do
            length(normalized) != length(fields) ->
              [overridden_fields: "must contain unique supported property names"]

            Enum.any?(fields, &(&1 not in @property_fields)) ->
              [overridden_fields: "contains an unsupported property"]

            true ->
              []
          end
        end)
    end
  end

  defp normalize_requested_fields(fields) do
    if Enum.all?(fields, &(is_atom(&1) or is_binary(&1))) do
      normalized = normalize_fields(fields)

      cond do
        length(normalized) != length(fields) ->
          {:error, "must contain unique supported property names"}

        Enum.any?(normalized, &(&1 not in @property_fields)) ->
          {:error, "contains an unsupported property"}

        true ->
          {:ok, normalized}
      end
    else
      {:error, "contains an unsupported property"}
    end
  end

  defp merge_overridden_fields(existing, attrs) do
    existing
    |> List.wrap()
    |> Kernel.++(property_keys(attrs))
    |> normalize_fields()
  end

  defp property_keys(attrs) do
    attrs
    |> Map.keys()
    |> Enum.map(&to_string/1)
    |> Enum.filter(&(&1 in @property_fields))
  end

  defp normalize_fields(fields), do: fields |> Enum.map(&to_string/1) |> Enum.uniq() |> Enum.sort()

  defp put_new_attr(attrs, key, value) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(attrs, key) or Map.has_key?(attrs, string_key) ->
        attrs

      Enum.any?(attrs, fn {attr_key, _value} -> is_atom(attr_key) end) ->
        Map.put(attrs, key, value)

      true ->
        Map.put(attrs, string_key, value)
    end
  end
end

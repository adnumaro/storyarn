defmodule Storyarn.Flows.SequenceCompositionChangesetTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.SequenceTrack
  alias Storyarn.Flows.SequenceVisualLayer

  @subjects [
    {SequenceTrack, %{flow_node_id: 1, kind: "music", track_key: "track-test"}, "volume"},
    {SequenceVisualLayer, %{flow_node_id: 1, asset_id: 1, kind: "backdrop", layer_key: "layer-test"}, "opacity"}
  ]

  test "visual geometry permits offstage and oversized images while bounding transforms" do
    attrs = %{flow_node_id: 1, asset_id: 1, kind: "character", x: -10, y: 10, width: 20, height: 2.5}
    assert SequenceVisualLayer.create_changeset(%SequenceVisualLayer{}, attrs).valid?

    for {field, value} <- [
          {:x, -10.01},
          {:y, 10.01},
          {:width, 0},
          {:height, 20.01},
          {:anchor_x, -0.01},
          {:anchor_y, 1.01},
          {:opacity, 1.01}
        ] do
      changeset = SequenceVisualLayer.create_changeset(%SequenceVisualLayer{}, Map.put(attrs, field, value))
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, field)
    end
  end

  test "create and override changesets reject a nil override mask" do
    for {module, attrs, _field} <- @subjects,
        changeset_function <- [:create_changeset, :override_changeset] do
      changeset =
        nil_override_changeset(module, changeset_function, attrs)

      refute changeset.valid?

      assert {"must be a list of supported property names", _metadata} =
               Keyword.fetch!(changeset.errors, :overridden_fields)
    end
  end

  test "revert changesets reject duplicate and unsupported requested fields before changing the mask" do
    for {module, _attrs, field} <- @subjects,
        {requested_fields, expected_error} <- [
          {[field, field], "must contain unique supported property names"},
          {["unsupported"], "contains an unsupported property"}
        ] do
      changeset =
        revert_changeset(module, field, requested_fields)

      refute changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :overridden_fields) == [field]
      assert {^expected_error, _metadata} = Keyword.fetch!(changeset.errors, :overridden_fields)
    end
  end

  defp nil_override_changeset(SequenceTrack, :create_changeset, attrs),
    do: SequenceTrack.create_changeset(%SequenceTrack{}, Map.put(attrs, :overridden_fields, nil))

  defp nil_override_changeset(SequenceTrack, :override_changeset, attrs),
    do: SequenceTrack.override_changeset(%SequenceTrack{}, Map.put(attrs, :overridden_fields, nil))

  defp nil_override_changeset(SequenceVisualLayer, :create_changeset, attrs),
    do: SequenceVisualLayer.create_changeset(%SequenceVisualLayer{}, Map.put(attrs, :overridden_fields, nil))

  defp nil_override_changeset(SequenceVisualLayer, :override_changeset, attrs),
    do: SequenceVisualLayer.override_changeset(%SequenceVisualLayer{}, Map.put(attrs, :overridden_fields, nil))

  defp revert_changeset(SequenceTrack, field, requested_fields) do
    SequenceTrack.revert_fields_changeset(
      %SequenceTrack{overridden_fields: [field]},
      requested_fields
    )
  end

  defp revert_changeset(SequenceVisualLayer, field, requested_fields) do
    SequenceVisualLayer.revert_fields_changeset(
      %SequenceVisualLayer{overridden_fields: [field]},
      requested_fields
    )
  end
end

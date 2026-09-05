defmodule Storyarn.Projects.Persistence.SequenceCompositionChangesetTest do
  use ExUnit.Case, async: true

  alias Storyarn.Projects.Persistence.SequenceTrackRecord
  alias Storyarn.Projects.Persistence.SequenceVisualLayerRecord

  @subjects [
    {SequenceTrackRecord, %{flow_node_id: 1, kind: "music", track_key: "track-test"}, "volume"},
    {SequenceVisualLayerRecord, %{flow_node_id: 1, asset_id: 1, kind: "backdrop", layer_key: "layer-test"}, "opacity"}
  ]

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

  defp nil_override_changeset(SequenceTrackRecord, :create_changeset, attrs) do
    SequenceTrackRecord.create_changeset(
      %SequenceTrackRecord{},
      Map.put(attrs, :overridden_fields, nil)
    )
  end

  defp nil_override_changeset(SequenceTrackRecord, :override_changeset, attrs) do
    SequenceTrackRecord.override_changeset(
      %SequenceTrackRecord{},
      Map.put(attrs, :overridden_fields, nil)
    )
  end

  defp nil_override_changeset(SequenceVisualLayerRecord, :create_changeset, attrs) do
    SequenceVisualLayerRecord.create_changeset(
      %SequenceVisualLayerRecord{},
      Map.put(attrs, :overridden_fields, nil)
    )
  end

  defp nil_override_changeset(SequenceVisualLayerRecord, :override_changeset, attrs) do
    SequenceVisualLayerRecord.override_changeset(
      %SequenceVisualLayerRecord{},
      Map.put(attrs, :overridden_fields, nil)
    )
  end

  defp revert_changeset(SequenceTrackRecord, field, requested_fields) do
    SequenceTrackRecord.revert_fields_changeset(
      %SequenceTrackRecord{overridden_fields: [field]},
      requested_fields
    )
  end

  defp revert_changeset(SequenceVisualLayerRecord, field, requested_fields) do
    SequenceVisualLayerRecord.revert_fields_changeset(
      %SequenceVisualLayerRecord{overridden_fields: [field]},
      requested_fields
    )
  end
end

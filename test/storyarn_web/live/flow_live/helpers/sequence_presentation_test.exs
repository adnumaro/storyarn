defmodule StoryarnWeb.FlowLive.Helpers.SequencePresentationTest do
  use ExUnit.Case, async: true

  alias StoryarnWeb.FlowLive.Helpers.SequencePresentation

  test "builds the selected dialogue and effective layer with provenance" do
    nodes = %{
      10 => sequence(10, nil, [layer(101, "room", 901)]),
      20 => dialogue(20, 10, "Open the gate.")
    }

    speakers = %{
      "7" => %{
        name: "Aria Vale",
        color: "#7c3aed",
        avatar_url: "/aria.png",
        avatars: []
      }
    }

    assert %{
             status: "ready",
             intervention: %{nodeId: 20, speakerName: "Aria Vale", text: "Open the gate."},
             composition: %{layers: [serialized_layer], diagnostics: []}
           } = SequencePresentation.stage(20, nodes, speakers, 1)

    assert serialized_layer.id == "room"
    assert serialized_layer.url == "/media/assets/901"
    assert serialized_layer.origin == %{nodeId: 10, sequenceId: 10, inherited: true}
    assert serialized_layer.propertyOrigins["asset_id"].nodeId == 10
  end

  test "surfaces structural resolver diagnostics as an error" do
    nodes = %{
      20 => dialogue(20, 99, "Lost")
    }

    assert %{
             status: "error",
             intervention: %{nodeId: 20},
             composition: %{
               diagnostics: [
                 %{code: "missing_composition_source", nodeId: 99, severity: "error"}
               ]
             }
           } = SequencePresentation.stage(20, nodes, %{}, 1)
  end

  defp sequence(id, source_id, layers) do
    %{
      id: id,
      type: "sequence",
      composition_source_id: source_id,
      sequence_visual_layers: layers,
      sequence_tracks: []
    }
  end

  defp dialogue(id, source_id, text) do
    %{
      id: id,
      type: "dialogue",
      composition_source_id: source_id,
      data: %{"speaker_sheet_id" => 7, "text" => text},
      sequence_visual_layers: [],
      sequence_tracks: []
    }
  end

  defp layer(id, key, asset_id) do
    %{
      id: id,
      layer_key: key,
      overridden_fields: ~w(asset_id kind label z_index slot x y width height anchor_x anchor_y fit opacity visible),
      removed: false,
      asset_id: asset_id,
      asset: %{id: asset_id, filename: "room.png", content_type: "image/png"},
      kind: "backdrop",
      label: "Room",
      z_index: 0,
      slot: "full",
      x: 0.0,
      y: 0.0,
      width: 1.0,
      height: 1.0,
      anchor_x: 0.0,
      anchor_y: 0.0,
      fit: "cover",
      opacity: 1.0,
      visible: true
    }
  end
end

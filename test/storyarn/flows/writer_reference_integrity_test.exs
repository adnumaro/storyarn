defmodule Storyarn.Flows.WriterReferenceIntegrityTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Localization
  alias Storyarn.Projects
  alias Storyarn.Repo
  alias Storyarn.Scenes

  setup do
    user =
      user_fixture(%{
        email: "flow-integrity-#{Ecto.UUID.generate()}@example.com"
      })

    project = project_fixture(user)
    other_project = project_fixture(user)
    flow = flow_fixture(project)

    %{
      user: user,
      project: project,
      other_project: other_project,
      flow: flow
    }
  end

  test "flow create, update and tree move reject foreign or cyclic parents without mutation",
       %{project: project, other_project: other_project, flow: flow} do
    foreign_parent = flow_fixture(other_project)
    count_before = Flows.count_flows(project.id)

    assert {:error, changeset} =
             Flows.create_flow(project, %{
               name: "Invalid child",
               parent_id: foreign_parent.id
             })

    assert errors_on(changeset).parent_id
    assert Flows.count_flows(project.id) == count_before

    child = flow_fixture(project, %{parent_id: flow.id})

    assert {:error, cycle_changeset} =
             Flows.update_flow(flow, %{parent_id: child.id, name: "Not saved"})

    assert errors_on(cycle_changeset).parent_id
    assert Repo.get!(Flow, flow.id).name == flow.name

    assert {:error, {:invalid_project_reference, :parent_id, foreign_id}} =
             Flows.move_flow_to_position(flow, foreign_parent.id, 0)

    assert foreign_id == foreign_parent.id
    assert is_nil(Repo.get!(Flow, flow.id).parent_id)
  end

  test "flow scene writers reject soft-deleted and foreign scenes and preserve the row",
       %{project: project, other_project: other_project, flow: flow} do
    active_scene = scene_fixture(project)
    deleted_scene = scene_fixture(project)
    foreign_scene = scene_fixture(other_project)

    {:ok, with_scene} = Flows.update_flow_scene(flow, %{scene_id: active_scene.id})
    {:ok, _deleted} = Scenes.delete_scene(deleted_scene)

    assert {:error, deleted_changeset} =
             Flows.update_flow_scene(with_scene, %{scene_id: deleted_scene.id})

    assert errors_on(deleted_changeset).scene_id

    assert {:error, foreign_changeset} =
             Flows.update_flow(with_scene, %{scene_id: foreign_scene.id})

    assert errors_on(foreign_changeset).scene_id
    assert Repo.get!(Flow, flow.id).scene_id == active_scene.id
  end

  test "node JSON rejects foreign speaker, non-audio asset and foreign HTML mention",
       %{project: project, other_project: other_project, flow: flow, user: user} do
    foreign_sheet = sheet_fixture(other_project)
    image_asset = image_asset_fixture(project, user)
    node = node_fixture(flow, %{data: %{"text" => "Original"}})

    assert {:error, {:invalid_project_reference, :speaker_sheet_id, foreign_sheet_id}} =
             Flows.update_node_data(node, %{
               "text" => "Changed",
               "speaker_sheet_id" => foreign_sheet.id,
               "avatar_id" => nil
             })

    assert foreign_sheet_id == foreign_sheet.id

    assert {:error, {:invalid_audio_asset_reference, image_asset_id}} =
             Flows.update_node_data(node, %{
               "text" => "Changed",
               "audio_asset_id" => image_asset.id
             })

    assert image_asset_id == image_asset.id

    mention =
      ~s(<p><span class="mention" data-type="sheet" data-id="#{foreign_sheet.id}">Foreign</span></p>)

    assert {:error, {:invalid_project_reference, {:flow_node_mention, "sheet"}, mention_id}} =
             Flows.update_node_data(node, %{"text" => mention})

    assert mention_id == to_string(foreign_sheet.id)
    assert Repo.get!(FlowNode, node.id).data["text"] == "Original"
  end

  test "every mention element must have one supported type and one nonblank id",
       %{project: project, flow: flow} do
    local_sheet = sheet_fixture(project)

    node =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{"text" => "Original", "responses" => []}
      })

    valid_non_span =
      ~s(<p><mark class="mention" data-type="sheet" data-id="#{local_sheet.id}">Local</mark></p>)

    assert {:ok, updated, _meta} =
             Flows.update_node_data(node, %{
               "text" => valid_non_span,
               "responses" => []
             })

    assert Repo.exists?(
             from(reference in Storyarn.Sheets.EntityReference,
               where:
                 reference.source_type == "flow_node" and
                   reference.source_id == ^node.id and
                   reference.target_type == "sheet" and
                   reference.target_id == ^local_sheet.id
             )
           )

    malformed_mentions = [
      ~s(<p><em class="mention" data-id="#{local_sheet.id}">Missing type</em></p>),
      ~s(<p><em class="mention" data-type="sheet">Missing id</em></p>),
      ~s(<p><em class="mention" data-type="scene" data-id="#{local_sheet.id}">Unsupported</em></p>),
      ~s(<p><em class="mention" data-type="sheet" data-id=" ">Blank</em></p>),
      ~s(<p><em class="mention" data-type="sheet" data-type="flow" data-id="#{local_sheet.id}">Duplicate</em></p>)
    ]

    for malformed <- malformed_mentions do
      assert {:error, {:invalid_project_reference, {:flow_node_mention, _context}, _value}} =
               Flows.update_node_data(updated, %{
                 "text" => malformed,
                 "responses" => []
               })

      assert Repo.get!(FlowNode, node.id).data["text"] == valid_non_span
    end
  end

  test "jump targets resolve to one active hub in the same flow and blank remains allowed",
       %{project: project, flow: flow} do
    {:ok, _hub} =
      Flows.create_node(flow, %{
        type: "hub",
        data: %{"hub_id" => "local_hub", "label" => "Local"}
      })

    other_flow = flow_fixture(project)

    {:ok, _foreign_hub} =
      Flows.create_node(other_flow, %{
        type: "hub",
        data: %{"hub_id" => "other_hub", "label" => "Other"}
      })

    assert {:ok, jump} =
             Flows.create_node(flow, %{
               type: "jump",
               data: %{"target_hub_id" => "local_hub"}
             })

    for invalid_target <- ["missing_hub", "other_hub"] do
      assert {:error, {:invalid_jump_target, ^invalid_target}} =
               Flows.update_node_data(jump, %{"target_hub_id" => invalid_target})

      assert Repo.get!(FlowNode, jump.id).data["target_hub_id"] == "local_hub"
    end

    assert {:error, {:invalid_jump_target, "missing_hub"}} =
             Flows.create_node(flow, %{
               type: "jump",
               data: %{"target_hub_id" => "missing_hub"}
             })

    assert {:ok, cleared, _meta} =
             Flows.update_node_data(jump, %{"target_hub_id" => "   "})

    assert cleared.data["target_hub_id"] == ""
  end

  test "invalid dialogue response identities roll back data, edges and localization keys",
       %{project: project, flow: flow} do
    _source = source_language_fixture(project, %{locale_code: "en", name: "English"})
    _target = language_fixture(project, %{locale_code: "es", name: "Spanish"})

    response_one = "response_keep_one"
    response_two = "response_keep_two"
    localization_id = "dialogue_keep_identity"

    dialogue =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{
          "localization_id" => localization_id,
          "text" => "Choose",
          "responses" => [
            %{"id" => response_one, "text" => "One"},
            %{"id" => response_two, "text" => "Two"}
          ]
        }
      })

    target_one = node_fixture(flow)
    target_two = node_fixture(flow)

    connection_one =
      Storyarn.FlowsFixtures.connection_fixture(flow, dialogue, target_one, %{
        source_pin: response_one
      })

    connection_two =
      Storyarn.FlowsFixtures.connection_fixture(flow, dialogue, target_two, %{
        source_pin: response_two
      })

    original_data = Repo.get!(FlowNode, dialogue.id).data

    original_localization =
      "flow_node"
      |> Localization.get_texts_for_source(dialogue.id)
      |> Enum.map(&{&1.id, &1.source_field, &1.source_text})
      |> Enum.sort()

    invalid_payloads = [
      %{
        "localization_id" => localization_id,
        "text" => "Changed",
        "responses" => [
          %{"id" => response_one, "text" => "One changed"},
          %{"text" => "Missing identity"}
        ]
      },
      %{
        "localization_id" => localization_id,
        "text" => "Changed",
        "responses" => [
          %{"id" => response_one, "text" => "One changed"},
          %{"id" => "invalid.response", "text" => "Invalid identity"}
        ]
      },
      %{
        "localization_id" => localization_id,
        "text" => "Changed",
        "responses" => [
          %{"id" => response_one, "text" => "One changed"},
          %{"id" => response_one, "text" => "Duplicate identity"}
        ]
      },
      %{
        "localization_id" => "dialogue_replacement",
        "text" => "Changed",
        "responses" => [
          %{"id" => response_one, "text" => "One changed"},
          %{"id" => response_two, "text" => "Two changed"}
        ]
      }
    ]

    for invalid_payload <- invalid_payloads do
      assert {:error, %Ecto.Changeset{valid?: false}} =
               Flows.update_node_data(dialogue, invalid_payload)

      assert Repo.get!(FlowNode, dialogue.id).data == original_data
      assert Repo.get!(FlowConnection, connection_one.id).source_pin == response_one
      assert Repo.get!(FlowConnection, connection_two.id).source_pin == response_two

      assert "flow_node"
             |> Localization.get_texts_for_source(dialogue.id)
             |> Enum.map(&{&1.id, &1.source_field, &1.source_text})
             |> Enum.sort() == original_localization
    end
  end

  test "node parent and referenced flow must be active and in the source flow/project",
       %{other_project: other_project, flow: flow} do
    other_flow = flow_fixture(other_project)
    {:ok, foreign_sequence} = Flows.create_sequence(other_flow.id, %{"name" => "Foreign"})
    node = node_fixture(flow, %{data: %{"text" => "Original"}})

    assert {:error, {:invalid_node_parent, parent_id}} =
             Flows.update_node_parent(node, foreign_sequence.id)

    assert parent_id == foreign_sequence.id
    assert is_nil(Repo.get!(FlowNode, node.id).parent_id)

    assert {:error, {:invalid_project_reference, :referenced_flow_id, target_flow_id}} =
             Flows.create_node(flow, %{
               type: "subflow",
               data: %{"referenced_flow_id" => other_flow.id}
             })

    assert target_flow_id == other_flow.id
  end

  test "exit targets are coherent, active and same-project with failed writes preserved",
       %{other_project: other_project, flow: flow} do
    foreign_scene = scene_fixture(other_project)
    exit_node = flow.id |> Flows.list_nodes() |> Enum.find(&(&1.type == "exit"))
    original_data = exit_node.data

    assert {:error, {:invalid_project_reference, :exit_target_id, foreign_scene_id}} =
             Flows.update_node_data(exit_node, %{
               "exit_mode" => "terminal",
               "target_type" => "scene",
               "target_id" => foreign_scene.id
             })

    assert foreign_scene_id == foreign_scene.id

    assert {:error, {:invalid_exit_target, :target_id, nil}} =
             Flows.update_node_data(exit_node, %{
               "exit_mode" => "terminal",
               "target_type" => "scene",
               "target_id" => nil
             })

    assert Repo.get!(FlowNode, exit_node.id).data == original_data
  end

  test "connection create rejects foreign/deleted endpoints and invalid pins",
       %{project: project, flow: flow} do
    other_flow = flow_fixture(project)
    foreign_source = node_fixture(other_flow)
    source = node_fixture(flow)
    target = node_fixture(flow)

    attrs = %{
      source_pin: "output",
      target_pin: "input"
    }

    assert {:error, :source_node_not_found} =
             Flows.create_connection(flow, foreign_source, target, attrs)

    {:ok, _deleted, _meta} = Flows.delete_node(source)

    assert {:error, :source_node_not_found} =
             Flows.create_connection(flow, source, target, attrs)

    entry = flow.id |> Flows.list_nodes() |> Enum.find(&(&1.type == "entry"))

    assert {:error, :invalid_source_pin} =
             Flows.create_connection(flow, entry, target, %{
               source_pin: "missing",
               target_pin: "input"
             })

    assert Flows.list_connections(flow.id) == []
  end

  test "subflow connections accept only active exits from the referenced flow",
       %{project: project, flow: flow} do
    referenced_flow = flow_fixture(project)

    referenced_exit =
      referenced_flow.id
      |> Flows.list_nodes()
      |> Enum.find(&(&1.type == "exit"))

    subflow =
      node_fixture(flow, %{
        type: "subflow",
        data: %{"referenced_flow_id" => referenced_flow.id}
      })

    target = node_fixture(flow)

    assert {:error, :invalid_source_pin} =
             Flows.create_connection(flow, subflow, target, %{
               source_pin: "output",
               target_pin: "input"
             })

    assert {:error, :invalid_source_pin} =
             Flows.create_connection(flow, subflow, target, %{
               source_pin: "exit_#{referenced_exit.id + 1_000_000}",
               target_pin: "input"
             })

    assert {:ok, connection} =
             Flows.create_connection(flow, subflow, target, %{
               source_pin: "exit_#{referenced_exit.id}",
               target_pin: "input"
             })

    assert connection.source_pin == "exit_#{referenced_exit.id}"
  end

  test "subflows without a reference or without active exits expose no output pin",
       %{project: project, flow: flow} do
    target = node_fixture(flow)

    without_reference =
      node_fixture(flow, %{
        type: "subflow",
        data: %{"referenced_flow_id" => nil}
      })

    assert {:error, :invalid_source_pin} =
             Flows.create_connection(flow, without_reference, target, %{
               source_pin: "output",
               target_pin: "input"
             })

    referenced_flow = flow_fixture(project)

    referenced_exit =
      referenced_flow.id
      |> Flows.list_nodes()
      |> Enum.find(&(&1.type == "exit"))

    referenced_exit
    |> FlowNode.soft_delete_changeset()
    |> Repo.update!()

    without_active_exits =
      node_fixture(flow, %{
        type: "subflow",
        data: %{"referenced_flow_id" => referenced_flow.id}
      })

    assert {:error, :invalid_source_pin} =
             Flows.create_connection(flow, without_active_exits, target, %{
               source_pin: "exit_#{referenced_exit.id}",
               target_pin: "input"
             })

    assert Flows.list_connections(flow.id) == []
  end

  test "changing or clearing a subflow reference reconciles its edges atomically",
       %{project: project, other_project: other_project, flow: flow} do
    first_reference = flow_fixture(project)
    second_reference = flow_fixture(project)
    foreign_reference = flow_fixture(other_project)

    first_exit =
      first_reference.id
      |> Flows.list_nodes()
      |> Enum.find(&(&1.type == "exit"))

    second_exit =
      second_reference.id
      |> Flows.list_nodes()
      |> Enum.find(&(&1.type == "exit"))

    subflow =
      node_fixture(flow, %{
        type: "subflow",
        data: %{"referenced_flow_id" => first_reference.id}
      })

    target = node_fixture(flow)

    connection =
      Storyarn.FlowsFixtures.connection_fixture(flow, subflow, target, %{
        source_pin: "exit_#{first_exit.id}",
        target_pin: "input"
      })

    assert {:ok, updated, %{connections_changed?: true}} =
             Flows.update_node_data(subflow, %{
               "referenced_flow_id" => second_reference.id
             })

    assert updated.data["referenced_flow_id"] == second_reference.id
    assert Repo.get!(FlowConnection, connection.id).source_pin == "exit_#{second_exit.id}"

    assert {:error, {:invalid_project_reference, :referenced_flow_id, foreign_id}} =
             Flows.update_node_data(updated, %{
               "referenced_flow_id" => foreign_reference.id
             })

    assert foreign_id == foreign_reference.id

    persisted_after_failure = Repo.get!(FlowNode, subflow.id)
    assert persisted_after_failure.data["referenced_flow_id"] == second_reference.id
    assert Repo.get!(FlowConnection, connection.id).source_pin == "exit_#{second_exit.id}"

    assert {:ok, cleared, %{connections_changed?: true}} =
             Flows.update_node_data(persisted_after_failure, %{
               "referenced_flow_id" => nil
             })

    assert is_nil(cleared.data["referenced_flow_id"])
    assert Repo.get(FlowConnection, connection.id) == nil
  end

  test "adding the first and removing the last dialogue response migrates the existing edge",
       %{flow: flow} do
    dialogue =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{"text" => "Choose", "responses" => []}
      })

    target = node_fixture(flow)
    connection = Storyarn.FlowsFixtures.connection_fixture(flow, dialogue, target)
    response_id = "response_#{Ecto.UUID.generate()}"

    assert {:ok, with_response, %{connections_changed?: true}} =
             Flows.update_node_data(dialogue, %{
               "text" => "Choose",
               "responses" => [%{"id" => response_id, "text" => "Continue"}]
             })

    assert Repo.get!(FlowConnection, connection.id).source_pin == response_id

    assert {:ok, _without_responses, %{connections_changed?: true}} =
             Flows.update_node_data(with_response, %{
               "text" => "Choose",
               "responses" => []
             })

    assert Repo.get!(FlowConnection, connection.id).source_pin == "output"
  end

  test "removing one of several dialogue responses deletes only its invalid edge",
       %{flow: flow} do
    kept_response_id = "response_#{Ecto.UUID.generate()}"
    removed_response_id = "response_#{Ecto.UUID.generate()}"

    dialogue =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{
          "text" => "Choose",
          "responses" => [
            %{"id" => kept_response_id, "text" => "Keep"},
            %{"id" => removed_response_id, "text" => "Remove"}
          ]
        }
      })

    kept_target = node_fixture(flow)
    removed_target = node_fixture(flow)

    kept_connection =
      Storyarn.FlowsFixtures.connection_fixture(flow, dialogue, kept_target, %{
        source_pin: kept_response_id
      })

    removed_connection =
      Storyarn.FlowsFixtures.connection_fixture(flow, dialogue, removed_target, %{
        source_pin: removed_response_id
      })

    assert {:ok, _updated, %{connections_changed?: true}} =
             Flows.update_node_data(dialogue, %{
               "text" => "Choose",
               "responses" => [%{"id" => kept_response_id, "text" => "Keep"}]
             })

    assert Repo.get!(FlowConnection, kept_connection.id).source_pin == kept_response_id
    assert Repo.get(FlowConnection, removed_connection.id) == nil
  end

  test "set_main_flow rejects forged and trashed structs without unsetting the legitimate main",
       %{project: project, other_project: other_project, flow: legitimate_main} do
    candidate = flow_fixture(project)

    assert {:ok, _main} = Flows.set_main_flow(legitimate_main)

    forged = %{candidate | project_id: other_project.id}
    assert {:error, :flow_not_found} = Flows.set_main_flow(forged)

    assert Repo.get!(Flow, legitimate_main.id).is_main
    refute Repo.get!(Flow, candidate.id).is_main

    assert {:ok, deleted_candidate} = Flows.delete_flow(candidate)
    assert {:error, :flow_not_found} = Flows.set_main_flow(deleted_candidate)

    assert Repo.get!(Flow, legitimate_main.id).is_main
    refute Repo.get!(Flow, candidate.id).is_main
  end

  test "connection deleters reject forged identity and a trashed flow without deleting rows",
       %{project: project, flow: flow} do
    source = node_fixture(flow)
    target = node_fixture(flow)
    connection = Storyarn.FlowsFixtures.connection_fixture(flow, source, target)
    other_flow = flow_fixture(project)
    forged = %{connection | flow_id: other_flow.id}

    assert {:error, :connection_not_found} = Flows.delete_connection(forged)
    assert Repo.get!(FlowConnection, connection.id)

    assert {:ok, _deleted_flow} = Flows.delete_flow(flow)

    assert {:error, :flow_not_found} = Flows.delete_connection(connection)

    assert {0, :flow_not_found} =
             Flows.delete_connection_by_nodes(flow.id, source.id, target.id)

    assert {0, :flow_not_found} =
             Flows.delete_connection_by_pins(
               flow.id,
               source.id,
               "output",
               target.id,
               "input"
             )

    assert {0, :flow_not_found} =
             Flows.delete_connections_among_nodes(flow.id, [source.id, target.id])

    assert Repo.get!(FlowConnection, connection.id)
  end

  test "sequence layer and track assets stay in the owner's project and failed updates preserve IDs",
       %{project: project, other_project: other_project, flow: flow, user: user} do
    {:ok, sequence} = Flows.create_sequence(flow.id, %{"name" => "Sequence"})
    image = image_asset_fixture(project, user)
    audio = audio_asset_fixture(project, user)
    foreign_image = image_asset_fixture(other_project, user)
    foreign_audio = audio_asset_fixture(other_project, user)

    assert {:error, {:invalid_project_reference, :sequence_visual_asset_id, foreign_image_id}} =
             Flows.create_sequence_visual_layer(sequence.id, %{
               "kind" => "backdrop",
               "asset_id" => foreign_image.id
             })

    assert foreign_image_id == foreign_image.id

    {:ok, layer} =
      Flows.create_sequence_visual_layer(sequence.id, %{
        "kind" => "backdrop",
        "asset_id" => image.id
      })

    assert {:error, {:invalid_project_reference, :sequence_visual_asset_id, _foreign_image_id}} =
             Flows.update_sequence_visual_layer(layer, %{
               "asset_id" => foreign_image.id
             })

    {:ok, track} =
      Flows.upsert_sequence_track(sequence.id, "music", %{
        "asset_id" => audio.id
      })

    assert {:error, {:invalid_project_reference, :sequence_track_asset_id, _foreign_audio_id}} =
             Flows.upsert_sequence_track(sequence.id, "music", %{
               "asset_id" => foreign_audio.id
             })

    assert Repo.get!(Storyarn.Flows.SequenceVisualLayer, layer.id).asset_id == image.id
    assert Repo.get!(Storyarn.Flows.SequenceTrack, track.id).asset_id == audio.id
  end

  test "writers reject a source flow after its project is soft-deleted",
       %{user: user, project: project, flow: flow} do
    node = node_fixture(flow, %{data: %{"text" => "Original"}})
    {:ok, _deleted_project} = Projects.delete_project(project, user.id)

    assert {:error, :flow_not_found} =
             Flows.update_node_data(node, %{"text" => "Not saved"})

    assert Repo.get!(FlowNode, node.id).data["text"] == "Original"
  end
end

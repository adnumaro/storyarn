defmodule Storyarn.Versioning.LocalizationSnapshotCodecTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Localization
  alias Storyarn.Versioning.LocalizationSnapshotCodec

  test "include_archived snapshots preserve lifecycle metadata" do
    project = project_fixture(user_fixture())
    source_language_fixture(project, %{locale_code: "en", name: "English"})
    language_fixture(project, %{locale_code: "es", name: "Spanish"})
    flow = flow_fixture(project)
    node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello", "responses" => []}})

    assert :ok = Localization.delete_flow_node_texts(node.id)

    assert [%{"archived_at" => archived_at, "archive_reason" => "source_deleted"} = row] =
             LocalizationSnapshotCodec.capture(
               project.id,
               %{"flow_node" => [node.id]},
               include_archived: true
             )

    assert archived_at
    assert :ok = LocalizationSnapshotCodec.restore(project.id, [row], %{node: %{node.id => node.id}})

    assert [%{archived_at: restored_at, archive_reason: "source_deleted"}] =
             project.id
             |> Localization.list_all_texts(source_type: "flow_node")
             |> Enum.filter(&(&1.source_id == node.id))

    assert restored_at
  end

  test "restore deduplicates rows that remap onto the same runtime source key" do
    project = project_fixture(user_fixture())
    source_language_fixture(project, %{locale_code: "en", name: "English"})
    language_fixture(project, %{locale_code: "es", name: "Spanish"})
    flow = flow_fixture(project)
    source_a = node_fixture(flow, %{type: "dialogue", data: %{"text" => "First", "responses" => []}})
    source_b = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Second", "responses" => []}})
    target = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Target", "responses" => []}})

    rows = LocalizationSnapshotCodec.capture(project.id, %{"flow_node" => [source_a.id, source_b.id]})

    assert :ok =
             LocalizationSnapshotCodec.restore(project.id, rows, %{
               node: %{source_a.id => target.id, source_b.id => target.id}
             })

    assert [_one_text] = Localization.get_texts_for_source("flow_node", target.id)
  end
end

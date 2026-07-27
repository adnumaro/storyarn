defmodule Storyarn.Flows.NodeUpdateBatchTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.NodeCreate
  alias Storyarn.Flows.NodeUpdate
  alias Storyarn.Flows.ReferenceIntegrity
  alias Storyarn.Repo
  alias Storyarn.Sheets

  test "batches audio asset semantic validation for unchanged nodes" do
    user = user_fixture()
    project = project_fixture(user)
    flow = flow_fixture(project)
    audio = audio_asset_fixture(project, user)

    nodes =
      for index <- 1..20 do
        node_fixture(flow, %{
          data: %{
            "text" => "Audio dialogue #{index}",
            "audio_asset_id" => audio.id,
            "responses" => []
          }
        })
      end

    assert_batched_query_growth(nodes, project.id)
  end

  test "batches avatar semantic validation for unchanged nodes" do
    user = user_fixture()
    project = project_fixture(user)
    flow = flow_fixture(project)
    speaker = sheet_fixture(project)
    image = image_asset_fixture(project, user)
    assert {:ok, avatar} = Sheets.add_avatar(speaker, image.id)

    nodes =
      for index <- 1..20 do
        node_fixture(flow, %{
          data: %{
            "text" => "Avatar dialogue #{index}",
            "speaker_sheet_id" => speaker.id,
            "avatar_id" => avatar.id,
            "responses" => []
          }
        })
      end

    assert_batched_query_growth(nodes, project.id)
  end

  test "batches jump target validation for unchanged nodes" do
    project = project_fixture()
    flow = flow_fixture(project)

    hub =
      node_fixture(flow, %{
        type: "hub",
        data: %{"hub_id" => "batch_target", "label" => "Batch target"}
      })

    nodes =
      for _index <- 1..20 do
        node_fixture(flow, %{
          type: "jump",
          data: %{"target_hub_id" => hub.data["hub_id"]}
        })
      end

    assert_batched_query_growth(nodes, project.id)
  end

  test "batches hub uniqueness validation for unchanged nodes" do
    project = project_fixture()
    flow = flow_fixture(project)

    nodes =
      for index <- 1..20 do
        node_fixture(flow, %{
          type: "hub",
          data: %{"hub_id" => "batch_hub_#{index}", "label" => "Batch hub #{index}"}
        })
      end

    assert_batched_query_growth(nodes, project.id)
  end

  test "batches referenced flow cycle validation for unchanged nodes" do
    project = project_fixture()
    source_flow = flow_fixture(project)
    target_flow = flow_fixture(project)

    nodes =
      for _index <- 1..20 do
        node_fixture(source_flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => target_flow.id}
        })
      end

    assert_batched_query_growth(nodes, project.id)
  end

  test "batch cycle detection matches singular detection for self, cycle, and non-cycle" do
    project = project_fixture()
    source_flow = flow_fixture(project)
    cyclic_target = flow_fixture(project)
    acyclic_target = flow_fixture(project)

    node_fixture(cyclic_target, %{
      type: "subflow",
      data: %{"referenced_flow_id" => source_flow.id}
    })

    pairs = [
      {source_flow.id, source_flow.id},
      {source_flow.id, cyclic_target.id},
      {source_flow.id, acyclic_target.id}
    ]

    expected =
      pairs
      |> Enum.filter(fn {source_flow_id, target_flow_id} ->
        NodeCreate.has_circular_reference?(source_flow_id, target_flow_id)
      end)
      |> MapSet.new()

    assert NodeCreate.circular_reference_pairs(pairs) == expected
  end

  test "batch cycle detection matches the singular depth boundary" do
    project = project_fixture()
    source_flow = flow_fixture(project)

    chain =
      for index <- 0..21 do
        flow_fixture(project, %{name: "Depth flow #{index}"})
      end

    chain
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.each(fn [flow, referenced_flow] ->
      node_fixture(flow, %{
        type: "subflow",
        data: %{"referenced_flow_id" => referenced_flow.id}
      })
    end)

    [over_limit_target, at_limit_target | _rest] = chain

    pairs = [
      {source_flow.id, over_limit_target.id},
      {source_flow.id, at_limit_target.id}
    ]

    expected =
      pairs
      |> Enum.filter(fn {source_flow_id, target_flow_id} ->
        NodeCreate.has_circular_reference?(source_flow_id, target_flow_id)
      end)
      |> MapSet.new()

    assert expected == MapSet.new([{source_flow.id, over_limit_target.id}])
    assert NodeCreate.circular_reference_pairs(pairs) == expected
  end

  test "batch avatar validation preserves missing and cross-project errors" do
    user = user_fixture()
    project = project_fixture(user)
    flow = flow_fixture(project)
    missing_avatar_id = System.unique_integer([:positive]) + 9_000_000_000

    assert_reference_batch_error_parity(
      project.id,
      flow.id,
      %{"avatar_id" => missing_avatar_id},
      {:invalid_avatar_reference, missing_avatar_id}
    )

    other_project = project_fixture(user)
    other_sheet = sheet_fixture(other_project)
    image = image_asset_fixture(other_project, user)
    assert {:ok, other_avatar} = Sheets.add_avatar(other_sheet, image.id)

    assert_reference_batch_error_parity(
      project.id,
      flow.id,
      %{"avatar_id" => other_avatar.id},
      {:avatar_project_mismatch, other_avatar.id}
    )
  end

  test "batch hub validation excludes self and rejects duplicate owners" do
    project = project_fixture()
    flow = flow_fixture(project)

    first =
      node_fixture(flow, %{
        type: "hub",
        data: %{"hub_id" => "shared_hub", "label" => "First"}
      })

    assert MapSet.member?(
             current_node_ids([{first, first.data}], project.id),
             first.id
           )

    second =
      node_fixture(flow, %{
        type: "hub",
        data: %{"hub_id" => "second_hub", "label" => "Second"}
      })

    duplicate_data = Map.put(second.data, "hub_id", first.data["hub_id"])

    second =
      second
      |> Ecto.Changeset.change(
        data: duplicate_data,
        derivatives_fingerprint: NodeUpdate.derivatives_fingerprint(second.type, duplicate_data)
      )
      |> Repo.update!()

    current_ids =
      current_node_ids(
        [{first, first.data}, {second, second.data}],
        project.id
      )

    refute MapSet.member?(current_ids, first.id)
    refute MapSet.member?(current_ids, second.id)
  end

  defp assert_batched_query_growth(nodes, project_id) do
    small_count =
      nodes
      |> Enum.take(5)
      |> current_node_query_count(project_id)

    large_count = current_node_query_count(nodes, project_id)

    assert large_count <= small_count + 2
  end

  defp current_node_query_count(nodes, project_id) do
    {:ok, {current_ids, queries}} =
      Repo.transaction(fn ->
        capture_queries(fn ->
          nodes
          |> Enum.map(&{&1, &1.data})
          |> Flows.node_data_and_derivatives_current_ids(project_id)
        end)
      end)

    assert MapSet.size(current_ids) == length(nodes)
    length(queries)
  end

  defp current_node_ids(node_data_pairs, project_id) do
    assert {:ok, current_ids} =
             Repo.transaction(fn ->
               Flows.node_data_and_derivatives_current_ids(
                 node_data_pairs,
                 project_id
               )
             end)

    current_ids
  end

  defp assert_reference_batch_error_parity(project_id, flow_id, data, expected_reason) do
    assert {:ok, {singular_result, batch_result}} =
             Repo.transaction(fn ->
               singular_result =
                 ReferenceIntegrity.lock_and_normalize_node_references(
                   project_id,
                   flow_id,
                   "dialogue",
                   data
                 )

               batch_result =
                 ReferenceIntegrity.lock_and_normalize_node_reference_batch(
                   project_id,
                   [{:candidate, flow_id, "dialogue", data}]
                 )

               {singular_result, batch_result}
             end)

    assert singular_result == {:error, expected_reason}
    assert batch_result == singular_result
  end

  defp capture_queries(fun) when is_function(fun, 0) do
    handler_id = "node-update-batch-query-budget-#{System.unique_integer([:positive])}"
    marker = make_ref()
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:storyarn, :repo, :query],
        fn _event, _measurements, %{query: query}, {pid, ref} ->
          if self() == pid, do: send(pid, {ref, query})
        end,
        {test_pid, marker}
      )

    try do
      {fun.(), drain_queries(marker)}
    after
      :telemetry.detach(handler_id)
    end
  end

  defp drain_queries(marker, queries \\ []) do
    receive do
      {^marker, query} -> drain_queries(marker, [query | queries])
    after
      0 -> Enum.reverse(queries)
    end
  end
end

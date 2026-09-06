defmodule Storyarn.Flows.VersionRequestsTest do
  use Storyarn.DataCase, async: true
  use Oban.Testing, repo: Storyarn.Repo

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.Versioning.VersionRequest
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Assets
  alias Storyarn.Repo
  alias Storyarn.Workers.CreateFlowVersionWorker

  setup do
    user = user_fixture()
    project = project_fixture(user, %{auto_version_flows: true})
    flow = flow_fixture(project, %{name: "Captured state"})
    %{user: user, project: project, flow: flow}
  end

  test "queues atomically and publishes the requested state once after further edits", ctx do
    Flows.subscribe_version_requests(ctx.project.id)
    assert {:ok, request} = Flows.request_version(ctx.flow, ctx.user.id, title: "Checkpoint")
    assert_enqueued(worker: CreateFlowVersionWorker, args: %{request_id: request.id})
    assert Flows.count_versions(ctx.flow.id) == 0
    assert %{pending: true, failed: false} = Flows.version_request_status(ctx.flow.id)
    assert {:ok, _} = Flows.update_flow(ctx.flow, %{name: "Later changes"})

    assert :ok = perform_job(CreateFlowVersionWorker, %{request_id: request.id})
    assert_receive {:flow_version_request_finished, _, _, "completed", false}
    version = Flows.get_version(ctx.flow.id, 1)
    assert {:ok, snapshot} = Flows.load_version_snapshot(version)
    assert snapshot["name"] == "Captured state"
    assert Repo.get!(VersionRequest, request.id).snapshot == %{}
    assert %{pending: false, failed: false} = Flows.version_request_status(ctx.flow.id)

    assert :ok = perform_job(CreateFlowVersionWorker, %{request_id: request.id})
    assert Flows.count_versions(ctx.flow.id) == 1
    assert_receive {:flow_version_request_finished, _, _, "completed", false}
  end

  test "later requests wait for older captures even when jobs execute out of order", ctx do
    assert {:ok, first} = Flows.request_version(ctx.flow, ctx.user.id, title: "First")
    assert {:ok, second} = Flows.request_version(ctx.flow, ctx.user.id, title: "Second")
    assert {:snooze, 5} = perform_job(CreateFlowVersionWorker, %{request_id: second.id})
    assert Flows.count_versions(ctx.flow.id) == 0
    assert :ok = perform_job(CreateFlowVersionWorker, %{request_id: first.id})
    assert :ok = perform_job(CreateFlowVersionWorker, %{request_id: second.id})
    assert Flows.get_version(ctx.flow.id, 1).title == "First"
    assert Flows.get_version(ctx.flow.id, 2).title == "Second"
  end

  test "coalesces automatic requests and rechecks the interval when publishing", ctx do
    assert {:ok, auto} = Flows.request_version(ctx.flow, ctx.user.id, is_auto: true)
    assert {:skipped, :pending} = Flows.request_version(ctx.flow, ctx.user.id, is_auto: true)
    assert {:ok, _} = Flows.create_version(ctx.flow, ctx.user.id, title: "Written meanwhile")
    assert :ok = perform_job(CreateFlowVersionWorker, %{request_id: auto.id})
    assert Repo.get!(VersionRequest, auto.id).status == "skipped"
    assert Flows.count_versions(ctx.flow.id) == 1
    assert {:skipped, :too_recent} = Flows.request_version(ctx.flow, ctx.user.id, is_auto: true)
  end

  test "does not publish automatic versions after the project opts out", ctx do
    assert {:ok, request} = Flows.request_version(ctx.flow, ctx.user.id, is_auto: true)
    ctx.project |> Ecto.Changeset.change(auto_version_flows: false) |> Repo.update!()
    assert :ok = perform_job(CreateFlowVersionWorker, %{request_id: request.id})
    assert Repo.get!(VersionRequest, request.id).status == "skipped"
    assert Flows.count_versions(ctx.flow.id) == 0
  end

  test "invalid manual requests persist neither captures nor jobs", ctx do
    assert {:error, :title_required} = Flows.request_version(ctx.flow, ctx.user.id, title: " ")
    refute Repo.get_by(VersionRequest, flow_id: ctx.flow.id)
    refute_enqueued(worker: CreateFlowVersionWorker)
  end

  test "a frozen asset catalog can publish after its original file and row are removed", ctx do
    asset = upload_layer(ctx)
    assert {:ok, request} = Flows.request_version(ctx.flow, ctx.user.id, title: "With image")
    assert :ok = Assets.storage_delete(asset.key)
    Repo.delete!(asset)
    assert :ok = perform_job(CreateFlowVersionWorker, %{request_id: request.id})
    assert {:ok, snapshot} = Flows.load_version_snapshot(Flows.get_version(ctx.flow.id, 1))
    assert snapshot["asset_blob_hashes"][to_string(asset.id)] == asset.blob_hash
  end

  test "capture does no object I/O; failed writes remain pending and retry the same capture", ctx do
    asset = upload_layer(ctx)
    blob_key = "projects/#{ctx.project.id}/blobs/#{asset.blob_hash}.png"
    assert :ok = delete_storage_blob(blob_key)
    assert :ok = Assets.storage_delete(asset.key)
    assert {:ok, request} = Flows.request_version(ctx.flow, ctx.user.id, title: "Missing bytes")
    assert {:error, _} = perform_job(CreateFlowVersionWorker, %{request_id: request.id})
    assert Repo.get!(VersionRequest, request.id).status == "pending"
    assert Flows.count_versions(ctx.flow.id) == 0
    assert {:ok, _} = Assets.storage_upload(asset.key, "image bytes", "image/png")
    assert :ok = perform_job(CreateFlowVersionWorker, %{request_id: request.id})
    assert Flows.count_versions(ctx.flow.id) == 1
  end

  test "terminal failures are visible and release the next request", ctx do
    asset = upload_layer(ctx)
    assert {:ok, first} = Flows.request_version(ctx.flow, ctx.user.id, title: "Fails")
    assert {:ok, second} = Flows.request_version(ctx.flow, ctx.user.id, title: "Next")
    delete_storage_blob("projects/#{ctx.project.id}/blobs/#{asset.blob_hash}.png")
    Assets.storage_delete(asset.key)
    assert {:discard, _} = Flows.perform_version_request(first.id, final_attempt: true)
    assert Repo.get!(VersionRequest, first.id).status == "failed"
    assert {:ok, _} = Assets.storage_upload(asset.key, "image bytes", "image/png")
    assert :ok = perform_job(CreateFlowVersionWorker, %{request_id: second.id})
    assert Flows.get_version(ctx.flow.id, 1).title == "Next"
  end

  test "snoozes do not consume the failure retry budget", ctx do
    asset = upload_layer(ctx)
    assert {:ok, request} = Flows.request_version(ctx.flow, ctx.user.id, title: "Retries")
    delete_storage_blob("projects/#{ctx.project.id}/blobs/#{asset.blob_hash}.png")
    Assets.storage_delete(asset.key)
    job = %Oban.Job{args: %{"request_id" => request.id}, attempt: 20, max_attempts: 22, errors: []}
    assert {:error, _} = CreateFlowVersionWorker.perform(job)
    assert Repo.get!(VersionRequest, request.id).status == "pending"
    assert {:discard, _} = CreateFlowVersionWorker.perform(%{job | errors: [%{}, %{}]})
    assert %{pending: false, failed: true} = Flows.version_request_status(ctx.flow.id)
  end

  test "recovers an interrupted execution without touching other workers", ctx do
    {:ok, request} = Flows.request_version(ctx.flow, ctx.user.id, title: "Interrupted")
    [job] = all_enqueued(worker: CreateFlowVersionWorker, args: %{request_id: request.id})
    old = DateTime.add(TimeHelpers.now(), -1800, :second)

    job
    |> Ecto.Changeset.change(state: "executing", attempted_at: %{old | microsecond: {0, 6}}, attempt: 1)
    |> Repo.update!()

    foreign = %Oban.Job{
      worker: "UnrelatedWorker",
      queue: "default",
      args: %{},
      state: "executing",
      attempted_at: %{old | microsecond: {0, 6}},
      attempt: 1
    }

    foreign = Repo.insert!(foreign)
    assert :ok = Flows.recover_version_requests()
    assert Repo.get!(Oban.Job, job.id).state == "available"
    assert Repo.get!(Oban.Job, foreign.id).state == "executing"
    assert :ok = perform_job(CreateFlowVersionWorker, %{request_id: request.id})
    assert Flows.count_versions(ctx.flow.id) == 1
  end

  test "exhausted interrupted execution terminalizes the capture and notifies the editor", ctx do
    {:ok, request} = Flows.request_version(ctx.flow, ctx.user.id, title: "Exhausted")
    [job] = all_enqueued(worker: CreateFlowVersionWorker, args: %{request_id: request.id})
    old = DateTime.add(TimeHelpers.now(), -1800, :second)
    request |> Ecto.Changeset.change(inserted_at: old) |> Repo.update!()

    job
    |> Ecto.Changeset.change(state: "executing", attempted_at: %{old | microsecond: {0, 6}}, attempt: 3)
    |> Repo.update!()

    Flows.subscribe_version_requests(ctx.project.id)
    assert :ok = Flows.recover_version_requests()
    assert Repo.get!(Oban.Job, job.id).state == "discarded"
    assert Repo.get!(VersionRequest, request.id).status == "failed"
    assert_receive {:flow_version_request_finished, _, _, "failed", false}
    assert Flows.count_versions(ctx.flow.id) == 0
  end

  defp upload_layer(ctx) do
    {:ok, asset} =
      Assets.upload_binary_and_create_asset(
        "image bytes",
        %{filename: "queued.png", content_type: "image/png"},
        ctx.project,
        ctx.user
      )

    node = node_fixture(ctx.flow)
    {:ok, _} = Flows.create_sequence_visual_layer(node.id, %{asset_id: asset.id, kind: "character"})

    on_exit(fn ->
      Assets.storage_delete(asset.key)
      delete_storage_blob("projects/#{ctx.project.id}/blobs/#{asset.blob_hash}.png")
    end)

    asset
  end
end

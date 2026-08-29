defmodule Storyarn.Workspaces.Invitations.Adapters.Jobs.InvitationQueueTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Repo
  alias Storyarn.Workers.DeliverWorkspaceInvitationWorker
  alias Storyarn.Workspaces.Invitations.Adapters.Jobs.InvitationQueue

  test "wakes only after the queued job is committed and visible" do
    marker = "workspace-post-commit-#{System.unique_integer([:positive])}"
    test_process = self()

    on_exit(fn -> delete_probe_jobs(marker) end)

    Sandbox.unboxed_run(Repo, fn ->
      assert {:ok, job} =
               Repo.transact(fn ->
                 %{
                   "context" => "workspace",
                   "encrypted_token" => "opaque",
                   "locale" => "en",
                   "post_commit_probe" => marker
                 }
                 |> DeliverWorkspaceInvitationWorker.new()
                 |> Oban.insert()
               end)

      assert :ok =
               InvitationQueue.wake_after_commit(
                 job,
                 queue_notifier: fn payload ->
                   refute Repo.in_transaction?()
                   persisted_job = Repo.get!(Oban.Job, job.id)
                   send(test_process, {:workspace_job_visible, payload, persisted_job.id})
                   :ok
                 end
               )
    end)

    assert_receive {:workspace_job_visible, %{queue: "invitation_delivery"}, job_id}
    assert is_integer(job_id)
  end

  defp delete_probe_jobs(marker) do
    Sandbox.unboxed_run(Repo, fn ->
      Repo.query!("DELETE FROM oban_jobs WHERE args ->> 'post_commit_probe' = $1", [marker])
    end)
  end
end

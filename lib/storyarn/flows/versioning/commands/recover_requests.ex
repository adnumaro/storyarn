defmodule Storyarn.Flows.Versioning.Commands.RecoverRequests do
  @moduledoc "Recovers interrupted Flow publications without changing other Oban queues."
  import Ecto.Query

  alias Storyarn.Flows.Versioning.Commands.PublishVersion
  alias Storyarn.Flows.Versioning.VersionRequest
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  @worker "Storyarn.Workers.CreateFlowVersionWorker"
  @stale_ms to_timeout(minute: 15)

  def recover do
    jobs = from j in Oban.Job, where: j.worker == @worker and j.queue == "flow_versions"

    with {:ok, recovered} <- Oban.Engine.rescue_jobs(Oban.config(), jobs, rescue_after: @stale_ms) do
      Enum.each(stale_pending_ids(), &finish_abandoned/1)

      if Enum.any?(recovered, &(&1.state == "available")),
        do: Oban.Notifier.notify(Oban, :insert, %{queue: "flow_versions"})

      :ok
    end
  end

  defp stale_pending_ids do
    cutoff = DateTime.shift(TimeHelpers.now(), minute: -15)

    Repo.all(
      from r in VersionRequest,
        where: r.status == "pending" and r.inserted_at < ^cutoff,
        order_by: r.id,
        limit: 100,
        select: r.id
    )
  end

  defp finish_abandoned(id) do
    result =
      Repo.transaction(fn ->
        request =
          Repo.one(from r in VersionRequest, where: r.id == ^id and r.status == "pending", lock: "FOR UPDATE SKIP LOCKED")

        not is_nil(request) and terminal_delivery?(request)
      end)

    if result == {:ok, true}, do: PublishVersion.fail_request(id, :publication_interrupted)
  end

  defp terminal_delivery?(request) do
    args = %{"request_id" => request.id}

    job =
      Repo.one(
        from j in Oban.Job,
          where: j.worker == @worker and j.queue == "flow_versions" and j.args == ^args,
          order_by: [desc: j.id],
          limit: 1
      )

    is_nil(job) or job.state in ~w(cancelled discarded completed)
  end
end

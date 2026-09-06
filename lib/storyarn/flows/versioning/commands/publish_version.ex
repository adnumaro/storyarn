defmodule Storyarn.Flows.Versioning.Commands.PublishVersion do
  @moduledoc "Publishes a durable request once, in capture order, with retryable failures."
  import Ecto.Query

  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.Versioning.Commands.VersionLifecycle
  alias Storyarn.Flows.Versioning.Events
  alias Storyarn.Flows.Versioning.Queries.VersionRequests
  alias Storyarn.Flows.Versioning.VersionRequest
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  def perform(id, opts \\ []) do
    result = publish_transaction(id)
    finish(result, id, opts)
  end

  def fail_request(id, reason), do: finish({:error, reason}, id, final_attempt: true)

  defp publish_transaction(id) do
    Repo.transaction(fn ->
      request = Repo.one(from r in VersionRequest, where: r.id == ^id, lock: "FOR UPDATE")
      publish_request(request)
    end)
  rescue
    error -> {:error, {:publication_failed, Exception.message(error)}}
  end

  defp publish_request(nil), do: {:discard, :request_not_found}
  defp publish_request(%VersionRequest{status: status} = request) when status != "pending", do: request

  defp publish_request(request) do
    case publish_next(request) do
      %VersionRequest{} = published -> {:published, published}
      other -> other
    end
  end

  def subscribe(project_id), do: Phoenix.PubSub.subscribe(Storyarn.PubSub, topic(project_id))

  defp publish_next(request) do
    if VersionRequests.earlier_pending?(request) do
      {:snooze, 5}
    else
      flow = %Flow{id: request.flow_id, project_id: request.project_id}
      opts = [title: request.title, description: request.description, is_auto: request.is_auto]

      case VersionLifecycle.create_captured_version(flow, request.created_by_id, request.snapshot, opts) do
        {:ok, version} -> update_request(request, "completed", version.id)
        {:skipped, _reason} -> update_request(request, "skipped", nil)
        {:error, reason} -> Repo.rollback(reason)
        {:error, reason, metadata} -> Repo.rollback({reason, metadata})
      end
    end
  end

  defp update_request(request, status, version_id) do
    request
    |> Ecto.Changeset.change(status: status, version_id: version_id, snapshot: %{})
    |> Repo.update!()
  end

  defp finish({:ok, {:published, request}}, _id, _opts) do
    if request.status == "completed" and not request.is_auto do
      Events.emit(%{id: request.created_by_id}, :version_created, %{entity_type: "flow", project_id: request.project_id})
    end

    broadcast(request)
    {:ok, request}
  end

  defp finish({:ok, %VersionRequest{} = request}, _id, _opts) do
    # Re-deliver completion if a previous execution committed but stopped before notifying the editor.
    broadcast(request)
    {:ok, request}
  end

  defp finish({:ok, result}, _id, _opts), do: result

  defp finish({:error, reason}, id, opts) do
    if Keyword.get(opts, :final_attempt, false) do
      {_, requests} =
        Repo.update_all(
          from(r in VersionRequest, where: r.id == ^id and r.status == "pending", select: r),
          set: [status: "failed", updated_at: TimeHelpers.now()]
        )

      Enum.each(requests, &broadcast/1)
      {:discard, reason}
    else
      {:error, reason}
    end
  end

  defp broadcast(request) do
    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      topic(request.project_id),
      {:flow_version_request_finished, request.flow_id, request.created_by_id, request.status, request.is_auto}
    )
  end

  defp topic(project_id), do: "flow_versions:#{project_id}"
end

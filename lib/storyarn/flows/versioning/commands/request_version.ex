defmodule Storyarn.Flows.Versioning.Commands.RequestVersion do
  @moduledoc "Persists a coherent capture and its job atomically, without object-storage I/O."
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.Versioning.Commands.NamedVersionCapacity
  alias Storyarn.Flows.Versioning.Commands.VersionLifecycle
  alias Storyarn.Flows.Versioning.FlowSnapshot
  alias Storyarn.Flows.Versioning.Queries.VersionRequests
  alias Storyarn.Flows.Versioning.VersionRequest
  alias Storyarn.Repo
  alias Storyarn.Workers.CreateFlowVersionWorker

  def request(flow, user_id, opts \\ [])

  def request(%Flow{} = flow, user_id, opts) when is_integer(user_id) and user_id > 0 do
    fn -> request_locked(flow, user_id, opts) end
    |> Repo.transaction()
    |> normalize_result()
  end

  def request(_flow, _user_id, _opts), do: {:error, :invalid_actor}

  defp request_locked(flow, user_id, opts) do
    with {:ok, project} <- NamedVersionCapacity.lock_project(flow.project_id),
         :ok <- allowed(flow, project, opts),
         {:ok, request} <- FlowSnapshot.capture(flow, &persist(flow, user_id, &1, opts)) do
      request
    else
      {:skipped, reason} -> {:skipped, reason}
      {:error, reason} -> Repo.rollback(reason)
      {:error, reason, metadata} -> Repo.rollback({reason, metadata})
    end
  end

  defp allowed(flow, project, opts) do
    if Keyword.get(opts, :is_auto, false) do
      if VersionRequests.pending_auto?(flow.id),
        do: {:skipped, :pending},
        else: VersionLifecycle.automatic_version_due(flow)
    else
      with :ok <- validate_title(opts), do: NamedVersionCapacity.ensure_capacity(project)
    end
  end

  defp validate_title(opts) do
    case Keyword.get(opts, :title) do
      title when is_binary(title) ->
        if String.trim(title) != "" and String.length(title) <= 255 and
             String.length(Keyword.get(opts, :description) || "") <= 500, do: :ok, else: {:error, :title_required}

      _ ->
        {:error, :title_required}
    end
  end

  defp persist(flow, user_id, snapshot, opts) do
    with {:ok, request} <-
           Repo.insert(%VersionRequest{
             flow_id: flow.id,
             project_id: flow.project_id,
             created_by_id: user_id,
             snapshot: snapshot,
             title: Keyword.get(opts, :title),
             description: Keyword.get(opts, :description),
             is_auto: Keyword.get(opts, :is_auto, false)
           }),
         {:ok, _job} <- %{request_id: request.id} |> CreateFlowVersionWorker.new() |> Oban.insert() do
      {:ok, request}
    end
  end

  defp normalize_result({:ok, {:skipped, reason}}), do: {:skipped, reason}
  defp normalize_result({:error, {:limit_reached, metadata}}), do: {:error, :limit_reached, metadata}
  defp normalize_result(result), do: result
end

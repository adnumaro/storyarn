defmodule Storyarn.Flows.Versioning.Queries.VersionRequests do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Flows.Versioning.VersionRequest
  alias Storyarn.Repo

  def pending_auto?(flow_id) do
    Repo.exists?(from r in VersionRequest, where: r.flow_id == ^flow_id and r.is_auto and r.status == "pending")
  end

  def earlier_pending?(request) do
    Repo.exists?(
      from r in VersionRequest,
        where: r.flow_id == ^request.flow_id and r.id < ^request.id and r.status == "pending"
    )
  end

  def status(flow_id) do
    latest = Repo.one(from r in VersionRequest, where: r.flow_id == ^flow_id, order_by: [desc: r.id], limit: 1)

    %{
      pending: Repo.exists?(from r in VersionRequest, where: r.flow_id == ^flow_id and r.status == "pending"),
      failed: match?(%VersionRequest{status: "failed"}, latest)
    }
  end
end

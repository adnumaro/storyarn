defmodule Storyarn.ProjectTemplates.Audit do
  @moduledoc """
  Validates whether a project can be published as a template.

  This first pass focuses on known migration hazards that can corrupt a cloned
  flow graph. The report shape is JSON-serializable so it can be stored on each
  immutable template version.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Repo
  alias Storyarn.Versioning.Builders.ProjectSnapshotBuilder

  @doc """
  Runs template-publication audit checks for a project.
  """
  @spec run(integer()) :: {:ok, map()} | {:error, map()}
  def run(project_id) do
    snapshot = ProjectSnapshotBuilder.build_snapshot(project_id)

    errors =
      []
      |> Kernel.++(stale_connection_errors(project_id))
      |> Kernel.++(unsafe_subflow_pin_errors(project_id))

    report = %{
      "status" => if(errors == [], do: "passed", else: "failed"),
      "errors" => errors,
      "warnings" => [],
      "entity_counts" => Map.get(snapshot, "entity_counts", %{})
    }

    if errors == [], do: {:ok, report}, else: {:error, report}
  end

  defp stale_connection_errors(project_id) do
    query =
      from c in FlowConnection,
        join: f in Flow,
        on: f.id == c.flow_id,
        left_join: source in FlowNode,
        on: source.id == c.source_node_id and is_nil(source.deleted_at),
        left_join: target in FlowNode,
        on: target.id == c.target_node_id and is_nil(target.deleted_at),
        where: f.project_id == ^project_id and is_nil(f.deleted_at),
        where: is_nil(source.id) or is_nil(target.id),
        select: %{
          "type" => "stale_flow_connection",
          "flow_id" => f.id,
          "connection_id" => c.id,
          "source_node_id" => c.source_node_id,
          "source_pin" => c.source_pin,
          "target_node_id" => c.target_node_id,
          "target_pin" => c.target_pin
        }

    Repo.all(query)
  end

  defp unsafe_subflow_pin_errors(project_id) do
    query =
      from c in FlowConnection,
        join: f in Flow,
        on: f.id == c.flow_id,
        join: source in FlowNode,
        on: source.id == c.source_node_id,
        where: f.project_id == ^project_id and is_nil(f.deleted_at),
        where: is_nil(source.deleted_at),
        where: source.type == "subflow" and like(c.source_pin, "exit_%"),
        select: %{
          "type" => "unsafe_subflow_exit_pin",
          "flow_id" => f.id,
          "connection_id" => c.id,
          "source_node_id" => c.source_node_id,
          "source_pin" => c.source_pin,
          "target_node_id" => c.target_node_id,
          "target_pin" => c.target_pin
        }

    Repo.all(query)
  end
end

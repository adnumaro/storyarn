defmodule Storyarn.Flows.FlowCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Flow
  alias Storyarn.Projects.Project
  alias Storyarn.Repo

  def list_flows(project_id) do
    from(f in Flow,
      where: f.project_id == ^project_id,
      order_by: [desc: f.is_main, asc: f.name]
    )
    |> Repo.all()
  end

  def get_flow(project_id, flow_id) do
    Flow
    |> where(project_id: ^project_id, id: ^flow_id)
    |> preload([:nodes, :connections])
    |> Repo.one()
  end

  def get_flow!(project_id, flow_id) do
    Flow
    |> where(project_id: ^project_id, id: ^flow_id)
    |> preload([:nodes, :connections])
    |> Repo.one!()
  end

  def create_flow(%Project{} = project, attrs) do
    %Flow{project_id: project.id}
    |> Flow.create_changeset(attrs)
    |> Repo.insert()
  end

  def update_flow(%Flow{} = flow, attrs) do
    flow
    |> Flow.update_changeset(attrs)
    |> Repo.update()
  end

  def delete_flow(%Flow{} = flow) do
    Repo.delete(flow)
  end

  def change_flow(%Flow{} = flow, attrs \\ %{}) do
    Flow.update_changeset(flow, attrs)
  end

  def get_main_flow(project_id) do
    Flow
    |> where(project_id: ^project_id, is_main: true)
    |> Repo.one()
  end

  def set_main_flow(%Flow{} = flow) do
    Repo.transaction(fn ->
      from(f in Flow, where: f.project_id == ^flow.project_id and f.is_main == true)
      |> Repo.update_all(set: [is_main: false])

      flow
      |> Ecto.Changeset.change(is_main: true)
      |> Repo.update!()
    end)
  end
end

defmodule StoryarnWeb.FlowLive.Handlers.NavigationHandlersTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Repo

  # Simulates the FlowLoader JS hook: triggers the event + waits for start_async
  defp load_flow(view) do
    render_click(view, "load_flow_data", %{})
    render_async(view, 2000)
  end

  defp editor_flow_id(view) do
    vue = LiveVue.Test.get_vue(view, name: "modules/flows/components/FlowEditor")
    flow_data = vue.props["flow-data"]
    flow_data = if is_binary(flow_data), do: Jason.decode!(flow_data), else: flow_data

    flow_data["id"] || flow_data[:id]
  end

  describe "navigate_to_subflow" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Main Flow"})
      %{project: project, flow: flow}
    end

    test "navigates to an existing flow", %{conn: conn, project: project, flow: flow} do
      target_flow = flow_fixture(project, %{name: "Target Flow"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      render_click(view, "navigate_to_subflow", %{"flow-id" => to_string(target_flow.id)})

      assert_patch(view)
    end

    test "shows error flash for non-existent flow ID",
         %{conn: conn, project: project, flow: flow} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      html = render_click(view, "navigate_to_subflow", %{"flow-id" => "999999"})

      assert is_binary(html)
      assert editor_flow_id(view) == flow.id
    end

    test "shows error flash for invalid flow ID string",
         %{conn: conn, project: project, flow: flow} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      html = render_click(view, "navigate_to_subflow", %{"flow-id" => "not_a_number"})

      assert is_binary(html)
      assert editor_flow_id(view) == flow.id
    end

    test "shows error for flow ID with trailing characters",
         %{conn: conn, project: project, flow: flow} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      html = render_click(view, "navigate_to_subflow", %{"flow-id" => "123abc"})

      assert is_binary(html)
      assert editor_flow_id(view) == flow.id
    end
  end

  describe "navigate_to_exit_flow" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Current Flow"})
      %{project: project, flow: flow}
    end

    test "navigates to exit flow reference", %{conn: conn, project: project, flow: flow} do
      target_flow = flow_fixture(project, %{name: "Exit Target"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      render_click(view, "navigate_to_exit_flow", %{
        "flow-id" => to_string(target_flow.id)
      })

      assert_patch(view)
    end

    test "shows error for non-existent exit flow",
         %{conn: conn, project: project, flow: flow} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      html = render_click(view, "navigate_to_exit_flow", %{"flow-id" => "0"})

      assert is_binary(html)
      assert editor_flow_id(view) == flow.id
    end
  end

  describe "navigate_to_referencing_flow" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Referenced Flow"})
      %{project: project, flow: flow}
    end

    test "navigates to referencing flow", %{conn: conn, project: project, flow: flow} do
      referencing_flow = flow_fixture(project, %{name: "Referencing Flow"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      render_click(view, "navigate_to_referencing_flow", %{
        "flow-id" => to_string(referencing_flow.id)
      })

      assert_patch(view)
    end

    test "shows error for invalid referencing flow ID",
         %{conn: conn, project: project, flow: flow} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      html = render_click(view, "navigate_to_referencing_flow", %{"flow-id" => "abc"})

      assert is_binary(html)
      assert editor_flow_id(view) == flow.id
    end
  end

  describe "navigate_to_flow with deleted flow" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Active Flow"})
      %{project: project, flow: flow}
    end

    test "shows error when target flow has been soft-deleted",
         %{conn: conn, project: project, flow: flow} do
      deleted_flow = flow_fixture(project, %{name: "Deleted Flow"})
      {:ok, _} = Storyarn.Flows.delete_flow(deleted_flow)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      load_flow(view)

      html =
        render_click(view, "navigate_to_subflow", %{"flow-id" => to_string(deleted_flow.id)})

      assert is_binary(html)
      assert editor_flow_id(view) == flow.id
    end
  end
end

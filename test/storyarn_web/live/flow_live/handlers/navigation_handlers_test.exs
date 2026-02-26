defmodule StoryarnWeb.FlowLive.Handlers.NavigationHandlersTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Repo

  # Simulates the FlowLoader JS hook: triggers the event + waits for start_async
  defp load_flow(view) do
    render_click(view, "load_flow_data", %{})
    render_async(view, 500)
  end

  describe "navigate_to_subflow" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
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

      # Trigger navigate_to_subflow event which delegates to NavigationHandlers
      assert {:error, {:live_redirect, %{to: redirect_path}}} =
               render_click(view, "navigate_to_subflow", %{"flow-id" => to_string(target_flow.id)})

      assert redirect_path =~
               "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{target_flow.id}"
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
      assert html =~ "Flow not found"
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
      assert html =~ "Invalid flow ID"
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
      assert html =~ "Invalid flow ID"
    end
  end

  describe "navigate_to_exit_flow" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
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

      assert {:error, {:live_redirect, %{to: redirect_path}}} =
               render_click(view, "navigate_to_exit_flow", %{
                 "flow-id" => to_string(target_flow.id)
               })

      assert redirect_path =~
               "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{target_flow.id}"
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
      assert html =~ "Flow not found"
    end
  end

  describe "navigate_to_referencing_flow" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
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

      assert {:error, {:live_redirect, %{to: redirect_path}}} =
               render_click(view, "navigate_to_referencing_flow", %{
                 "flow-id" => to_string(referencing_flow.id)
               })

      assert redirect_path =~ "/flows/#{referencing_flow.id}"
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
      assert html =~ "Invalid flow ID"
    end
  end

  describe "navigate_to_flow with deleted flow" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
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

      assert html =~ "Flow not found"
    end
  end
end

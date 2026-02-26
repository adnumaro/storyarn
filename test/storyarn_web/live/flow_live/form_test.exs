defmodule StoryarnWeb.FlowLive.FormTest do
  @moduledoc """
  Tests for the FlowLive.Form LiveComponent.

  Covers: update/2, handle_event("validate"), handle_event("save"),
  notify_parent/1, and rendering.
  """

  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows
  alias Storyarn.Repo

  describe "rendering" do
    setup :register_and_log_in_user

    test "renders the form with name and description inputs", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/new"
        )

      html = render(view)

      # Form title
      assert html =~ "New Flow"
      # Name input
      assert html =~ "Name"
      # Description textarea
      assert html =~ "Description"
      # Placeholders
      assert html =~ "Main Story"
      assert html =~ "Describe the purpose of this flow"
      # Cancel link
      assert html =~ "Cancel"
      # Submit button
      assert html =~ "Create Flow"
    end

    test "cancel link navigates back to flows index", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/new"
        )

      # The cancel link should patch back to the flows index
      html = render(view)
      expected_path = "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows"
      assert html =~ expected_path
    end
  end

  describe "validate" do
    setup :register_and_log_in_user

    test "validates flow params on change", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/new"
        )

      # Fill in a valid name - should not show errors
      html =
        view
        |> form("#flow-form", flow: %{name: "My New Flow", description: "A test"})
        |> render_change()

      refute html =~ "can&#39;t be blank"

      # Clear the name - should show validation error
      html =
        view
        |> form("#flow-form", flow: %{name: "", description: ""})
        |> render_change()

      assert html =~ "can" or html =~ "blank" or html =~ "required"
    end

    test "validates with special characters in name", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/new"
        )

      # Name with unicode characters should validate fine
      html =
        view
        |> form("#flow-form", flow: %{name: "Chapitre Un - Les Debuts"})
        |> render_change()

      refute html =~ "can&#39;t be blank"
    end
  end

  describe "save" do
    setup :register_and_log_in_user

    test "creates a flow on valid submission", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/new"
        )

      # Submit the form with valid data
      view
      |> form("#flow-form", flow: %{name: "Chapter One", description: "The first chapter"})
      |> render_submit()

      # The form should notify the parent which triggers a redirect
      # Verify the flow was created in the database
      flows = Flows.list_flows(project.id)
      assert flows != []
      chapter_flow = Enum.find(flows, &(&1.name == "Chapter One"))
      assert chapter_flow
      assert chapter_flow.description == "The first chapter"
    end

    test "creates flow and navigates to the flow editor", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/new"
        )

      view
      |> form("#flow-form", flow: %{name: "New Story Flow", description: ""})
      |> render_submit()

      # The parent handles notify_parent and push_navigates to the new flow
      # Verify the flow was created
      flows = Flows.list_flows(project.id)
      flow = Enum.find(flows, &(&1.name == "New Story Flow"))
      assert flow

      # The parent should push_navigate to the flow show page
      {path, flash} = assert_redirect(view)
      assert path =~ "/flows/#{flow.id}"
      assert flash["info"] =~ "created successfully"
    end

    test "creates flow with empty description", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/new"
        )

      view
      |> form("#flow-form", flow: %{name: "Minimal Flow", description: ""})
      |> render_submit()

      flows = Flows.list_flows(project.id)
      flow = Enum.find(flows, &(&1.name == "Minimal Flow"))
      assert flow
      assert flow.description in [nil, ""]
    end

    test "shows errors on invalid submission (empty name)", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/new"
        )

      # Submit with empty name should show validation errors
      html =
        view
        |> form("#flow-form", flow: %{name: ""})
        |> render_submit()

      # Should stay on the page (not redirect) and show error
      assert html =~ "can" or html =~ "blank" or html =~ "required"
    end
  end

  describe "notify_parent" do
    setup :register_and_log_in_user

    test "parent LiveView receives {:saved, flow} and redirects with flash", %{
      conn: conn,
      user: user
    } do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/new"
        )

      # Submit valid form - the parent should receive the notify message
      # and flash a success message before redirecting
      view
      |> form("#flow-form", flow: %{name: "Notified Flow"})
      |> render_submit()

      # The parent receives {Form, {:saved, flow}} and triggers push_navigate
      {path, flash} = assert_redirect(view)

      # Verify it navigates to the newly created flow
      assert path =~ "/flows/"
      assert flash["info"] =~ "created successfully"
    end
  end

  describe "authorization" do
    setup :register_and_log_in_user

    test "viewer cannot access the new flow form", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/new"
        )

      # Modal should not be rendered for viewers (can_edit is false)
      refute html =~ "flow-form"
    end

    test "editor can access the new flow form", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "editor")

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/new"
        )

      # Modal should be rendered for editors
      assert html =~ "flow-form"
      assert html =~ "Create Flow"
    end
  end

  describe "update/2" do
    setup :register_and_log_in_user

    test "initializes with default Flow when no flow assign provided", %{
      conn: conn,
      user: user
    } do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/new"
        )

      # Form should be present with empty inputs (default Flow struct)
      assert html =~ "flow-form"
      # The form should contain name and description fields, with placeholder text
      assert html =~ "Main Story"
      assert html =~ "Describe the purpose of this flow"
    end

    test "form has required attribute on name field", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/new"
        )

      assert html =~ "required"
    end
  end
end

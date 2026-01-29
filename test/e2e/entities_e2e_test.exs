defmodule StoryarnWeb.E2E.EntitiesTest do
  @moduledoc """
  E2E tests for entity-related flows.

  These tests use Playwright to run in a real browser.

  Run with: mix test.e2e
  """

  use PhoenixTest.Playwright.Case, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.EntitiesFixtures
  import Storyarn.ProjectsFixtures

  @moduletag :e2e

  defp authenticate_user(conn, user) do
    {token, _db_token} = generate_user_magic_link_token(user)

    conn
    |> visit("/users/log-in/#{token}")
    |> click_button("Keep me logged in on this device")
    |> assert_has("a", text: "Settings")
  end

  describe "entity templates" do
    test "can view empty templates page", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user, %{name: "My Project"})

      conn
      |> authenticate_user(user)
      |> visit("/projects/#{project.id}/templates")
      |> assert_has("h1", text: "Entity Templates")
      |> assert_has("p", text: "No templates yet")
    end

    test "can create default templates", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user)

      conn
      |> authenticate_user(user)
      |> visit("/projects/#{project.id}/templates")
      |> click_button("Create Default Templates")
      |> assert_has("h3", text: "Character")
      |> assert_has("h3", text: "Location")
      |> assert_has("h3", text: "Item")
      |> assert_has("h3", text: "Custom")
    end

    test "can create a new template", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user)

      conn
      |> authenticate_user(user)
      |> visit("/projects/#{project.id}/templates/new")
      |> fill_in("Name", with: "Hero")
      |> select("Type", option: "Character")
      |> fill_in("Description", with: "Main character template")
      |> click_button("Create Template")
      |> assert_has("h3", text: "Hero")
    end

    test "can edit a template", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user)
      template = template_fixture(project, %{name: "Original"})

      conn
      |> authenticate_user(user)
      |> visit("/projects/#{project.id}/templates/#{template.id}/edit")
      |> fill_in("Name", with: "Updated Template")
      |> click_button("Save Changes")
      |> assert_has("p", text: "updated successfully")
      |> assert_has("h3", text: "Updated Template")
    end

    test "can delete a template with no entities", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user)
      _template = template_fixture(project, %{name: "ToDelete"})

      conn
      |> authenticate_user(user)
      |> visit("/projects/#{project.id}/templates")
      |> assert_has("h3", text: "ToDelete")
      |> click_button("hero-trash")
      |> assert_has("p", text: "deleted successfully")
    end
  end

  describe "entities" do
    test "can view empty entities page", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user)

      conn
      |> authenticate_user(user)
      |> visit("/projects/#{project.id}/entities")
      |> assert_has("h1", text: "Entities")
      |> assert_has("p", text: "No entities yet")
    end

    test "can create a new entity", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user)
      _template = template_fixture(project, %{name: "Character", type: "character"})

      conn
      |> authenticate_user(user)
      |> visit("/projects/#{project.id}/entities")
      |> click_button("New Entity")
      |> click_link("Character")
      |> fill_in("Display Name", with: "John Doe")
      |> fill_in("Description", with: "The main protagonist")
      |> click_button("Create Entity")
      |> assert_has("h1 span", text: "John Doe")
    end

    test "can view entity details", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user)
      template = template_fixture(project, %{name: "Character"})

      entity =
        entity_fixture(project, template, %{
          display_name: "Jane Smith",
          description: "A brave warrior"
        })

      conn
      |> authenticate_user(user)
      |> visit("/projects/#{project.id}/entities/#{entity.id}")
      |> assert_has("h1 span", text: "Jane Smith")
      |> assert_has("p", text: "A brave warrior")
      |> assert_has("span", text: entity.technical_name)
    end

    test "can edit an entity", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user)
      template = template_fixture(project)
      entity = entity_fixture(project, template, %{display_name: "Original Name"})

      conn
      |> authenticate_user(user)
      |> visit("/projects/#{project.id}/entities/#{entity.id}/edit")
      |> fill_in("Display Name", with: "Updated Name")
      |> click_button("Save Changes")
      |> assert_has("p", text: "updated successfully")
      |> assert_has("h1 span", text: "Updated Name")
    end

    test "can delete an entity", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user)
      template = template_fixture(project)
      entity = entity_fixture(project, template, %{display_name: "ToDelete"})

      conn
      |> authenticate_user(user)
      |> visit("/projects/#{project.id}/entities/#{entity.id}")
      |> click_button("Delete")
      |> assert_path("/projects/#{project.id}/entities")
      |> assert_has("p", text: "deleted successfully")
    end

    test "can filter entities by type", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user)
      char_template = template_fixture(project, %{name: "Character", type: "character"})
      loc_template = template_fixture(project, %{name: "Location", type: "location"})
      _char = entity_fixture(project, char_template, %{display_name: "Hero"})
      _loc = entity_fixture(project, loc_template, %{display_name: "Forest"})

      conn
      |> authenticate_user(user)
      |> visit("/projects/#{project.id}/entities")
      |> assert_has("h3", text: "Hero")
      |> assert_has("h3", text: "Forest")
      |> select("select[name=type]", option: "Location")
      |> refute_has("h3", text: "Hero")
      |> assert_has("h3", text: "Forest")
    end

    test "can search entities", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user)
      template = template_fixture(project)
      _entity1 = entity_fixture(project, template, %{display_name: "John Doe"})
      _entity2 = entity_fixture(project, template, %{display_name: "Jane Smith"})

      conn
      |> authenticate_user(user)
      |> visit("/projects/#{project.id}/entities")
      |> assert_has("h3", text: "John Doe")
      |> assert_has("h3", text: "Jane Smith")
      |> fill_in("input[name=search]", with: "Jane")
      |> refute_has("h3", text: "John Doe")
      |> assert_has("h3", text: "Jane Smith")
    end
  end

  describe "variables" do
    test "can view empty variables page", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user)

      conn
      |> authenticate_user(user)
      |> visit("/projects/#{project.id}/variables")
      |> assert_has("h1", text: "Variables")
      |> assert_has("p", text: "No variables yet")
    end

    test "can create a new variable", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user)

      conn
      |> authenticate_user(user)
      |> visit("/projects/#{project.id}/variables/new")
      |> fill_in("Name", with: "player_health")
      |> select("Type", option: "Integer")
      |> fill_in("Default Value", with: "100")
      |> fill_in("Category", with: "player")
      |> click_button("Create Variable")
      |> assert_has("td", text: "player_health")
      |> assert_has("td", text: "100")
    end

    test "can edit a variable", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user)

      variable =
        variable_fixture(project, %{name: "original", description: "Original description"})

      conn
      |> authenticate_user(user)
      |> visit("/projects/#{project.id}/variables/#{variable.id}/edit")
      |> fill_in("Description", with: "Updated description")
      |> click_button("Save Changes")
      |> assert_has("p", text: "updated successfully")
    end

    test "can delete a variable", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user)
      _variable = variable_fixture(project, %{name: "to_delete"})

      conn
      |> authenticate_user(user)
      |> visit("/projects/#{project.id}/variables")
      |> assert_has("td", text: "to_delete")
      |> click_button("hero-trash")
      |> assert_has("p", text: "deleted successfully")
      |> refute_has("td", text: "to_delete")
    end

    test "variables are grouped by category", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user)
      _var1 = variable_fixture(project, %{name: "health", category: "player"})
      _var2 = variable_fixture(project, %{name: "score", category: "game"})

      conn
      |> authenticate_user(user)
      |> visit("/projects/#{project.id}/variables")
      |> assert_has("h3", text: "player")
      |> assert_has("h3", text: "game")
    end
  end
end

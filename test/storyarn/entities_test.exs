defmodule Storyarn.EntitiesTest do
  use Storyarn.DataCase

  alias Storyarn.Entities
  alias Storyarn.Entities.{Entity, EntityTemplate, Variable}

  import Storyarn.AccountsFixtures
  import Storyarn.EntitiesFixtures
  import Storyarn.ProjectsFixtures

  describe "entity_templates" do
    setup do
      user = user_fixture()
      project = project_fixture(user)
      %{project: project}
    end

    test "list_templates/1 returns all templates for a project", %{project: project} do
      template = template_fixture(project)
      templates = Entities.list_templates(project.id)

      assert length(templates) == 1
      assert hd(templates).id == template.id
    end

    test "list_templates/2 filters by type", %{project: project} do
      _character = template_fixture(project, %{type: "character", name: "Character"})
      location = template_fixture(project, %{type: "location", name: "Location"})

      templates = Entities.list_templates(project.id, type: "location")

      assert length(templates) == 1
      assert hd(templates).id == location.id
    end

    test "get_template/2 returns template by id", %{project: project} do
      template = template_fixture(project)

      assert found = Entities.get_template(project.id, template.id)
      assert found.id == template.id
    end

    test "get_template/2 returns nil for wrong project", %{project: project} do
      other_project = project_fixture()
      template = template_fixture(other_project)

      assert Entities.get_template(project.id, template.id) == nil
    end

    test "create_template/2 creates a template", %{project: project} do
      attrs = %{name: "Hero", type: "character", description: "Main character"}

      assert {:ok, template} = Entities.create_template(project, attrs)
      assert template.name == "Hero"
      assert template.type == "character"
      assert template.color == EntityTemplate.default_color("character")
      assert template.icon == EntityTemplate.default_icon("character")
    end

    test "create_template/2 validates required fields", %{project: project} do
      assert {:error, changeset} = Entities.create_template(project, %{name: ""})
      assert "can't be blank" in errors_on(changeset).name
    end

    test "create_template/2 validates type", %{project: project} do
      assert {:error, changeset} =
               Entities.create_template(project, %{name: "Test", type: "invalid"})

      assert "is invalid" in errors_on(changeset).type
    end

    test "create_template/2 enforces unique name per project", %{project: project} do
      _template = template_fixture(project, %{name: "Character"})

      assert {:error, changeset} =
               Entities.create_template(project, %{name: "Character", type: "character"})

      assert "has already been taken" in errors_on(changeset).name
    end

    test "update_template/2 updates a template", %{project: project} do
      template = template_fixture(project)

      assert {:ok, updated} = Entities.update_template(template, %{name: "Updated"})
      assert updated.name == "Updated"
    end

    test "delete_template/1 deletes a template", %{project: project} do
      template = template_fixture(project)

      assert {:ok, _} = Entities.delete_template(template)
      assert Entities.get_template(project.id, template.id) == nil
    end

    test "create_default_templates/1 creates one template per type", %{project: project} do
      assert {:ok, templates} = Entities.create_default_templates(project)
      assert length(templates) == length(EntityTemplate.types())

      types = Enum.map(templates, & &1.type)
      assert Enum.sort(types) == Enum.sort(EntityTemplate.types())
    end

    test "change_template/2 returns a changeset", %{project: project} do
      template = template_fixture(project)

      assert %Ecto.Changeset{} = Entities.change_template(template)
    end
  end

  describe "entities" do
    setup do
      user = user_fixture()
      project = project_fixture(user)
      template = template_fixture(project)
      %{project: project, template: template}
    end

    test "list_entities/2 returns all entities for a project", %{
      project: project,
      template: template
    } do
      entity = entity_fixture(project, template)
      entities = Entities.list_entities(project.id)

      assert length(entities) == 1
      assert hd(entities).id == entity.id
    end

    test "list_entities/2 filters by template_id", %{project: project, template: template} do
      other_template = template_fixture(project, %{name: "Other", type: "item"})
      _entity1 = entity_fixture(project, template)
      entity2 = entity_fixture(project, other_template)

      entities = Entities.list_entities(project.id, template_id: other_template.id)

      assert length(entities) == 1
      assert hd(entities).id == entity2.id
    end

    test "list_entities/2 filters by type", %{project: project, template: template} do
      location_template = template_fixture(project, %{name: "Location", type: "location"})
      _character = entity_fixture(project, template)
      location = entity_fixture(project, location_template)

      entities = Entities.list_entities(project.id, type: "location")

      assert length(entities) == 1
      assert hd(entities).id == location.id
    end

    test "list_entities/2 searches by display_name", %{project: project, template: template} do
      _entity1 = entity_fixture(project, template, %{display_name: "John Doe"})
      entity2 = entity_fixture(project, template, %{display_name: "Jane Smith"})

      entities = Entities.list_entities(project.id, search: "Jane")

      assert length(entities) == 1
      assert hd(entities).id == entity2.id
    end

    test "list_entities/2 searches by technical_name", %{project: project, template: template} do
      entity1 =
        entity_fixture(project, template, %{display_name: "John", technical_name: "john_main"})

      _entity2 =
        entity_fixture(project, template, %{display_name: "Jane", technical_name: "jane_side"})

      entities = Entities.list_entities(project.id, search: "main")

      assert length(entities) == 1
      assert hd(entities).id == entity1.id
    end

    test "get_entity/2 returns entity by id", %{project: project, template: template} do
      entity = entity_fixture(project, template)

      assert found = Entities.get_entity(project.id, entity.id)
      assert found.id == entity.id
      assert found.template.id == template.id
    end

    test "get_entity/2 returns nil for wrong project", %{template: template} do
      other_project = project_fixture()
      entity = entity_fixture(other_project, template_fixture(other_project))

      assert Entities.get_entity(other_project.id, entity.id) != nil
      assert Entities.get_entity(template.project_id, entity.id) == nil
    end

    test "create_entity/3 creates an entity", %{project: project, template: template} do
      attrs = %{display_name: "Hero", description: "The main hero"}

      assert {:ok, entity} = Entities.create_entity(project, template, attrs)
      assert entity.display_name == "Hero"
      assert entity.technical_name == "hero"
      assert entity.template_id == template.id
    end

    test "create_entity/3 generates technical_name from display_name", %{
      project: project,
      template: template
    } do
      attrs = %{display_name: "John Doe the Third!"}

      assert {:ok, entity} = Entities.create_entity(project, template, attrs)
      assert entity.technical_name == "john_doe_the_third"
    end

    test "create_entity/3 preserves provided technical_name", %{
      project: project,
      template: template
    } do
      attrs = %{display_name: "John", technical_name: "custom_name"}

      assert {:ok, entity} = Entities.create_entity(project, template, attrs)
      assert entity.technical_name == "custom_name"
    end

    test "create_entity/3 validates technical_name format", %{
      project: project,
      template: template
    } do
      attrs = %{display_name: "Test", technical_name: "Invalid Name"}

      assert {:error, changeset} = Entities.create_entity(project, template, attrs)
      assert errors_on(changeset).technical_name != []
    end

    test "create_entity/3 enforces unique technical_name per project", %{
      project: project,
      template: template
    } do
      _entity = entity_fixture(project, template, %{technical_name: "hero"})

      assert {:error, changeset} =
               Entities.create_entity(project, template, %{
                 display_name: "Another",
                 technical_name: "hero"
               })

      assert "has already been taken" in errors_on(changeset).technical_name
    end

    test "update_entity/2 updates an entity", %{project: project, template: template} do
      entity = entity_fixture(project, template)

      assert {:ok, updated} = Entities.update_entity(entity, %{display_name: "Updated"})
      assert updated.display_name == "Updated"
    end

    test "update_entity/2 allows updating data", %{project: project, template: template} do
      entity = entity_fixture(project, template)

      assert {:ok, updated} = Entities.update_entity(entity, %{data: %{"health" => 100}})
      assert updated.data == %{"health" => 100}
    end

    test "delete_entity/1 deletes an entity", %{project: project, template: template} do
      entity = entity_fixture(project, template)

      assert {:ok, _} = Entities.delete_entity(entity)
      assert Entities.get_entity(project.id, entity.id) == nil
    end

    test "count_entities_by_template/1 returns counts", %{project: project, template: template} do
      other_template = template_fixture(project, %{name: "Other", type: "item"})
      _entity1 = entity_fixture(project, template)
      _entity2 = entity_fixture(project, template)
      _entity3 = entity_fixture(project, other_template)

      counts = Entities.count_entities_by_template(project.id)

      assert counts[template.id] == 2
      assert counts[other_template.id] == 1
    end

    test "change_entity/2 returns a changeset", %{project: project, template: template} do
      entity = entity_fixture(project, template)

      assert %Ecto.Changeset{} = Entities.change_entity(entity)
    end
  end

  describe "Entity.generate_technical_name/1" do
    test "converts display name to snake_case" do
      assert Entity.generate_technical_name("John Doe") == "john_doe"
    end

    test "removes special characters" do
      assert Entity.generate_technical_name("Hello, World!") == "hello_world"
    end

    test "handles names starting with numbers" do
      assert Entity.generate_technical_name("123 Test") == "entity_123_test"
    end

    test "handles empty string" do
      assert Entity.generate_technical_name("") == ""
    end

    test "handles nil" do
      assert Entity.generate_technical_name(nil) == ""
    end
  end

  describe "variables" do
    setup do
      user = user_fixture()
      project = project_fixture(user)
      %{project: project}
    end

    test "list_variables/2 returns all variables for a project", %{project: project} do
      variable = variable_fixture(project)
      variables = Entities.list_variables(project.id)

      assert length(variables) == 1
      assert hd(variables).id == variable.id
    end

    test "list_variables/2 filters by category", %{project: project} do
      _var1 = variable_fixture(project, %{name: "var1", category: "player"})
      var2 = variable_fixture(project, %{name: "var2", category: "game"})

      variables = Entities.list_variables(project.id, category: "game")

      assert length(variables) == 1
      assert hd(variables).id == var2.id
    end

    test "list_variables/2 filters by type", %{project: project} do
      _var1 = variable_fixture(project, %{name: "var1", type: "boolean"})
      var2 = variable_fixture(project, %{name: "var2", type: "integer", default_value: "42"})

      variables = Entities.list_variables(project.id, type: "integer")

      assert length(variables) == 1
      assert hd(variables).id == var2.id
    end

    test "get_variable/2 returns variable by id", %{project: project} do
      variable = variable_fixture(project)

      assert found = Entities.get_variable(project.id, variable.id)
      assert found.id == variable.id
    end

    test "create_variable/2 creates a variable", %{project: project} do
      attrs = %{name: "player_health", type: "integer", default_value: "100"}

      assert {:ok, variable} = Entities.create_variable(project, attrs)
      assert variable.name == "player_health"
      assert variable.type == "integer"
      assert variable.default_value == "100"
    end

    test "create_variable/2 sets default value based on type", %{project: project} do
      assert {:ok, bool_var} =
               Entities.create_variable(project, %{name: "flag", type: "boolean"})

      assert bool_var.default_value == "false"

      assert {:ok, int_var} =
               Entities.create_variable(project, %{name: "count", type: "integer"})

      assert int_var.default_value == "0"
    end

    test "create_variable/2 validates name format", %{project: project} do
      assert {:error, changeset} =
               Entities.create_variable(project, %{name: "Invalid Name", type: "boolean"})

      assert errors_on(changeset).name != []
    end

    test "create_variable/2 validates type", %{project: project} do
      assert {:error, changeset} =
               Entities.create_variable(project, %{name: "test", type: "invalid"})

      assert "is invalid" in errors_on(changeset).type
    end

    test "create_variable/2 validates default_value matches type", %{project: project} do
      assert {:error, changeset} =
               Entities.create_variable(project, %{
                 name: "test",
                 type: "integer",
                 default_value: "not_a_number"
               })

      assert errors_on(changeset).default_value != []
    end

    test "create_variable/2 enforces unique name per project", %{project: project} do
      _variable = variable_fixture(project, %{name: "health"})

      assert {:error, changeset} =
               Entities.create_variable(project, %{name: "health", type: "integer"})

      assert "has already been taken" in errors_on(changeset).name
    end

    test "update_variable/2 updates a variable", %{project: project} do
      variable = variable_fixture(project)

      assert {:ok, updated} = Entities.update_variable(variable, %{description: "Updated"})
      assert updated.description == "Updated"
    end

    test "delete_variable/1 deletes a variable", %{project: project} do
      variable = variable_fixture(project)

      assert {:ok, _} = Entities.delete_variable(variable)
      assert Entities.get_variable(project.id, variable.id) == nil
    end

    test "list_variable_categories/1 returns unique categories", %{project: project} do
      _var1 = variable_fixture(project, %{name: "var1", category: "player"})
      _var2 = variable_fixture(project, %{name: "var2", category: "game"})
      _var3 = variable_fixture(project, %{name: "var3", category: "player"})
      _var4 = variable_fixture(project, %{name: "var4", category: nil})

      categories = Entities.list_variable_categories(project.id)

      assert length(categories) == 2
      assert "player" in categories
      assert "game" in categories
    end

    test "change_variable/2 returns a changeset", %{project: project} do
      variable = variable_fixture(project)

      assert %Ecto.Changeset{} = Entities.change_variable(variable)
    end
  end

  describe "Variable.parse_value/2" do
    test "parses boolean values" do
      assert {:ok, "true"} = Variable.parse_value("boolean", "true")
      assert {:ok, "false"} = Variable.parse_value("boolean", "false")
      assert {:error, _} = Variable.parse_value("boolean", "yes")
    end

    test "parses integer values" do
      assert {:ok, "42"} = Variable.parse_value("integer", "42")
      assert {:ok, "-10"} = Variable.parse_value("integer", "-10")
      assert {:error, _} = Variable.parse_value("integer", "3.14")
      assert {:error, _} = Variable.parse_value("integer", "abc")
    end

    test "parses float values" do
      assert {:ok, "3.14"} = Variable.parse_value("float", "3.14")
      assert {:ok, "42"} = Variable.parse_value("float", "42")
      assert {:error, _} = Variable.parse_value("float", "abc")
    end

    test "accepts any string value" do
      assert {:ok, "hello"} = Variable.parse_value("string", "hello")
      assert {:ok, ""} = Variable.parse_value("string", "")
    end
  end
end

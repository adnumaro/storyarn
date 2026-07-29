defmodule Storyarn.CommandPaletteTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures

  alias Storyarn.CommandPalette
  alias Storyarn.CommandPalette.Definition
  alias Storyarn.CommandPalette.Operation
  alias Storyarn.CommandPalette.Registry
  alias Storyarn.Repo

  describe "operation registry" do
    test "contains exactly the delivered operations with unique, validated contracts" do
      definitions = Registry.all()
      ids = Enum.map(definitions, & &1.id)

      assert ids ==
               ~w(goto variable_definition variable_usages entity_usages flow_callers create delete run_command open_view)

      assert Enum.uniq(ids) == ids
      assert Definition.latency_budget_ms(:instant) == 150
      assert Definition.latency_budget_ms(:interactive) == nil

      assert Map.new(definitions, &{&1.id, &1.requires_project}) == %{
               "goto" => false,
               "variable_definition" => true,
               "variable_usages" => true,
               "entity_usages" => true,
               "flow_callers" => true,
               "create" => false,
               "delete" => false,
               "run_command" => false,
               "open_view" => false
             }

      for definition <- definitions do
        assert definition.domain in Definition.enum_values(:domain)
        assert definition.latency in Definition.enum_values(:latency)
        assert definition.authorization in Definition.enum_values(:authorization)
        assert definition.result_type in Definition.enum_values(:result_type)

        for parameter <- definition.parameters do
          assert parameter.type in Definition.enum_values(:parameter_type)
          assert parameter.completion_source in Definition.enum_values(:completion_source)
          assert parameter.completion_mode in Definition.enum_values(:completion_mode)
        end
      end

      assert Map.new(
               for definition <- definitions,
                   parameter <- definition.parameters,
                   do: {{definition.id, parameter.id}, parameter.completion_mode}
             ) ==
               %{
                 {"goto", "destination"} => :server,
                 {"variable_definition", "variable"} => :server,
                 {"variable_usages", "variable"} => :server,
                 {"entity_usages", "entity"} => :server,
                 {"flow_callers", "flow"} => :server,
                 {"create", "entity_type"} => :client,
                 {"create", "project"} => :client,
                 {"delete", "entity"} => :server,
                 {"run_command", "command"} => :client,
                 {"open_view", "destination"} => :client
               }
    end

    test "serializes the generated help catalog using the LiveVue contract" do
      catalog = CommandPalette.operation_catalog()

      assert Enum.map(catalog, & &1.id) ==
               ~w(goto variable_definition variable_usages entity_usages flow_callers create delete run_command open_view)

      assert Jason.encode!(catalog)

      assert goto = Enum.find(catalog, &(&1.id == "goto"))
      assert goto.resultType == "navigation"
      assert goto.authorization == "view"
      assert goto.requiresProject == false

      assert Enum.find(catalog, &(&1.id == "variable_definition")).requiresProject == true

      assert [
               %{
                 id: "destination",
                 type: "destination",
                 completionSource: "navigation",
                 completionMode: "server",
                 required: true,
                 labelKey: "palette.operations.goto.parameters.destination"
               }
             ] = goto.parameters

      assert goto.phrase == [
               %{kind: "text", textKey: "palette.operations.goto.phrase.prefix"},
               %{kind: "parameter", parameterId: "destination"}
             ]

      assert goto.help == %{
               labelKey: "palette.operations.goto.label",
               descriptionKey: "palette.operations.goto.description",
               exampleKey: "palette.operations.goto.example",
               pattern: nil
             }
    end

    test "every generated help key resolves to non-empty English and Spanish copy" do
      definitions = Registry.all()

      for locale <- ~w(en es) do
        messages =
          "assets/app/locales/#{locale}/palette.json"
          |> File.read!()
          |> Jason.decode!()

        for definition <- definitions,
            translation_key <- definition_translation_keys(definition) do
          value = get_in(messages, String.split(translation_key, "."))

          assert is_binary(value) and String.trim(value) != "",
                 "missing #{locale} translation for #{translation_key}"
        end
      end
    end

    test "rejects unknown enum values and unknown operation parameters" do
      definition = hd(Registry.all())

      assert_raise ArgumentError, ~r/invalid latency/, fn ->
        Definition.validate!(%{definition | latency: :eventually})
      end

      invalid_parameter =
        definition.parameters
        |> hd()
        |> Map.put(:completion_mode, :remote)

      assert_raise ArgumentError, ~r/invalid parameters/, fn ->
        Definition.validate!(%{definition | parameters: [invalid_parameter]})
      end

      assert_raise ArgumentError, ~r/invalid requires_project/, fn ->
        Definition.validate!(%{definition | requires_project: :sometimes})
      end

      assert {:ok, %{completion_source: :navigation, completion_mode: :server}} =
               Registry.fetch_parameter("goto", "destination")

      assert {:ok, %{source: :navigation, mode: :server}} =
               CommandPalette.parameter_completion("goto", "destination")

      assert :error = Registry.fetch_parameter("goto", "forged")
      assert :error = Registry.fetch_parameter("forged", "destination")
      assert CommandPalette.registered_operation_id?("goto")
      refute CommandPalette.registered_operation_id?("forged")
      refute CommandPalette.registered_operation_id?(123)
    end
  end

  defp definition_translation_keys(definition) do
    help_keys = [
      definition.help.label_key,
      definition.help.description_key,
      definition.help.example_key
    ]

    parameter_keys = Enum.map(definition.parameters, & &1.label_key)

    phrase_keys =
      Enum.flat_map(definition.phrase, fn
        %{kind: :text, text_key: text_key} -> [text_key]
        %{kind: :parameter} -> []
      end)

    ["palette.operation_domains.#{definition.domain}" | help_keys ++ parameter_keys ++ phrase_keys]
  end

  test "commits a successful mutation and its replay result atomically" do
    scope = user_scope_fixture()
    execution_id = "create-once"

    assert {%{url: "/sheets/123"}, :broadcast} =
             CommandPalette.run(
               scope,
               "palette_create",
               execution_id,
               fn ->
                 send(self(), :executed)
                 {%{url: "/sheets/123"}, :broadcast}
               end,
               fn _reason -> %{error: "failed"} end
             )

    assert_receive :executed

    assert {%{url: "/sheets/123"}, nil} =
             CommandPalette.run(
               scope,
               "palette_create",
               execution_id,
               fn ->
                 send(self(), :executed_twice)
                 {%{url: "/sheets/999"}, :broadcast}
               end,
               fn _reason -> %{error: "failed"} end
             )

    refute_receive :executed_twice
  end

  test "preserves rollback reasons and allows a failed execution id to be retried" do
    scope = user_scope_fixture()
    execution_id = "retry-after-limit"

    assert {%{error: "limit_reached"}, nil} =
             CommandPalette.run(
               scope,
               "palette_create",
               execution_id,
               fn -> Repo.rollback({:limit_reached, %{limit: 1}}) end,
               fn
                 {:limit_reached, _details} -> %{error: "limit_reached"}
                 _reason -> %{error: "failed"}
               end
             )

    refute Repo.get_by(Operation,
             user_id: scope.user.id,
             event: "palette_create",
             operation_id: execution_id
           )

    assert {%{url: "/sheets/123"}, :broadcast} =
             CommandPalette.run(
               scope,
               "palette_create",
               execution_id,
               fn -> {%{url: "/sheets/123"}, :broadcast} end,
               fn _reason -> %{error: "failed"} end
             )
  end
end

defmodule Storyarn.CommandPaletteTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures

  alias Storyarn.CommandPalette
  alias Storyarn.CommandPalette.Definition
  alias Storyarn.CommandPalette.Operation
  alias Storyarn.CommandPalette.Registry
  alias Storyarn.Repo

  describe "operation registry" do
    test "contains exactly the PR-2 operations with unique, validated contracts" do
      definitions = Registry.all()
      ids = Enum.map(definitions, & &1.id)

      assert ids == ~w(goto create delete run_command open_view)
      assert Enum.uniq(ids) == ids
      assert Definition.latency_budget_ms(:instant) == 150
      assert Definition.latency_budget_ms(:interactive) == nil

      for definition <- definitions do
        assert definition.domain in Definition.enum_values(:domain)
        assert definition.latency in Definition.enum_values(:latency)
        assert definition.authorization in Definition.enum_values(:authorization)
        assert definition.result_type in Definition.enum_values(:result_type)

        for parameter <- definition.parameters do
          assert parameter.type in Definition.enum_values(:parameter_type)
          assert parameter.completion_source in Definition.enum_values(:completion_source)
        end
      end
    end

    test "serializes the generated help catalog using the LiveVue contract" do
      catalog = CommandPalette.operation_catalog()

      assert Enum.map(catalog, & &1.id) == ~w(goto create delete run_command open_view)
      assert Jason.encode!(catalog)

      assert goto = Enum.find(catalog, &(&1.id == "goto"))
      assert goto.resultType == "navigation"
      assert goto.authorization == "view"

      assert [
               %{
                 id: "destination",
                 type: "destination",
                 completionSource: "navigation",
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

      assert {:ok, %{completion_source: :navigation}} =
               Registry.fetch_parameter("goto", "destination")

      assert :error = Registry.fetch_parameter("goto", "forged")
      assert :error = Registry.fetch_parameter("forged", "destination")
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

    help_keys ++ parameter_keys ++ phrase_keys
  end

  test "commits a successful mutation and its replay result atomically" do
    scope = user_scope_fixture()
    operation_id = "create-once"

    assert {%{url: "/sheets/123"}, :broadcast} =
             CommandPalette.run(
               scope,
               "palette_create",
               operation_id,
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
               operation_id,
               fn ->
                 send(self(), :executed_twice)
                 {%{url: "/sheets/999"}, :broadcast}
               end,
               fn _reason -> %{error: "failed"} end
             )

    refute_receive :executed_twice
  end

  test "preserves rollback reasons and allows a failed operation id to be retried" do
    scope = user_scope_fixture()
    operation_id = "retry-after-limit"

    assert {%{error: "limit_reached"}, nil} =
             CommandPalette.run(
               scope,
               "palette_create",
               operation_id,
               fn -> Repo.rollback({:limit_reached, %{limit: 1}}) end,
               fn
                 {:limit_reached, _details} -> %{error: "limit_reached"}
                 _reason -> %{error: "failed"}
               end
             )

    refute Repo.get_by(Operation,
             user_id: scope.user.id,
             event: "palette_create",
             operation_id: operation_id
           )

    assert {%{url: "/sheets/123"}, :broadcast} =
             CommandPalette.run(
               scope,
               "palette_create",
               operation_id,
               fn -> {%{url: "/sheets/123"}, :broadcast} end,
               fn _reason -> %{error: "failed"} end
             )
  end
end

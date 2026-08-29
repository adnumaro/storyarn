defmodule Storyarn.Architecture.PlatformFacadeContractTest do
  use ExUnit.Case, async: true

  alias Storyarn.Platform

  @public_contract [
    analytics_frontend_config: 1,
    cast_onboarding_tutorial: 1,
    complete_onboarding_tutorial: 2,
    deliver_async_result: 3,
    deliver_content_activity: 5,
    deliver_content_activity_by_ids: 5,
    deliver_scoped_async_result: 3,
    known_product_metric_project_subtype?: 2,
    known_product_metric_project_type?: 1,
    list_notifications: 1,
    list_notifications: 2,
    mark_all_notifications_read: 1,
    mark_notification_read: 2,
    onboarding_pending?: 2,
    onboarding_summary: 1,
    onboarding_tutorials: 0,
    product_metric_project_options: 0,
    product_metric_project_subtypes: 0,
    product_metric_project_subtypes: 1,
    product_metric_project_types: 0,
    publish_notification_delivery: 1,
    react_to_event: 4,
    restart_all_onboarding_tutorials: 1,
    restart_onboarding_tutorial: 2,
    subscribe_notifications: 1,
    track_analytics: 2,
    track_analytics: 3,
    unread_notification_count: 1
  ]

  @public_types ~w(notification_delivery_outcome onboarding_summary)a

  # Advanced deliberately when ENG-112 moved the complete commercial contract
  # into Storyarn.Commercial. These hashes protect Platform's remaining
  # semantic signatures, defaults, documentation, types, and specs.
  @docs_digest "4089846cb21bfe7a6e320041d6a0675c6a4f8340752a3619b903df7e2d3c6652"
  @types_digest "b16240403430379604117214f246a929a2c9493712e2244ac7020191167c00f0"
  @specs_digest "44e9f2fa16d6e3fd7429fb9a04b3f1965ead40c89edf3258626724cbd066264c"

  test "the root facade preserves every established function and arity" do
    public_functions =
      :functions
      |> Platform.__info__()
      |> Enum.reject(fn {name, _arity} -> name in [:module_info, :__info__] end)
      |> MapSet.new()

    assert public_functions == MapSet.new(@public_contract)
  end

  test "the root facade is declarative and enters implementation through capability facades" do
    source = File.read!("lib/storyarn/platform.ex")

    refute Regex.match?(~r/^\s*def(?:p|macro|macrop)?\s/m, source)
    assert Regex.scan(~r/^\s*defdelegate\s/m, source) != []
    refute source =~ "Storyarn.Repo"
    refute source =~ "Oban.insert"

    targets =
      ~r/\bto:\s*([A-Z][A-Za-z0-9_.]*)/
      |> Regex.scan(source, capture: :all_but_first)
      |> List.flatten()
      |> Enum.uniq()
      |> Enum.sort()

    assert targets == ~w(Notifications Onboarding Reactions)
  end

  test "the compiled facade preserves docs and semantic default signatures" do
    assert {:docs_v1, _, _, _, _, _, entries} = Code.fetch_docs(Platform)

    function_docs =
      Enum.flat_map(entries, fn
        {{:function, name, arity}, _, signatures, doc, metadata} ->
          [{name, arity, signatures, doc, Map.get(metadata, :defaults, 0)}]

        _other ->
          []
      end)

    status_counts =
      Enum.frequencies_by(function_docs, fn {_name, _arity, _signatures, doc, _defaults} ->
        case doc do
          :hidden -> :hidden
          :none -> :none
          %{} -> :documented
        end
      end)

    represented_arities =
      function_docs
      |> Enum.flat_map(fn {name, arity, _signatures, _doc, defaults} ->
        Enum.map((arity - defaults)..arity, &{name, &1})
      end)
      |> MapSet.new()

    assert length(function_docs) == 26
    assert status_counts == %{documented: 26}
    assert represented_arities == MapSet.new(@public_contract)
    assert digest(Enum.sort(function_docs)) == @docs_digest
  end

  test "the compiled facade preserves its stable public types" do
    assert {:ok, types} = Code.Typespec.fetch_types(Platform)

    type_names =
      types
      |> Enum.map(fn {_kind, {name, _definition, _args}} -> name end)
      |> Enum.sort()

    normalized_types =
      types
      |> Enum.map(fn {kind, type} ->
        {kind, type |> Code.Typespec.type_to_quoted() |> Macro.to_string()}
      end)
      |> Enum.sort()

    assert type_names == Enum.sort(@public_types)
    assert digest(normalized_types) == @types_digest
  end

  test "the compiled facade preserves every established public spec" do
    assert {:ok, specs} = Code.Typespec.fetch_specs(Platform)

    normalized_specs =
      specs
      |> Enum.flat_map(fn {{name, arity}, definitions} ->
        Enum.map(definitions, fn definition ->
          quoted = Code.Typespec.spec_to_quoted(name, definition)
          {name, arity, Macro.to_string(quoted)}
        end)
      end)
      |> Enum.sort()

    assert length(normalized_specs) == 26
    assert digest(normalized_specs) == @specs_digest
  end

  defp digest(term) do
    :sha256
    |> :crypto.hash(:erlang.term_to_binary(term))
    |> Base.encode16(case: :lower)
  end
end

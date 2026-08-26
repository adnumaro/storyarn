defmodule Storyarn.Scenes.Health.Contracts.LabelParityTest do
  @moduledoc """
  Guards the Scene-owned health code-to-label contract without coupling it to
  another tool's vocabulary.
  """

  use ExUnit.Case, async: true

  alias Storyarn.Scenes.Health.Rules.Checker, as: HealthChecker

  @project_root Path.expand("../../../../..", __DIR__)
  @domain "scenes"
  @locales ~w(en es)
  @chrome_keys ~w(errors info looks_great review warnings)

  test "every emitted finding has one nonblank label in every locale" do
    for locale <- @locales do
      labels = labels(locale)

      assert uncovered_codes(HealthChecker.codes(), labels) == []
      assert orphan_labels(HealthChecker.codes(), labels) == []
      assert blank_labels(labels) == []
    end
  end

  test "the Scene health popover chrome exists in every locale" do
    for locale <- @locales do
      health = health_catalog(locale)
      assert Enum.reject(@chrome_keys, &present_string?(Map.get(health, &1))) == []
    end
  end

  test "dashboard issue labels exactly cover Scene findings" do
    for locale <- @locales do
      labels = issue_type_labels(locale)

      assert uncovered_codes(HealthChecker.codes(), labels) == []
      assert orphan_labels(HealthChecker.codes(), labels) == []
      assert blank_labels(labels) == []

      refute Enum.any?(labels, fn {_code, label} ->
               String.contains?(label, "{") or String.contains?(label, "}")
             end)
    end
  end

  test "Spanish issue labels do not fall back to raw code names" do
    for {code, label} <- issue_type_labels("es") do
      normalized_label = label |> String.trim() |> String.downcase()
      normalized_code = String.downcase(code)

      refute normalized_label in [normalized_code, String.replace(normalized_code, "_", " ")]
    end
  end

  test "the parity guard detects uncovered, orphaned, and blank labels" do
    assert uncovered_codes([:__uncovered_control__ | HealthChecker.codes()], labels("en")) == [
             "__uncovered_control__"
           ]

    assert orphan_labels(
             HealthChecker.codes(),
             Map.put(labels("en"), "__orphan_control__", "Orphan")
           ) == ["__orphan_control__"]

    assert blank_labels(Map.put(labels("en"), "__blank_control__", "   ")) == [
             "__blank_control__"
           ]
  end

  defp uncovered_codes(codes, labels) do
    codes |> Enum.map(&to_string/1) |> Enum.reject(&Map.has_key?(labels, &1)) |> Enum.sort()
  end

  defp orphan_labels(codes, labels) do
    known = MapSet.new(codes, &to_string/1)
    labels |> Map.keys() |> Enum.reject(&MapSet.member?(known, &1)) |> Enum.sort()
  end

  defp blank_labels(labels) do
    labels
    |> Enum.reject(fn {_code, label} -> present_string?(label) end)
    |> Enum.map(fn {code, _label} -> code end)
    |> Enum.sort()
  end

  defp present_string?(value), do: is_binary(value) and String.trim(value) != ""
  defp labels(locale), do: Map.fetch!(health_catalog(locale), "findings")
  defp issue_type_labels(locale), do: Map.fetch!(health_catalog(locale), "issue_types")

  defp health_catalog(locale) do
    @project_root
    |> Path.join("assets/app/locales/#{locale}/#{@domain}.json")
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!(@domain)
    |> Map.fetch!("health")
  end
end

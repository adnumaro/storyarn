defmodule Storyarn.HealthLabelParityTest do
  @moduledoc """
  Guards the code↔label contract every health surface depends on.

  All three checkers declare their vocabulary once in `@severity_by_code` and
  expose it through `codes/0`; the Vue side turns each code into a sentence via
  `<domain>.health.findings.<code>`. Nothing connected the two: adding a code
  and forgetting its label shipped a raw atom to the user, and
  `Storyarn.Publication.LocalesTest` could not catch it because it only compares
  en↔es leaf paths — a code missing from *both* locales passes there.

  The code list comes from `codes/0` rather than a hardcoded copy, so this guard
  cannot drift from the catalog it guards.
  """

  use ExUnit.Case, async: true

  @project_root Path.expand("../..", __DIR__)
  @locales ~w(en es)

  @domains [
    {"flows", Storyarn.Flows.HealthChecker},
    {"sheets", Storyarn.Sheets.HealthChecker},
    {"scenes", Storyarn.Scenes.HealthChecker}
  ]

  # `HealthStatusPopover.vue` resolves these five off `translationPrefix`, so
  # they are as required as the findings themselves.
  @chrome_keys ~w(errors info looks_great review warnings)

  describe "finding labels" do
    test "every code a checker can emit has a label in every locale" do
      for {domain, checker} <- @domains, locale <- @locales do
        uncovered = uncovered_codes(checker.codes(), labels(domain, locale))

        assert uncovered == [],
               "assets/app/locales/#{locale}/#{domain}.json has no label for " <>
                 report(domain, uncovered)
      end
    end

    test "every finding label maps to a code the checker still emits" do
      for {domain, checker} <- @domains, locale <- @locales do
        orphans = orphan_labels(checker.codes(), labels(domain, locale))

        assert orphans == [],
               "assets/app/locales/#{locale}/#{domain}.json labels codes " <>
                 "#{inspect(checker)} no longer emits: " <> report(domain, orphans)
      end
    end

    test "no finding label is blank" do
      for {domain, _checker} <- @domains, locale <- @locales do
        blank = blank_labels(labels(domain, locale))

        assert blank == [],
               "assets/app/locales/#{locale}/#{domain}.json leaves blank " <>
                 report(domain, blank)
      end
    end

    test "every domain ships the chrome the shared popover reads" do
      for {domain, _checker} <- @domains, locale <- @locales do
        health = health_catalog(domain, locale)
        missing = Enum.reject(@chrome_keys, &present_string?(Map.get(health, &1)))

        assert missing == [],
               "assets/app/locales/#{locale}/#{domain}.json is missing the " <>
                 "HealthStatusPopover chrome " <>
                 Enum.map_join(missing, ", ", &"#{domain}.health.#{&1}")
      end
    end
  end

  # Positive controls: the assertions above pass today, so each one is fed a
  # deliberately broken input to prove it can still fail and names the offender.
  describe "the guard itself" do
    test "reports a code with no label, per domain" do
      for {domain, checker} <- @domains do
        codes = [:__uncovered_control__ | checker.codes()]

        assert uncovered_codes(codes, labels(domain, "en")) == ["__uncovered_control__"]
        assert uncovered_codes(codes, labels(domain, "es")) == ["__uncovered_control__"]
      end
    end

    test "reports a label whose code no longer exists, per domain" do
      for {domain, checker} <- @domains do
        polluted = Map.put(labels(domain, "en"), "__orphan_control__", "Orphaned sentence")

        assert orphan_labels(checker.codes(), polluted) == ["__orphan_control__"]
      end
    end

    test "reports a blank label, per domain" do
      for {domain, _checker} <- @domains do
        polluted = Map.put(labels(domain, "en"), "__blank_control__", "   ")

        assert blank_labels(polluted) == ["__blank_control__"]
      end
    end
  end

  defp report(domain, codes) do
    Enum.map_join(codes, ", ", &"#{domain}.health.findings.#{&1}")
  end

  defp uncovered_codes(codes, labels) do
    codes
    |> Enum.map(&to_string/1)
    |> Enum.reject(&Map.has_key?(labels, &1))
    |> Enum.sort()
  end

  defp orphan_labels(codes, labels) do
    known = MapSet.new(codes, &to_string/1)

    labels
    |> Map.keys()
    |> Enum.reject(&MapSet.member?(known, &1))
    |> Enum.sort()
  end

  defp blank_labels(labels) do
    labels
    |> Enum.reject(fn {_code, label} -> present_string?(label) end)
    |> Enum.map(fn {code, _label} -> code end)
    |> Enum.sort()
  end

  defp present_string?(value), do: is_binary(value) and String.trim(value) != ""

  defp labels(domain, locale), do: Map.fetch!(health_catalog(domain, locale), "findings")

  defp health_catalog(domain, locale) do
    @project_root
    |> Path.join("assets/app/locales/#{locale}/#{domain}.json")
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!(domain)
    |> Map.fetch!("health")
  end
end

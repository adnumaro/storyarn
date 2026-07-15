defmodule Storyarn.Imports.SourceBundleTest do
  use ExUnit.Case, async: true

  alias Storyarn.Imports.SourceBundle

  test "opens a ZIP in memory and exposes only opaque source aliases" do
    zip = zip!([{"Dialogue/intro.yarn", yarn("Start")}, {"project.yarnproject", "{}"}])

    assert {:ok, bundle} = SourceBundle.open("private-project-name.zip", zip)
    assert bundle.kind == :archive
    assert Enum.map(bundle.files, & &1.alias) == ["source_1", "source_2"]
    refute inspect(bundle) =~ "private-project-name"
    refute inspect(bundle) =~ "Dialogue/intro.yarn"
  end

  test "accepts ordinary directory entries in project archives" do
    zip = zip!([{"Dialogue/", ""}, {"Dialogue/intro.yarn", yarn("Start")}])

    assert {:ok, bundle} = SourceBundle.open("project.zip", zip)
    assert [%{alias: "source_1", extension: ".yarn"}] = SourceBundle.yarn_files(bundle)
  end

  test "rejects traversal paths before extraction" do
    zip = zip!([{"../escape.yarn", yarn("Start")}])
    assert {:error, :invalid_archive_path} = SourceBundle.open("project.zip", zip)
  end

  test "rejects nested archives" do
    zip = zip!([{"dialogue.yarn", yarn("Start")}, {"nested.zip", "not relevant"}])
    assert {:error, :nested_archive_not_allowed} = SourceBundle.open("project.zip", zip)
  end

  test "rejects duplicate paths case-insensitively" do
    zip = zip!([{"A.yarn", yarn("A")}, {"a.yarn", yarn("B")}])
    assert {:error, :duplicate_archive_entry} = SourceBundle.open("project.zip", zip)
  end

  test "rejects highly compressed expansion bombs" do
    zip = zip!([{"bomb.yarn", String.duplicate("a", 1_000_000)}])
    assert {:error, :archive_expansion_ratio_exceeded} = SourceBundle.open("project.zip", zip)
  end

  test "requires at least one Yarn source" do
    zip = zip!([{"project.yarnproject", "{}"}])
    assert {:error, :archive_missing_yarn_files} = SourceBundle.open("project.zip", zip)
  end

  defp yarn(title), do: "title: #{title}\n---\nHello\n===\n"

  defp zip!(files) do
    entries = Enum.map(files, fn {name, content} -> {String.to_charlist(name), content} end)
    {:ok, {_name, binary}} = :zip.create(~c"memory.zip", entries, [:memory])
    binary
  end
end

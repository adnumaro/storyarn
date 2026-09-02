defmodule Storyarn.Projects.Imports.SourceBundleTest do
  use ExUnit.Case, async: true

  alias Storyarn.Projects.Imports.Parsers.Yarn
  alias Storyarn.Projects.Imports.Parsers.Yarn.SourceProfile
  alias Storyarn.Projects.Imports.SourceBundle

  @test_profile %{
    plain_extensions: MapSet.new([".yarn"]),
    archive_extensions: MapSet.new([".zip"]),
    archive_entry_extensions: MapSet.new([".yarn"])
  }

  test "opens a ZIP in memory and exposes only opaque source aliases" do
    zip = zip!([{"Dialogue/intro.yarn", yarn("Start")}, {"project.yarnproject", project_json()}])

    assert {:ok, bundle} = Yarn.open_source("private-project-name.zip", zip)
    assert bundle.kind == :archive
    assert SourceProfile.replace_eligible?(bundle)
    assert Enum.map(bundle.files, & &1.alias) == ["source_1", "source_2"]
    refute inspect(bundle) =~ "private-project-name"
    refute inspect(bundle) =~ "Dialogue/intro.yarn"
  end

  test "rejects archive selector entries that did not cross the validated ZIP boundary" do
    zip = zip!([{"Dialogue/intro.yarn", yarn("Start")}])

    selectors = [
      fn [file] -> {:ok, [%{file | path: "Injected/outside.yarn"}]} end,
      fn [file] -> {:ok, [%{file | extension: ".json"}]} end,
      fn [file] -> {:ok, [%{file | content: yarn("Injected")}]} end,
      fn [_file] ->
        {:ok,
         [
           %{
             path: "Injected/outside.yarn",
             extension: ".yarn",
             content: yarn("Injected")
           }
         ]}
      end
    ]

    for selector <- selectors do
      assert {:error, :invalid_archive} =
               SourceBundle.open("project.zip", zip, @test_profile, selector)
    end
  end

  test "rejects duplicate and malformed archive selector results" do
    zip = zip!([{"Dialogue/intro.yarn", yarn("Start")}])

    assert {:error, :invalid_archive} =
             SourceBundle.open("project.zip", zip, @test_profile, fn [file] ->
               {:ok, [file, file]}
             end)

    assert {:error, :invalid_archive} =
             SourceBundle.open("project.zip", zip, @test_profile, fn _files ->
               {:ok, :not_a_source_list}
             end)
  end

  test "allows a selector to retain an exact validated subset in its chosen order" do
    first = yarn("First")
    second = yarn("Second")
    third = yarn("Third")

    zip =
      zip!([
        {"Dialogue/first.yarn", first},
        {"Dialogue/second.yarn", second},
        {"Dialogue/third.yarn", third}
      ])

    assert {:ok, bundle} =
             SourceBundle.open("project.zip", zip, @test_profile, fn files ->
               files_by_path = Map.new(files, &{&1.path, &1})

               {:ok,
                [
                  Map.fetch!(files_by_path, "Dialogue/third.yarn"),
                  Map.fetch!(files_by_path, "Dialogue/first.yarn")
                ]}
             end)

    assert bundle.files == [
             %{alias: "source_1", extension: ".yarn", content: third},
             %{alias: "source_2", extension: ".yarn", content: first}
           ]
  end

  test "selects only Yarn sources included by a project and applies exclusions last" do
    project =
      project_json(
        ["Dialogue/**/*.yarn", "../Shared/*.yarn"],
        ["Dialogue/**/backup/**", "Dialogue/**/*.test.yarn"]
      )

    zip =
      zip!([
        {"Game/project.yarnproject", project},
        {"Game/Dialogue/intro.yarn", yarn("Intro")},
        {"Game/Dialogue/Chapter/quest.yarn", yarn("Quest")},
        {"Game/Dialogue/backup/intro.yarn", yarn("OldIntro")},
        {"Game/Dialogue/Chapter/quest.test.yarn", yarn("TestQuest")},
        {"Shared/common.yarn", yarn("Common")},
        {"Unrelated/other.yarn", yarn("Other")}
      ])

    assert {:ok, bundle} = Yarn.open_source("project.zip", zip)

    assert bundle
           |> SourceProfile.yarn_files()
           |> Enum.map(& &1.content)
           |> Enum.sort() ==
             Enum.sort([yarn("Common"), yarn("Intro"), yarn("Quest")])
  end

  test "globstar includes files beside the project and in nested directories" do
    zip =
      zip!([
        {"Game/project.yarnproject", project_json()},
        {"Game/root.yarn", yarn("Root")},
        {"Game/Nested/child.yarn", yarn("Child")},
        {"outside.yarn", yarn("Outside")}
      ])

    assert {:ok, bundle} = Yarn.open_source("project.zip", zip)

    assert bundle
           |> SourceProfile.yarn_files()
           |> Enum.map(& &1.content)
           |> Enum.sort() == Enum.sort([yarn("Child"), yarn("Root")])
  end

  test "resolves parent source patterns within the archive boundary" do
    zip =
      zip!([
        {"Game/Dialogue/project.yarnproject", project_json(["../../Shared.yarn"])},
        {"Shared.yarn", yarn("Shared")},
        {"Game/Dialogue/local.yarn", yarn("Local")}
      ])

    assert {:ok, bundle} = Yarn.open_source("project.zip", zip)
    assert [%{content: content}] = SourceProfile.yarn_files(bundle)
    assert content == yarn("Shared")
  end

  test "keeps official implicit-project behavior when no yarnproject exists" do
    zip =
      zip!([
        {"Dialogue/intro.yarn", yarn("Intro")},
        {"backup/intro.yarn", yarn("Backup")}
      ])

    assert {:ok, bundle} = Yarn.open_source("project.zip", zip)
    assert length(SourceProfile.yarn_files(bundle)) == 2
    refute SourceProfile.replace_eligible?(bundle)
  end

  test "standalone Yarn sources are not eligible for whole-project replacement" do
    assert {:ok, bundle} = Yarn.open_source("dialogue.yarn", yarn("Start"))
    assert bundle.kind == :file
    refute SourceProfile.replace_eligible?(bundle)
  end

  test "rejects multiple yarnprojects instead of merging independent programs" do
    zip =
      zip!([
        {"Main/project.yarnproject", project_json()},
        {"Main/main.yarn", yarn("Main")},
        {"Barks/project.yarnproject", project_json()},
        {"Barks/bark.yarn", yarn("Bark")}
      ])

    assert {:error, :invalid_json_structure} = Yarn.open_source("project.zip", zip)
  end

  test "rejects malformed and structurally invalid yarnprojects" do
    malformed = zip!([{"project.yarnproject", "{"}, {"intro.yarn", yarn("Intro")}])

    invalid_version =
      zip!([
        {"project.yarnproject", project_json(["**/*.yarn"], [], 99)},
        {"intro.yarn", yarn("Intro")}
      ])

    missing_sources =
      zip!([
        {"project.yarnproject", Jason.encode!(%{"projectFileVersion" => 3})},
        {"intro.yarn", yarn("Intro")}
      ])

    assert {:error, :invalid_json} = Yarn.open_source("project.zip", malformed)
    assert {:error, :invalid_json_structure} = Yarn.open_source("project.zip", invalid_version)
    assert {:error, :invalid_json_structure} = Yarn.open_source("project.zip", missing_sources)
  end

  test "rejects source patterns that escape the archive or use unsupported glob syntax" do
    escaping =
      zip!([
        {"project.yarnproject", project_json(["../outside.yarn"])},
        {"inside.yarn", yarn("Inside")}
      ])

    unsupported =
      zip!([
        {"project.yarnproject", project_json(["Dialogue/[ab].yarn"])},
        {"Dialogue/a.yarn", yarn("A")}
      ])

    embedded_globstar =
      zip!([
        {"project.yarnproject", project_json(["Dialogue/foo**.yarn"])},
        {"Dialogue/foo.yarn", yarn("Foo")}
      ])

    assert {:error, :invalid_json_structure} = Yarn.open_source("project.zip", escaping)
    assert {:error, :invalid_json_structure} = Yarn.open_source("project.zip", unsupported)
    assert {:error, :invalid_json_structure} = Yarn.open_source("project.zip", embedded_globstar)
  end

  test "rejects a yarnproject whose patterns select no Yarn sources" do
    zip =
      zip!([
        {"project.yarnproject", project_json(["Dialogue/*.yarn"])},
        {"Other/intro.yarn", yarn("Intro")}
      ])

    assert {:error, :archive_missing_yarn_files} = Yarn.open_source("project.zip", zip)
  end

  test "bounds yarnproject glob count" do
    patterns = Enum.map(1..101, &"Dialogue/#{&1}.yarn")

    zip =
      zip!([
        {"project.yarnproject", project_json(patterns)},
        {"Dialogue/1.yarn", yarn("Intro")}
      ])

    assert {:error, :invalid_json_structure} = Yarn.open_source("project.zip", zip)
  end

  test "bounds aggregate wildcard matching work for large projects" do
    wildcard = String.duplicate("*a", 100)
    patterns = Enum.map(1..100, &"Dialogue/#{wildcard}#{&1}.yarn")

    yarn_files =
      Enum.map(1..100, fn index ->
        {"Dialogue/#{String.duplicate("x", 100)}#{index}.yarn", yarn("Node#{index}")}
      end)

    zip = zip!([{"project.yarnproject", project_json(patterns)} | yarn_files])

    assert {:error, :invalid_json_structure} = Yarn.open_source("project.zip", zip)
  end

  test "accepts current Yarn Spinner project file versions 2 through 4" do
    for version <- [2, 3, 4] do
      zip =
        zip!([
          {"project.yarnproject", project_json(["*.yarn"], [], version)},
          {"intro.yarn", yarn("Intro")}
        ])

      assert {:ok, bundle} = Yarn.open_source("project.zip", zip)
      assert [%{content: content}] = SourceProfile.yarn_files(bundle)
      assert content == yarn("Intro")
    end
  end

  test "rejects undocumented future Yarn project versions" do
    zip =
      zip!([
        {"project.yarnproject", project_json(["*.yarn"], [], 5)},
        {"intro.yarn", yarn("Intro")}
      ])

    assert {:error, :invalid_json_structure} = Yarn.open_source("project.zip", zip)
  end

  test "matches Yarn project patterns case-insensitively like Yarn Spinner" do
    zip =
      zip!([
        {"Game/project.yarnproject", project_json(["DIALOGUE/*.YARN"])},
        {"Game/Dialogue/intro.yarn", yarn("Intro")}
      ])

    assert {:ok, bundle} = Yarn.open_source("project.zip", zip)
    assert [%{content: content}] = SourceProfile.yarn_files(bundle)
    assert content == yarn("Intro")
  end

  test "supports the documented single-character wildcard" do
    zip =
      zip!([
        {"project.yarnproject", project_json(["Dialogue/scene?.yarn"])},
        {"Dialogue/scene1.yarn", yarn("Included")},
        {"Dialogue/scene10.yarn", yarn("Excluded")}
      ])

    assert {:ok, bundle} = Yarn.open_source("project.zip", zip)
    assert [%{content: content}] = SourceProfile.yarn_files(bundle)
    assert content == yarn("Included")
  end

  test "reads relevant yarnproject properties case-insensitively like Yarn Spinner" do
    project =
      Jason.encode!(%{
        "PROJECTFILEVERSION" => 3,
        "SOURCEFILES" => ["Dialogue/*.yarn"],
        "EXCLUDEFILES" => []
      })

    zip =
      zip!([
        {"project.yarnproject", project},
        {"Dialogue/intro.yarn", yarn("Intro")}
      ])

    assert {:ok, bundle} = Yarn.open_source("project.zip", zip)
    assert [%{content: content}] = SourceProfile.yarn_files(bundle)
    assert content == yarn("Intro")
  end

  test "accepts ordinary directory entries in project archives" do
    zip = zip!([{"Dialogue/", ""}, {"Dialogue/intro.yarn", yarn("Start")}])

    assert {:ok, bundle} = Yarn.open_source("project.zip", zip)
    assert [%{alias: "source_1", extension: ".yarn"}] = SourceProfile.yarn_files(bundle)
  end

  test "rejects traversal paths before extraction" do
    zip = zip!([{"../escape.yarn", yarn("Start")}])
    assert {:error, :invalid_archive_path} = Yarn.open_source("project.zip", zip)
  end

  test "rejects nested archives" do
    zip = zip!([{"dialogue.yarn", yarn("Start")}, {"nested.zip", "not relevant"}])
    assert {:error, :nested_archive_not_allowed} = Yarn.open_source("project.zip", zip)
  end

  test "rejects duplicate paths case-insensitively" do
    zip = zip!([{"A.yarn", yarn("A")}, {"a.yarn", yarn("B")}])
    assert {:error, :duplicate_archive_entry} = Yarn.open_source("project.zip", zip)
  end

  test "rejects duplicate paths after separator and Unicode normalization" do
    repeated_separator =
      zip!([{"Dialogue//intro.yarn", yarn("A")}, {"dialogue/intro.yarn", yarn("B")}])

    decomposed = "Cafe\u0301.yarn"
    composed = "Café.yarn"
    unicode_equivalent = zip!([{decomposed, yarn("A")}, {composed, yarn("B")}])

    assert {:error, :duplicate_archive_entry} =
             Yarn.open_source("project.zip", repeated_separator)

    assert {:error, :duplicate_archive_entry} =
             Yarn.open_source("project.zip", unicode_equivalent)
  end

  test "rejects highly compressed expansion bombs" do
    zip = zip!([{"bomb.yarn", String.duplicate("a", 1_000_000)}])
    assert {:error, :archive_expansion_ratio_exceeded} = Yarn.open_source("project.zip", zip)
  end

  test "requires at least one Yarn source" do
    zip = zip!([{"project.yarnproject", project_json()}])
    assert {:error, :archive_missing_yarn_files} = Yarn.open_source("project.zip", zip)
  end

  test "accepts exactly 500 ZIP entries" do
    zip = zip_entries!(500)

    assert {:ok, bundle} = Yarn.open_source("project.zip", zip)
    assert length(SourceProfile.yarn_files(bundle)) == 500
  end

  test "rejects 501 ZIP entries during preflight" do
    zip = zip_entries!(501)

    assert {:error, :archive_too_many_entries} = Yarn.open_source("project.zip", zip)
  end

  test "rejects an excessive declared EOCD entry count" do
    zip = zip!([{"intro.yarn", yarn("Start")}])
    zip = zip |> put_eocd_u16(8, 501) |> put_eocd_u16(10, 501)

    assert {:error, :archive_too_many_entries} = Yarn.open_source("project.zip", zip)
  end

  test "rejects an understated EOCD entry count" do
    zip = zip_entries!(2)
    zip = zip |> put_eocd_u16(8, 1) |> put_eocd_u16(10, 1)

    assert {:error, :invalid_archive} = Yarn.open_source("project.zip", zip)
  end

  test "rejects malformed central directory offsets" do
    zip = zip!([{"intro.yarn", yarn("Start")}])
    zip = put_eocd_u32(zip, 16, byte_size(zip))

    assert {:error, :invalid_archive} = Yarn.open_source("project.zip", zip)
  end

  test "rejects ZIP64 sentinels" do
    zip = zip!([{"intro.yarn", yarn("Start")}])
    zip = zip |> put_eocd_u16(8, 0xFFFF) |> put_eocd_u16(10, 0xFFFF)

    assert {:error, :invalid_archive} = Yarn.open_source("project.zip", zip)
  end

  test "rejects ZIP64 locators even without saturated legacy fields" do
    zip = zip!([{"intro.yarn", yarn("Start")}])
    locator = <<0x50, 0x4B, 0x06, 0x07, 0::little-size(32), 0::little-size(64), 1::little-size(32)>>
    zip = insert_before_eocd(zip, locator)

    assert {:error, :invalid_archive} = Yarn.open_source("project.zip", zip)
  end

  test "rejects multi-disk ZIP metadata" do
    zip = zip!([{"intro.yarn", yarn("Start")}])
    zip = zip |> put_eocd_u16(4, 1) |> put_eocd_u16(6, 1)

    assert {:error, :invalid_archive} = Yarn.open_source("project.zip", zip)
  end

  test "rejects oversized central directory entry names" do
    name = String.duplicate("a", 1_021) <> ".yarn"
    zip = zip!([{name, yarn("Start")}])

    assert {:error, :invalid_archive} = Yarn.open_source("project.zip", zip)
  end

  test "accepts a bounded central directory digital signature" do
    zip = zip!([{"intro.yarn", yarn("Start")}])
    signed_zip = add_central_directory_signature(zip, "test-signature")

    assert {:ok, bundle} = Yarn.open_source("project.zip", signed_zip)
    assert [%{extension: ".yarn"}] = SourceProfile.yarn_files(bundle)
  end

  defp yarn(title), do: "title: #{title}\n---\nHello\n===\n"

  defp project_json(source_files \\ ["**/*.yarn"], exclude_files \\ [], version \\ 3) do
    Jason.encode!(%{
      "projectFileVersion" => version,
      "sourceFiles" => source_files,
      "excludeFiles" => exclude_files
    })
  end

  defp zip!(files) do
    entries = Enum.map(files, fn {name, content} -> {String.to_charlist(name), content} end)
    {:ok, {_name, binary}} = :zip.create(~c"memory.zip", entries, [:memory])
    binary
  end

  defp zip_entries!(count) do
    1..count
    |> Enum.map(fn index -> {"Dialogue/#{index}.yarn", yarn("Node#{index}")} end)
    |> zip!()
  end

  defp put_eocd_u16(binary, field_offset, value) do
    put_eocd_field(binary, field_offset, 2, <<value::little-unsigned-integer-size(16)>>)
  end

  defp put_eocd_u32(binary, field_offset, value) do
    put_eocd_field(binary, field_offset, 4, <<value::little-unsigned-integer-size(32)>>)
  end

  defp put_eocd_field(binary, field_offset, field_size, replacement) do
    {eocd_offset, 4} = eocd_match(binary)
    offset = eocd_offset + field_offset
    <<prefix::binary-size(offset), _old::binary-size(field_size), suffix::binary>> = binary
    prefix <> replacement <> suffix
  end

  defp insert_before_eocd(binary, data) do
    {eocd_offset, 4} = eocd_match(binary)
    <<prefix::binary-size(eocd_offset), suffix::binary>> = binary
    prefix <> data <> suffix
  end

  defp add_central_directory_signature(binary, signature) do
    {eocd_offset, 4} = eocd_match(binary)

    <<_prefix::binary-size(eocd_offset + 12), directory_size::little-unsigned-integer-size(32), _rest::binary>> =
      binary

    record =
      <<0x50, 0x4B, 0x05, 0x05, byte_size(signature)::little-unsigned-integer-size(16), signature::binary>>

    binary
    |> insert_before_eocd(record)
    |> put_eocd_u32(12, directory_size + byte_size(record))
  end

  defp eocd_match(binary) do
    binary
    |> :binary.matches(<<0x50, 0x4B, 0x05, 0x06>>)
    |> List.last()
  end
end

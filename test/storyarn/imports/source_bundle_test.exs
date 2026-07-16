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

  test "accepts exactly 500 ZIP entries" do
    zip = zip_entries!(500)

    assert {:ok, bundle} = SourceBundle.open("project.zip", zip)
    assert length(SourceBundle.yarn_files(bundle)) == 500
  end

  test "rejects 501 ZIP entries during preflight" do
    zip = zip_entries!(501)

    assert {:error, :archive_too_many_entries} = SourceBundle.open("project.zip", zip)
  end

  test "rejects an excessive declared EOCD entry count" do
    zip = zip!([{"intro.yarn", yarn("Start")}])
    zip = zip |> put_eocd_u16(8, 501) |> put_eocd_u16(10, 501)

    assert {:error, :archive_too_many_entries} = SourceBundle.open("project.zip", zip)
  end

  test "rejects an understated EOCD entry count" do
    zip = zip_entries!(2)
    zip = zip |> put_eocd_u16(8, 1) |> put_eocd_u16(10, 1)

    assert {:error, :invalid_archive} = SourceBundle.open("project.zip", zip)
  end

  test "rejects malformed central directory offsets" do
    zip = zip!([{"intro.yarn", yarn("Start")}])
    zip = put_eocd_u32(zip, 16, byte_size(zip))

    assert {:error, :invalid_archive} = SourceBundle.open("project.zip", zip)
  end

  test "rejects ZIP64 sentinels" do
    zip = zip!([{"intro.yarn", yarn("Start")}])
    zip = zip |> put_eocd_u16(8, 0xFFFF) |> put_eocd_u16(10, 0xFFFF)

    assert {:error, :invalid_archive} = SourceBundle.open("project.zip", zip)
  end

  test "rejects ZIP64 locators even without saturated legacy fields" do
    zip = zip!([{"intro.yarn", yarn("Start")}])
    locator = <<0x50, 0x4B, 0x06, 0x07, 0::little-size(32), 0::little-size(64), 1::little-size(32)>>
    zip = insert_before_eocd(zip, locator)

    assert {:error, :invalid_archive} = SourceBundle.open("project.zip", zip)
  end

  test "rejects multi-disk ZIP metadata" do
    zip = zip!([{"intro.yarn", yarn("Start")}])
    zip = zip |> put_eocd_u16(4, 1) |> put_eocd_u16(6, 1)

    assert {:error, :invalid_archive} = SourceBundle.open("project.zip", zip)
  end

  test "rejects oversized central directory entry names" do
    name = String.duplicate("a", 1_021) <> ".yarn"
    zip = zip!([{name, yarn("Start")}])

    assert {:error, :invalid_archive} = SourceBundle.open("project.zip", zip)
  end

  test "accepts a bounded central directory digital signature" do
    zip = zip!([{"intro.yarn", yarn("Start")}])
    signed_zip = add_central_directory_signature(zip, "test-signature")

    assert {:ok, bundle} = SourceBundle.open("project.zip", signed_zip)
    assert [%{extension: ".yarn"}] = SourceBundle.yarn_files(bundle)
  end

  defp yarn(title), do: "title: #{title}\n---\nHello\n===\n"

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

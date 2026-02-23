defmodule Storyarn.Localization.ExportImportTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Localization

  import Storyarn.AccountsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures

  describe "export_csv/2" do
    test "exports texts as CSV" do
      user = user_fixture()
      project = project_fixture(user)
      _source = source_language_fixture(project)

      _text =
        localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_id: 1,
          source_field: "text",
          source_text: "Hello world",
          locale_code: "es"
        })

      {:ok, csv} = Localization.export_csv(project.id, locale_code: "es")

      assert String.contains?(csv, "ID,Source Type,Source ID")
      assert String.contains?(csv, "Hello world")
      assert String.contains?(csv, "flow_node")
    end

    test "exports empty CSV when no texts" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, csv} = Localization.export_csv(project.id, locale_code: "es")

      # Only header row
      lines = String.split(csv, "\n", trim: true)
      assert length(lines) == 1
    end
  end

  describe "export_xlsx/2" do
    test "exports texts as xlsx binary" do
      user = user_fixture()
      project = project_fixture(user)
      _source = source_language_fixture(project)

      _text =
        localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_id: 1,
          source_field: "text",
          source_text: "Hello world",
          locale_code: "es"
        })

      {:ok, binary} = Localization.export_xlsx(project.id, locale_code: "es")

      # XLSX files start with PK (zip header)
      assert <<0x50, 0x4B, _rest::binary>> = binary
      assert byte_size(binary) > 0
    end
  end

  describe "import_csv/1" do
    test "imports translations from CSV" do
      user = user_fixture()
      project = project_fixture(user)
      _source = source_language_fixture(project)

      text =
        localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_id: 1,
          source_field: "text",
          source_text: "Hello",
          locale_code: "es"
        })

      csv = """
      ID,Translation,Status
      #{text.id},Hola,draft
      """

      {:ok, result} = Localization.import_csv(csv)

      assert result.updated == 1
      assert result.skipped == 0

      updated = Localization.get_text!(text.id)
      assert updated.translated_text == "Hola"
      assert updated.status == "draft"
    end

    test "skips rows with invalid IDs" do
      csv = """
      ID,Translation,Status
      999999,Hola,draft
      """

      {:ok, result} = Localization.import_csv(csv)
      assert result.updated == 0
      assert result.errors != []
    end

    test "returns error for empty file" do
      assert {:error, :empty_file} = Localization.import_csv("")
    end

    test "returns error when ID column is missing" do
      csv = """
      Name,Translation,Status
      test,Hola,draft
      """

      assert {:error, :missing_id_column} = Localization.import_csv(csv)
    end

    test "handles quoted CSV fields with commas" do
      user = user_fixture()
      project = project_fixture(user)
      _source = source_language_fixture(project)

      text =
        localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_id: 1,
          source_field: "text",
          source_text: "Hello",
          locale_code: "es"
        })

      csv = """
      ID,Translation,Status
      #{text.id},"Hola, mundo",draft
      """

      {:ok, result} = Localization.import_csv(csv)
      assert result.updated == 1

      updated = Localization.get_text!(text.id)
      assert updated.translated_text == "Hola, mundo"
    end
  end
end

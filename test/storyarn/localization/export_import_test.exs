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

      {:ok, result} = Localization.import_csv(project.id, csv)

      assert result.updated == 1
      assert result.skipped == 0

      updated = Localization.get_text!(text.project_id, text.id)
      assert updated.translated_text == "Hola"
      assert updated.status == "draft"
    end

    test "skips rows with invalid IDs" do
      user = user_fixture()
      project = project_fixture(user)

      csv = """
      ID,Translation,Status
      999999,Hola,draft
      """

      {:ok, result} = Localization.import_csv(project.id, csv)
      assert result.updated == 0
      assert result.errors != []
    end

    test "returns error for empty file" do
      user = user_fixture()
      project = project_fixture(user)

      assert {:error, :empty_file} = Localization.import_csv(project.id, "")
    end

    test "returns error when ID column is missing" do
      user = user_fixture()
      project = project_fixture(user)

      csv = """
      Name,Translation,Status
      test,Hola,draft
      """

      assert {:error, :missing_id_column} = Localization.import_csv(project.id, csv)
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

      {:ok, result} = Localization.import_csv(project.id, csv)
      assert result.updated == 1

      updated = Localization.get_text!(text.project_id, text.id)
      assert updated.translated_text == "Hola, mundo"
    end

    test "skips rows with empty translation and invalid status" do
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

      # Empty translation + invalid status = empty attrs = :skip
      csv = "ID,Translation,Status\n#{text.id},,invalid_status"

      {:ok, result} = Localization.import_csv(project.id, csv)
      assert result.skipped == 1
      assert result.updated == 0
    end

    test "handles quoted fields with escaped quotes" do
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

      # Escaped quotes in CSV: "" inside quoted field becomes "
      csv = "ID,Translation,Status\n#{text.id},\"She said \"\"hello\"\"\",draft"

      {:ok, result} = Localization.import_csv(project.id, csv)
      assert result.updated == 1

      updated = Localization.get_text!(text.project_id, text.id)
      assert updated.translated_text == "She said \"hello\""
    end

    test "skips row with only whitespace translation" do
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

      # Whitespace-only translation with valid status should still update status
      csv = "ID,Translation,Status\n#{text.id},   ,draft"

      {:ok, result} = Localization.import_csv(project.id, csv)
      # Status is valid so attrs won't be empty, will update
      assert result.updated == 1
    end

    test "imports CSV with no Translation column" do
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

      # Only ID and Status, no Translation column -> maybe_put_translation receives nil
      csv = "ID,Status\n#{text.id},draft"

      {:ok, result} = Localization.import_csv(project.id, csv)
      assert result.updated == 1
    end
  end

  describe "export_csv/2 with special characters" do
    test "escapes commas, quotes, and newlines in text fields" do
      user = user_fixture()
      project = project_fixture(user)
      _source = source_language_fixture(project)

      _text =
        localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_id: 1,
          source_field: "text",
          source_text: "Hello, \"world\"\nNew line",
          locale_code: "es"
        })

      {:ok, csv} = Localization.export_csv(project.id, locale_code: "es")

      # The source text with comma/quote/newline should be quoted and escaped
      assert csv =~ ~s("Hello, ""world"")
    end

    test "handles nil translated_text in CSV export" do
      user = user_fixture()
      project = project_fixture(user)
      _source = source_language_fixture(project)

      _text =
        localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_id: 1,
          source_field: "text",
          source_text: "Hello",
          translated_text: nil,
          locale_code: "es"
        })

      {:ok, csv} = Localization.export_csv(project.id, locale_code: "es")

      # csv_escape(nil) should return "" and not crash
      assert is_binary(csv)
      lines = String.split(csv, "\n", trim: true)
      assert length(lines) == 2
    end
  end
end

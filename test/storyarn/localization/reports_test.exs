defmodule Storyarn.Localization.ReportsTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Localization.Reports

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.LocalizationFixtures

  describe "progress_by_language/1" do
    test "returns progress for each target language" do
      user = user_fixture()
      project = project_fixture(user)

      source_language_fixture(project, %{locale_code: "en", name: "English"})
      language_fixture(project, %{locale_code: "es", name: "Spanish"})

      # Create texts with different statuses
      localized_text_fixture(project.id, %{locale_code: "es", status: "pending"})
      localized_text_fixture(project.id, %{locale_code: "es", status: "final"})
      localized_text_fixture(project.id, %{locale_code: "es", status: "final"})

      [progress] = Reports.progress_by_language(project.id)

      assert progress.locale_code == "es"
      assert progress.name == "Spanish"
      assert progress.total == 3
      assert progress.final == 2
      assert_in_delta progress.percentage, 66.7, 0.1
    end

    test "excludes source language from results" do
      user = user_fixture()
      project = project_fixture(user)

      source_language_fixture(project, %{locale_code: "en", name: "English"})

      result = Reports.progress_by_language(project.id)
      assert result == []
    end

    test "returns empty list when no languages configured" do
      user = user_fixture()
      project = project_fixture(user)

      assert Reports.progress_by_language(project.id) == []
    end
  end

  describe "word_counts_by_speaker/2" do
    test "returns word counts grouped by speaker" do
      user = user_fixture()
      project = project_fixture(user)

      localized_text_fixture(project.id, %{
        locale_code: "es",
        source_type: "flow_node",
        speaker_sheet_id: nil,
        word_count: 10
      })

      localized_text_fixture(project.id, %{
        locale_code: "es",
        source_type: "flow_node",
        speaker_sheet_id: nil,
        word_count: 5
      })

      stats = Reports.word_counts_by_speaker(project.id, "es")

      assert length(stats) == 1
      [stat] = stats
      assert stat.speaker_sheet_id == nil
      assert stat.word_count == 15
      assert stat.line_count == 2
    end

    test "only counts flow_node source type" do
      user = user_fixture()
      project = project_fixture(user)

      localized_text_fixture(project.id, %{
        locale_code: "es",
        source_type: "flow_node",
        word_count: 10
      })

      localized_text_fixture(project.id, %{
        locale_code: "es",
        source_type: "sheet",
        word_count: 20
      })

      stats = Reports.word_counts_by_speaker(project.id, "es")
      assert length(stats) == 1
      assert hd(stats).word_count == 10
    end
  end

  describe "vo_progress/2" do
    test "returns VO status counts with defaults" do
      user = user_fixture()
      project = project_fixture(user)

      localized_text_fixture(project.id, %{
        locale_code: "es",
        source_type: "flow_node",
        vo_status: "none"
      })

      localized_text_fixture(project.id, %{
        locale_code: "es",
        source_type: "flow_node",
        vo_status: "needed"
      })

      localized_text_fixture(project.id, %{
        locale_code: "es",
        source_type: "flow_node",
        vo_status: "needed"
      })

      result = Reports.vo_progress(project.id, "es")

      assert result.none == 1
      assert result.needed == 2
      assert result.recorded == 0
      assert result.approved == 0
    end

    test "returns all zeros when no texts exist" do
      user = user_fixture()
      project = project_fixture(user)

      result = Reports.vo_progress(project.id, "es")

      assert result == %{none: 0, needed: 0, recorded: 0, approved: 0}
    end
  end

  describe "counts_by_source_type/2" do
    test "returns counts grouped by source type" do
      user = user_fixture()
      project = project_fixture(user)

      localized_text_fixture(project.id, %{locale_code: "es", source_type: "flow_node"})
      localized_text_fixture(project.id, %{locale_code: "es", source_type: "flow_node"})
      localized_text_fixture(project.id, %{locale_code: "es", source_type: "sheet"})

      counts = Reports.counts_by_source_type(project.id, "es")

      assert counts["flow_node"] == 2
      assert counts["sheet"] == 1
    end

    test "returns empty map when no texts exist" do
      user = user_fixture()
      project = project_fixture(user)

      assert Reports.counts_by_source_type(project.id, "es") == %{}
    end
  end
end

defmodule StoryarnWeb.LocalizationLive.EditTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Repo

  defp edit_url(project, text) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/#{text.id}"
  end

  defp get_edit_vue(view) do
    LiveVue.Test.get_vue(view, name: "modules/localization/components/LocalizationEdit")
  end

  describe "Edit translation page" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      %{project: project}
    end

    test "renders localization edit Vue component", %{conn: conn, project: project} do
      text = localized_text_fixture(project.id, %{source_text: "Hello world", locale_code: "es"})

      {:ok, view, _html} = live(conn, edit_url(project, text))

      vue = get_edit_vue(view)
      assert vue.component == "modules/localization/components/LocalizationEdit"
      assert vue.props["text"]["source_text"] =~ "Hello world"
      assert vue.props["text"]["locale_code"] == "es"
    end

    test "passes source text and word count in text prop", %{conn: conn, project: project} do
      text =
        localized_text_fixture(project.id, %{
          source_text: "Welcome adventurer",
          locale_code: "es",
          word_count: 2
        })

      {:ok, view, _html} = live(conn, edit_url(project, text))

      vue = get_edit_vue(view)
      assert vue.props["text"]["source_text"] =~ "Welcome adventurer"
      assert vue.props["text"]["word_count"] == 2
    end

    test "passes form prop with translation fields", %{conn: conn, project: project} do
      text = localized_text_fixture(project.id)

      {:ok, view, _html} = live(conn, edit_url(project, text))

      vue = get_edit_vue(view)
      assert is_map(vue.props["form"])
    end

    test "passes back-url to Vue", %{conn: conn, project: project} do
      text = localized_text_fixture(project.id)

      {:ok, view, _html} = live(conn, edit_url(project, text))

      vue = get_edit_vue(view)
      assert vue.props["back-url"] =~ "/localization"
    end

    test "passes source type and field metadata", %{conn: conn, project: project} do
      text =
        localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_field: "text"
        })

      {:ok, view, _html} = live(conn, edit_url(project, text))

      vue = get_edit_vue(view)
      assert vue.props["text"]["source_type"] == "flow_node"
      assert vue.props["text"]["source_field"] == "text"
    end
  end

  describe "Authentication and authorization" do
    test "unauthenticated user gets redirected to login", %{conn: conn} do
      assert {:error, redirect} =
               live(conn, ~p"/workspaces/some-ws/projects/some-proj/localization/1")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "user without project access gets redirected", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      other_user = user_fixture()
      project = other_user |> project_fixture() |> Repo.preload(:workspace)
      text = localized_text_fixture(project.id)

      assert {:error, {:redirect, %{to: "/workspaces", flash: %{"error" => error_msg}}}} =
               live(
                 conn,
                 ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/#{text.id}"
               )

      assert error_msg =~ "not found"
    end

    test "member with viewer role can access the page", %{conn: conn} do
      viewer = user_fixture()
      conn = log_in_user(conn, viewer)

      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, viewer, "viewer")
      text = localized_text_fixture(project.id)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/#{text.id}"
        )

      vue = get_edit_vue(view)
      assert vue.component == "modules/localization/components/LocalizationEdit"
      assert vue.props["can-edit"] == false
    end
  end

  describe "save_translation event" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      %{project: project}
    end

    test "successfully saves translation with text and status", %{
      conn: conn,
      project: project
    } do
      text =
        localized_text_fixture(project.id, %{
          source_text: "Hello world",
          locale_code: "es",
          status: "pending"
        })

      {:ok, view, _html} = live(conn, edit_url(project, text))

      html =
        render_click(view, "save_translation", %{
          "localized_text" => %{
            "translated_text" => "Hola mundo",
            "status" => "draft",
            "translator_notes" => "First pass"
          }
        })

      assert html =~ "Translation saved"
    end

    test "saves translation with final status", %{conn: conn, project: project} do
      text = localized_text_fixture(project.id, %{locale_code: "es"})

      {:ok, view, _html} = live(conn, edit_url(project, text))

      html =
        render_click(view, "save_translation", %{
          "localized_text" => %{
            "translated_text" => "Traduccion final",
            "status" => "final"
          }
        })

      assert html =~ "Translation saved"
    end

    test "save_translation with empty text preserves Vue component", %{
      conn: conn,
      project: project
    } do
      text = localized_text_fixture(project.id, %{locale_code: "es"})

      {:ok, view, _html} = live(conn, edit_url(project, text))

      render_click(view, "save_translation", %{
        "localized_text" => %{
          "translated_text" => "",
          "status" => "draft"
        }
      })

      # Vue component should still render after save
      vue = get_edit_vue(view)
      assert vue.component == "modules/localization/components/LocalizationEdit"
    end

    test "updates text prop after successful save", %{conn: conn, project: project} do
      text = localized_text_fixture(project.id, %{locale_code: "es"})

      {:ok, view, _html} = live(conn, edit_url(project, text))

      render_click(view, "save_translation", %{
        "localized_text" => %{
          "translated_text" => "Texto actualizado",
          "status" => "draft",
          "translator_notes" => "Notes here"
        }
      })

      vue = get_edit_vue(view)
      assert vue.props["text"]["translated_text"] == "Texto actualizado"
      assert vue.props["text"]["translator_notes"] == "Notes here"
    end
  end

  describe "translate_with_deepl event" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      %{project: project}
    end

    test "translate_with_deepl fails without active provider", %{conn: conn, project: project} do
      text = localized_text_fixture(project.id, %{locale_code: "es"})

      {:ok, view, _html} = live(conn, edit_url(project, text))

      # Without a DeepL provider configured, this should fail.
      html = render_click(view, "translate_with_deepl", %{})

      assert html =~ "Translation failed" or html =~ "permission"
    end
  end

  describe "Machine translated flag" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      %{project: project}
    end

    test "passes machine_translated=true to Vue", %{conn: conn, project: project} do
      text =
        localized_text_fixture(project.id, %{
          locale_code: "es",
          machine_translated: true
        })

      {:ok, view, _html} = live(conn, edit_url(project, text))

      vue = get_edit_vue(view)
      assert vue.props["text"]["machine_translated"] == true
    end

    test "passes machine_translated=false to Vue", %{conn: conn, project: project} do
      text =
        localized_text_fixture(project.id, %{
          locale_code: "es",
          machine_translated: false
        })

      {:ok, view, _html} = live(conn, edit_url(project, text))

      vue = get_edit_vue(view)
      assert vue.props["text"]["machine_translated"] == false
    end
  end

  describe "Last translated at timestamp" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      %{project: project}
    end

    test "passes last_translated_at when set", %{conn: conn, project: project} do
      text =
        localized_text_fixture(project.id, %{
          locale_code: "es"
        })

      {:ok, updated_text} =
        Storyarn.Localization.update_text(text, %{
          "last_translated_at" => ~U[2025-06-15 14:30:00Z]
        })

      {:ok, view, _html} = live(conn, edit_url(project, updated_text))

      vue = get_edit_vue(view)
      assert vue.props["text"]["last_translated_at"] =~ "2025-06-15"
    end

    test "last_translated_at is nil when not set", %{conn: conn, project: project} do
      text =
        localized_text_fixture(project.id, %{
          locale_code: "es"
        })

      {:ok, view, _html} = live(conn, edit_url(project, text))

      vue = get_edit_vue(view)
      assert vue.props["text"]["last_translated_at"] == nil
    end
  end

  describe "Viewer authorization for save and translate" do
    test "viewer cannot save translation (gets unauthorized flash)", %{conn: conn} do
      viewer = user_fixture()
      conn = log_in_user(conn, viewer)

      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, viewer, "viewer")
      text = localized_text_fixture(project.id, %{locale_code: "es"})

      {:ok, view, _html} = live(conn, edit_url(project, text))

      html =
        render_click(view, "save_translation", %{
          "localized_text" => %{
            "translated_text" => "Should not work",
            "status" => "draft"
          }
        })

      assert html =~ "permission"
    end

    test "viewer cannot use translate_with_deepl (gets unauthorized flash)", %{conn: conn} do
      viewer = user_fixture()
      conn = log_in_user(conn, viewer)

      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, viewer, "viewer")
      text = localized_text_fixture(project.id, %{locale_code: "es"})

      {:ok, view, _html} = live(conn, edit_url(project, text))

      html = render_click(view, "translate_with_deepl", %{})

      assert html =~ "permission"
    end
  end

  describe "Word count and provider props" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      %{project: project}
    end

    test "nil word count is passed as-is to Vue", %{conn: conn, project: project} do
      text =
        localized_text_fixture(project.id, %{
          locale_code: "es",
          word_count: nil
        })

      {:ok, view, _html} = live(conn, edit_url(project, text))

      vue = get_edit_vue(view)
      assert vue.props["text"]["word_count"] == nil
    end

    test "passes correct word count when set", %{conn: conn, project: project} do
      text =
        localized_text_fixture(project.id, %{
          locale_code: "es",
          word_count: 5
        })

      {:ok, view, _html} = live(conn, edit_url(project, text))

      vue = get_edit_vue(view)
      assert vue.props["text"]["word_count"] == 5
    end

    test "has-provider is false when no active provider", %{conn: conn, project: project} do
      text = localized_text_fixture(project.id, %{locale_code: "es"})

      {:ok, view, _html} = live(conn, edit_url(project, text))

      vue = get_edit_vue(view)
      assert vue.props["has-provider"] == false
    end
  end

  describe "Source text sanitization" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      %{project: project}
    end

    test "passes sanitized HTML source text to Vue", %{conn: conn, project: project} do
      text =
        localized_text_fixture(project.id, %{
          source_text: "<p>Hello <strong>bold</strong> world</p>",
          locale_code: "es"
        })

      {:ok, view, _html} = live(conn, edit_url(project, text))

      vue = get_edit_vue(view)
      assert vue.props["text"]["source_text"] =~ "Hello"
      assert vue.props["text"]["source_text"] =~ "bold"
    end

    test "handles nil source text without error", %{conn: conn, project: project} do
      text =
        localized_text_fixture(project.id, %{
          source_text: nil,
          locale_code: "es"
        })

      {:ok, view, _html} = live(conn, edit_url(project, text))

      vue = get_edit_vue(view)
      assert vue.component == "modules/localization/components/LocalizationEdit"
    end
  end
end

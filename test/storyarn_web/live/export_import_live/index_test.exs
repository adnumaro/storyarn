defmodule StoryarnWeb.ExportImportLive.IndexTest do
  use StoryarnWeb.ConnCase, async: true

  import Ecto.Query, warn: false
  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Accounts.Scope
  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Imports
  alias Storyarn.Imports.PlanStorage
  alias Storyarn.Imports.ProjectImportAttempt
  alias Storyarn.Imports.Shared
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias StoryarnWeb.ExportImportLive.Index

  defp get_settings_layout(view) do
    LiveVue.Test.get_vue(view, name: "live/layouts/settings/Layout")
  end

  defp get_export_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/project/settings/export-import/ProjectSettingsExportImport")
  end

  defp export_config(view), do: get_export_vue(view).props["export-config"]
  defp import_state(view), do: get_export_vue(view).props["import-state"]
  defp format_config(view), do: export_config(view)["formatConfig"]
  defp selected_format(view), do: format_config(view)["selected"]
  defp format_extension(view), do: format_config(view)["extension"]
  defp visible_formats(view), do: format_config(view)["formats"]
  defp download_url(view), do: export_config(view)["downloadUrl"]
  defp validation_status(view), do: (export_config(view)["validation"] || %{})["status"]
  defp validation_stale?(view), do: (export_config(view)["validation"] || %{})["stale"]
  defp entity_counts(view), do: export_config(view)["sectionConfig"]["entityCounts"]

  setup :register_and_log_in_user

  setup %{user: user} do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    %{project: project}
  end

  defp export_url(project) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/export-import"
  end

  describe "import and export page" do
    test "renders the combined import and export workspace", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_url(project))

      settings_layout = get_settings_layout(view)
      assert settings_layout.props["title"] == "Import & Export"

      assert String.trim(settings_layout.props["subtitle"]) ==
               "Move narrative content into or out of this project."
    end

    test "exposes a bounded Yarn upload and empty import state to editors", %{
      conn: conn,
      project: project,
      user: user
    } do
      {:ok, view, _html} = live(conn, export_url(project))

      props = get_export_vue(view).props
      assert props["can-edit"] == true
      refute Map.has_key?(props, "project-id")
      refute Map.has_key?(props, "current-user-id")
      assert props["resume-storage-key"] == Imports.resume_storage_key(Scope.for_user(user), project)
      assert is_map(props["upload-config"])
      assert import_state(view)["step"] == "upload"
      assert import_state(view)["conflictStrategy"] == "rename"
    end

    test "automatically restores the current user's latest active import on connected mount", %{
      conn: conn,
      project: project,
      user: user
    } do
      scope = Scope.for_user(user)

      assert {:ok, expected, _preview} =
               Imports.prepare_import(
                 scope,
                 project,
                 "owner.yarn",
                 "title: OwnerImport\n---\nHello\n===\n"
               )

      other_owner = user_fixture()
      membership_fixture(project, other_owner, "owner")

      assert {:ok, other_attempt, _preview} =
               Imports.prepare_import(
                 Scope.for_user(other_owner),
                 project,
                 "other-owner.yarn",
                 "title: OtherOwnerImport\n---\nHello\n===\n"
               )

      assert other_attempt.id > expected.id

      {:ok, view, _html} = live(conn, export_url(project))

      state = import_state(view)
      assert state["step"] == "preview"
      assert state["attemptId"] == expected.id
      assert state["status"] == "ready"
      assert state["preview"]["counts"]["flows"] == 1
    end

    test "rehydrates a ready attempt and recomputes its conflict preview", %{
      conn: conn,
      project: project,
      user: user
    } do
      _existing = flow_fixture(project, %{name: "Start"})
      scope = Scope.for_user(user)

      assert {:ok, ready, _preview} =
               Imports.prepare_import(
                 scope,
                 project,
                 "project.yarn",
                 "title: Start\n---\nHello\n===\n"
               )

      {:ok, view, _html} = live(conn, export_url(project))
      render_hook(view, "resume_import", %{"attempt_id" => ready.id})
      assert_reply(view, %{ok: true, status: "ready"})

      state = import_state(view)
      assert state["step"] == "preview"
      assert state["attemptId"] == ready.id
      assert state["status"] == "ready"
      assert state["preview"]["has_conflicts"]
      assert state["preview"]["counts"]["flows"] == 1
    end

    test "persists the selected conflict strategy across navigation", %{
      conn: conn,
      project: project,
      user: user
    } do
      scope = Scope.for_user(user)

      assert {:ok, ready, _preview} =
               Imports.prepare_import(
                 scope,
                 project,
                 "strategy.yarn",
                 "title: Start\n---\nHello\n===\n"
               )

      {:ok, view, _html} = live(conn, export_url(project))
      assert import_state(view)["conflictStrategy"] == "rename"

      render_hook(view, "set_strategy", %{"attempt_id" => ready.id, "strategy" => "skip"})
      assert import_state(view)["conflictStrategy"] == "skip"
      assert Repo.get!(ProjectImportAttempt, ready.id).conflict_strategy == "skip"

      {:ok, remounted, _html} = live(conn, export_url(project))
      assert import_state(remounted)["attemptId"] == ready.id
      assert import_state(remounted)["conflictStrategy"] == "skip"
    end

    test "a concurrent strategy failure cannot dismiss a running import", %{
      conn: conn,
      project: project,
      user: user
    } do
      scope = Scope.for_user(user)

      assert {:ok, ready, _preview} =
               Imports.prepare_import(
                 scope,
                 project,
                 "strategy-race.yarn",
                 "title: Start\n---\nHello\n===\n"
               )

      {:ok, view, _html} = live(conn, export_url(project))
      assert import_state(view)["status"] == "ready"

      # Simulate another tab starting materialization without relying on its
      # ephemeral PubSub message reaching this LiveView first.
      Repo.update_all(
        from(attempt in ProjectImportAttempt, where: attempt.id == ^ready.id),
        set: [status: "running", stage: "materializing", started_at: TimeHelpers.now()]
      )

      render_hook(view, "set_strategy", %{"attempt_id" => ready.id, "strategy" => "skip"})

      state = import_state(view)
      assert state["step"] == "queued"
      assert state["status"] == "running"
      assert state["attemptId"] == ready.id

      render_hook(view, "reset_import", %{"attempt_id" => ready.id})
      assert_reply(view, %{ok: false, reason: "import_not_cancellable"})

      assert import_state(view)["attemptId"] == ready.id
      assert Repo.get!(ProjectImportAttempt, ready.id).status == "running"
    end

    test "a strategy race adopts a terminal attempt when its broadcast was missed", %{
      conn: conn,
      project: project,
      user: user
    } do
      scope = Scope.for_user(user)

      assert {:ok, ready, _preview} =
               Imports.prepare_import(
                 scope,
                 project,
                 "terminal-strategy-race.yarn",
                 "title: Start\n---\nHello\n===\n"
               )

      {:ok, view, _html} = live(conn, export_url(project))
      assert import_state(view)["status"] == "ready"

      expired =
        ready
        |> ProjectImportAttempt.expired_changeset(TimeHelpers.now())
        |> Repo.update!()

      render_hook(view, "set_strategy", %{"attempt_id" => ready.id, "strategy" => "skip"})

      state = import_state(view)
      assert state["step"] == "error"
      assert state["status"] == "expired"
      assert state["attemptId"] == expired.id
    end

    test "review mutation races adopt the exact terminal attempt", %{
      conn: conn,
      project: project,
      user: user
    } do
      scope = Scope.for_user(user)

      mutations = [
        {"save_import_review", %{"review_decisions" => []}},
        {"validate_import_review", %{"review_acknowledged" => true, "review_decisions" => []}},
        {"execute_import", %{"review_confirmation_fingerprint" => "stale"}}
      ]

      for {event, params} <- mutations do
        assert {:ok, ready, _preview} =
                 Imports.prepare_import(
                   scope,
                   project,
                   "#{event}.yarn",
                   "title: #{event}\n---\nHello\n===\n"
                 )

        {:ok, view, _html} = live(conn, export_url(project))
        assert import_state(view)["attemptId"] == ready.id

        expired =
          ready
          |> ProjectImportAttempt.expired_changeset(TimeHelpers.now())
          |> Repo.update!()

        render_hook(view, event, Map.put(params, "attempt_id", ready.id))
        assert_reply(view, %{ok: false})

        state = import_state(view)
        assert state["step"] == "error"
        assert state["status"] == "expired"
        assert state["attemptId"] == expired.id
      end
    end

    test "reset dismisses an attempt that became terminal after the socket snapshot", %{
      conn: conn,
      project: project,
      user: user
    } do
      scope = Scope.for_user(user)

      assert {:ok, ready, _preview} =
               Imports.prepare_import(
                 scope,
                 project,
                 "terminal-reset-race.yarn",
                 "title: Start\n---\nHello\n===\n"
               )

      {:ok, view, _html} = live(conn, export_url(project))
      assert import_state(view)["status"] == "ready"

      ready
      |> ProjectImportAttempt.expired_changeset(TimeHelpers.now())
      |> Repo.update!()

      ready_id = ready.id
      render_hook(view, "reset_import", %{"attempt_id" => ready_id})
      assert_reply(view, %{ok: true, attempt_id: ^ready_id})

      state = import_state(view)
      assert state["step"] == "upload"
      assert state["attemptId"] == nil
    end

    test "a terminal update reveals another import that is still active", %{
      conn: conn,
      project: project,
      user: user
    } do
      scope = Scope.for_user(user)

      assert {:ok, older_active, _preview} =
               Imports.prepare_import(
                 scope,
                 project,
                 "older-active.yarn",
                 "title: OlderActive\n---\nStill active\n===\n"
               )

      assert {:ok, current, _preview} =
               Imports.prepare_import(
                 scope,
                 project,
                 "current.yarn",
                 "title: Current\n---\nFinishing\n===\n"
               )

      {:ok, view, _html} = live(conn, export_url(project))
      assert import_state(view)["attemptId"] == current.id

      expired =
        current
        |> ProjectImportAttempt.expired_changeset(TimeHelpers.now())
        |> Repo.update!()

      send(view.pid, {:project_import_updated, expired})
      _html = render(view)

      state = import_state(view)
      assert state["attemptId"] == older_active.id
      assert state["status"] == "ready"
      assert state["step"] == "preview"
    end

    test "a refused stale reset does not displace the attempt now displayed", %{
      conn: conn,
      project: project,
      user: user
    } do
      scope = Scope.for_user(user)

      assert {:ok, first, _preview} =
               Imports.prepare_import(
                 scope,
                 project,
                 "running.yarn",
                 "title: Running\n---\nStill writing\n===\n"
               )

      assert {:ok, queued} = Imports.enqueue_import(scope, first.id, :rename)

      Repo.update_all(
        from(attempt in ProjectImportAttempt, where: attempt.id == ^queued.id),
        set: [status: "running", stage: "materializing", started_at: TimeHelpers.now()]
      )

      assert {:ok, second, _preview} =
               Imports.prepare_import(
                 scope,
                 project,
                 "current.yarn",
                 "title: Current\n---\nKeep me visible\n===\n"
               )

      {:ok, view, _html} = live(conn, export_url(project))
      assert import_state(view)["attemptId"] == second.id

      render_hook(view, "reset_import", %{"attempt_id" => queued.id})
      assert_reply(view, %{ok: false, reason: "import_not_cancellable"})

      state = import_state(view)
      assert state["attemptId"] == second.id
      assert state["status"] == "ready"
      assert Repo.get!(ProjectImportAttempt, queued.id).status == "running"
    end

    test "reset cannot cancel an attempt from another project", %{
      conn: conn,
      project: project,
      user: user
    } do
      scope = Scope.for_user(user)
      other_project = project_fixture(user)

      assert {:ok, other_attempt, _preview} =
               Imports.prepare_import(
                 scope,
                 other_project,
                 "other-project.yarn",
                 "title: OtherProject\n---\nKeep this\n===\n"
               )

      {:ok, view, _html} = live(conn, export_url(project))
      assert import_state(view)["attemptId"] == nil

      other_attempt_id = other_attempt.id
      render_hook(view, "reset_import", %{"attempt_id" => other_attempt_id})
      assert_reply(view, %{ok: true, attempt_id: ^other_attempt_id})

      assert import_state(view)["attemptId"] == nil
      assert Repo.get!(ProjectImportAttempt, other_attempt.id).status == "ready"
    end

    test "mutations are bound to the attempt that initiated them", %{
      conn: conn,
      project: project,
      user: user
    } do
      scope = Scope.for_user(user)

      assert {:ok, first, _preview} =
               Imports.prepare_import(
                 scope,
                 project,
                 "first.yarn",
                 "title: First\n---\nHello\n===\n"
               )

      {:ok, view, _html} = live(conn, export_url(project))
      assert import_state(view)["attemptId"] == first.id

      assert {:ok, second, _preview} =
               Imports.prepare_import(
                 scope,
                 project,
                 "second.yarn",
                 "title: Second\n---\nHello\n===\n"
               )

      render_hook(view, "resume_import", %{"attempt_id" => second.id})
      assert_reply(view, %{ok: true, status: "ready"})
      assert import_state(view)["attemptId"] == second.id

      render_hook(view, "set_strategy", %{"attempt_id" => first.id, "strategy" => "skip"})
      assert Repo.get!(ProjectImportAttempt, first.id).conflict_strategy == "rename"

      render_hook(view, "save_import_review", %{
        "attempt_id" => first.id,
        "review_decisions" => []
      })

      assert_reply(view, %{ok: false, reason: "stale"})

      render_hook(view, "validate_import_review", %{
        "attempt_id" => first.id,
        "review_acknowledged" => true,
        "review_decisions" => []
      })

      assert_reply(view, %{ok: false, reason: "stale"})

      render_hook(view, "execute_import", %{
        "attempt_id" => first.id,
        "review_confirmation_fingerprint" => "stale"
      })

      assert_reply(view, %{ok: false, reason: "stale"})

      render_hook(view, "reset_import", %{"attempt_id" => first.id})
      first_id = first.id
      assert_reply(view, %{ok: true, attempt_id: ^first_id})

      render_hook(view, "reset_import", %{"attempt_id" => nil})
      assert_reply(view, %{ok: false, reason: "stale"})

      assert import_state(view)["attemptId"] == second.id
      assert Repo.get!(ProjectImportAttempt, first.id).status == "expired"
      assert Repo.get!(ProjectImportAttempt, second.id).status == "ready"
    end

    test "persists and validates Yarn review before executing its exact confirmed revision", %{
      conn: conn,
      project: project,
      user: user
    } do
      scope = Scope.for_user(user)

      source = """
      title: Start
      ---
      <<clear_slide>>
      <<start_slide>>
      SlideHeader: Introduction
      SlideImage: slide-1
      <<end_slide>>
      <<start_slide>>
      SlideHeader: Summary
      SlideImage: slide-2
      <<end_slide>>
      ===
      """

      assert {:ok, ready, _preview} =
               Imports.prepare_import(scope, project, "presentation.yarn", source)

      {:ok, view, _html} = live(conn, export_url(project))
      render_hook(view, "resume_import", %{"attempt_id" => ready.id})
      assert_reply(view, %{ok: true, status: "ready"})

      review = import_state(view)["preview"]["import_review"]
      issue_summary = import_state(view)["preview"]["issue_summary"]
      assert review["variable_count"] == 0
      assert review["preserved_channel_count"] == 2
      assert review["speaker_decision_count"] == 2
      assert review["compatibility_warning_count"] > 0
      assert review["requires_acknowledgement"] == true
      assert issue_summary["warning_count"] == review["compatibility_warning_count"]
      assert issue_summary["counts_by_code"] == review["compatibility_warning_counts_by_code"]

      assert review["speaker_decisions"]
             |> Enum.filter(&(&1["suggested_action"] == "preserve_literal"))
             |> Enum.map(& &1["speaker"])
             |> Enum.sort() == ["SlideHeader", "SlideImage"]

      assert review["possible_speaker_aliases"] == []

      decisions =
        Enum.map(review["speaker_decisions"], fn decision ->
          %{
            "speaker" => decision["speaker"],
            "action" => decision["suggested_action"]
          }
        end)

      render_hook(view, "execute_import", %{})
      # Consume this event's own reply so later assert_reply calls cannot
      # accidentally match it out of the mailbox.
      assert_reply(view, %{ok: false, reason: "invalid"})
      assert Repo.get!(ProjectImportAttempt, ready.id).status == "ready"
      assert import_state(view)["step"] == "preview"

      render_hook(view, "validate_import_review", %{
        "attempt_id" => ready.id,
        "review_acknowledged" => "true",
        "review_decisions" => decisions
      })

      assert_reply(view, %{ok: false, reason: "invalid"})
      assert Repo.get!(ProjectImportAttempt, ready.id).status == "ready"
      assert import_state(view)["step"] == "preview"

      render_hook(view, "validate_import_review", %{
        "attempt_id" => ready.id,
        "review_acknowledged" => false,
        "review_decisions" => decisions
      })

      assert_reply(view, %{ok: false, reason: "invalid"})
      assert Repo.get!(ProjectImportAttempt, ready.id).status == "ready"
      assert import_state(view)["step"] == "preview"

      render_hook(view, "save_import_review", %{
        "attempt_id" => ready.id,
        "review_decisions" => [List.first(decisions)]
      })

      assert_reply(view, %{ok: true})
      assert import_state(view)["preview"]["import_review_draft"]["decisions"] == [List.first(decisions)]

      render_hook(view, "validate_import_review", %{
        "attempt_id" => ready.id,
        "review_acknowledged" => true,
        "review_decisions" => decisions
      })

      assert_reply(
        view,
        %{ok: true, review_confirmation_fingerprint: fingerprint}
      )

      assert is_binary(fingerprint)
      assert Repo.get!(ProjectImportAttempt, ready.id).status == "ready"
      assert import_state(view)["preview"]["import_review_resolution"]["decision_fingerprint"] == fingerprint

      render_hook(view, "execute_import", %{
        "attempt_id" => ready.id,
        "review_confirmation_fingerprint" => "stale-fingerprint"
      })

      assert Repo.get!(ProjectImportAttempt, ready.id).status == "ready"

      render_hook(view, "execute_import", %{
        "attempt_id" => ready.id,
        "review_confirmation_fingerprint" => fingerprint
      })

      assert Repo.get!(ProjectImportAttempt, ready.id).status == "queued"
      assert import_state(view)["step"] == "queued"
    end

    test "expires a stored import plan that predates deterministic review", %{
      conn: conn,
      project: project,
      user: user
    } do
      scope = Scope.for_user(user)

      assert {:ok, ready, _preview} =
               Imports.prepare_import(
                 scope,
                 project,
                 "legacy.yarn",
                 "title: Start\n---\nAlice: Hello\n===\n"
               )

      assert {:ok, plan} = PlanStorage.load(ready.plan_storage_key)
      legacy_plan = %{plan | data: Map.delete(plan.data, "import_review")}
      assert {:ok, legacy_plan} = Shared.bind_plan_to_attempt(legacy_plan, ready.plan_storage_key)
      assert {:ok, _storage_key} = PlanStorage.store_at(ready.plan_storage_key, legacy_plan)

      {:ok, view, _html} = live(conn, export_url(project))
      render_hook(view, "resume_import", %{"attempt_id" => ready.id})
      assert_reply(view, %{ok: true, status: "ready"})

      assert import_state(view)["preview"]["import_review"] == nil

      render_hook(view, "execute_import", %{
        "attempt_id" => ready.id,
        "review_confirmation_fingerprint" => "not-required"
      })

      assert Repo.get!(ProjectImportAttempt, ready.id).status == "expired"
      assert import_state(view)["step"] == "error"
      assert {:error, :import_plan_unavailable} = PlanStorage.load(ready.plan_storage_key)
    end

    test "expires a stored import plan whose deterministic review is malformed", %{
      conn: conn,
      project: project,
      user: user
    } do
      scope = Scope.for_user(user)

      assert {:ok, ready, _preview} =
               Imports.prepare_import(
                 scope,
                 project,
                 "malformed-review.yarn",
                 "title: Start\n---\nAlice: Hello\n===\n"
               )

      assert {:ok, plan} = PlanStorage.load(ready.plan_storage_key)

      malformed_review =
        plan.data
        |> Map.fetch!("import_review")
        |> Map.delete("requires_acknowledgement")

      malformed_plan = %{plan | data: Map.put(plan.data, "import_review", malformed_review)}
      assert {:ok, malformed_plan} = Shared.bind_plan_to_attempt(malformed_plan, ready.plan_storage_key)
      assert {:ok, _storage_key} = PlanStorage.store_at(ready.plan_storage_key, malformed_plan)

      {:ok, view, _html} = live(conn, export_url(project))
      render_hook(view, "resume_import", %{"attempt_id" => ready.id})
      assert_reply(view, %{ok: true, status: "ready"})

      render_hook(view, "execute_import", %{
        "attempt_id" => ready.id,
        "review_confirmation_fingerprint" => "malformed-review"
      })

      assert Repo.get!(ProjectImportAttempt, ready.id).status == "expired"
      assert import_state(view)["step"] == "error"
      assert {:error, :import_plan_unavailable} = PlanStorage.load(ready.plan_storage_key)
    end

    test "reconciles a queued attempt after its completion broadcast was missed", %{
      conn: conn,
      project: project,
      user: user
    } do
      scope = Scope.for_user(user)

      assert {:ok, ready, _preview} =
               Imports.prepare_import(
                 scope,
                 project,
                 "project.yarn",
                 "title: Start\n---\nHello\n===\n"
               )

      assert {:ok, queued} = Imports.enqueue_import(scope, ready.id, :rename)

      {:ok, view, _html} = live(conn, export_url(project))
      render_hook(view, "resume_import", %{"attempt_id" => queued.id})
      assert_reply(view, %{ok: true, status: "queued"})
      assert import_state(view)["step"] == "queued"

      assert {:ok, completed} = Imports.perform_import(queued.id, attempt: 1, max_attempts: 3)

      render_hook(view, "reconcile_import", %{"attempt_id" => queued.id})
      assert_reply(view, %{ok: true, status: "completed"})

      state = import_state(view)
      assert state["step"] == "done"
      assert state["attemptId"] == completed.id
      assert state["preview"]["counts"] == completed.counts
    end

    test "polling a terminal attempt reveals another import that is still active", %{
      conn: conn,
      project: project,
      user: user
    } do
      scope = Scope.for_user(user)

      assert {:ok, older_active, _preview} =
               Imports.prepare_import(
                 scope,
                 project,
                 "older-active-poll.yarn",
                 "title: OlderActivePoll\n---\nStill active\n===\n"
               )

      assert {:ok, current, _preview} =
               Imports.prepare_import(
                 scope,
                 project,
                 "current-poll.yarn",
                 "title: CurrentPoll\n---\nFinishing\n===\n"
               )

      {:ok, view, _html} = live(conn, export_url(project))
      assert import_state(view)["attemptId"] == current.id

      current
      |> ProjectImportAttempt.expired_changeset(TimeHelpers.now())
      |> Repo.update!()

      render_hook(view, "reconcile_import", %{"attempt_id" => current.id})
      assert_reply(view, %{ok: true, status: "ready"})

      state = import_state(view)
      assert state["attemptId"] == older_active.id
      assert state["status"] == "ready"
      assert state["step"] == "preview"
    end

    test "rehydrates a terminal attempt completed while the page was closed", %{
      conn: conn,
      project: project,
      user: user
    } do
      scope = Scope.for_user(user)

      assert {:ok, ready, _preview} =
               Imports.prepare_import(
                 scope,
                 project,
                 "project.yarn",
                 "title: Start\n---\nHello\n===\n"
               )

      assert {:ok, queued} = Imports.enqueue_import(scope, ready.id, :rename)
      assert {:ok, completed} = Imports.perform_import(queued.id, attempt: 1, max_attempts: 3)

      {:ok, view, _html} = live(conn, export_url(project))
      render_hook(view, "resume_import", %{"attempt_id" => completed.id})
      assert_reply(view, %{ok: true, status: "completed"})

      state = import_state(view)
      assert state["step"] == "done"
      assert state["attemptId"] == completed.id
      assert state["preview"]["counts"] == completed.counts
    end

    test "a terminal browser reference cannot displace an import that is still active", %{
      conn: conn,
      project: project,
      user: user
    } do
      scope = Scope.for_user(user)

      assert {:ok, active, _preview} =
               Imports.prepare_import(
                 scope,
                 project,
                 "active.yarn",
                 "title: Active\n---\nStill running\n===\n"
               )

      assert {:ok, later, _preview} =
               Imports.prepare_import(
                 scope,
                 project,
                 "terminal.yarn",
                 "title: Terminal\n---\nAlready done\n===\n"
               )

      terminal =
        later
        |> ProjectImportAttempt.expired_changeset(TimeHelpers.now())
        |> Repo.update!()

      assert terminal.id > active.id

      {:ok, view, _html} = live(conn, export_url(project))
      assert import_state(view)["attemptId"] == active.id
      assert import_state(view)["status"] == "ready"

      render_hook(view, "resume_import", %{"attempt_id" => terminal.id})
      assert_reply(view, %{ok: false, reason: "superseded"})

      state = import_state(view)
      assert state["attemptId"] == active.id
      assert state["status"] == "ready"
      assert state["step"] == "preview"
    end

    test "rejects malformed, missing, and other-project resume references", %{
      conn: conn,
      project: project,
      user: user
    } do
      scope = Scope.for_user(user)
      other_project = project_fixture(user)

      assert {:ok, other_attempt, _preview} =
               Imports.prepare_import(
                 scope,
                 other_project,
                 "other.yarn",
                 "title: Other\n---\nHello\n===\n"
               )

      {:ok, view, _html} = live(conn, export_url(project))

      render_hook(view, "resume_import", %{"attempt_id" => "invalid"})
      assert_reply(view, %{ok: false, reason: "invalid"})
      assert import_state(view)["step"] == "upload"

      render_hook(view, "resume_import", %{"attempt_id" => 999_999_999})
      assert_reply(view, %{ok: false, reason: "not_found"})
      assert import_state(view)["step"] == "upload"

      render_hook(view, "resume_import", %{"attempt_id" => other_attempt.id})
      assert_reply(view, %{ok: false, reason: reason})
      assert reason in ["not_found", "unauthorized"]
      assert import_state(view)["step"] == "upload"
    end

    test "rejects unsafe numeric IDs before querying persistence", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_url(project))

      render_hook(view, "resume_import", %{"attempt_id" => 9_007_199_254_740_992})
      assert_reply(view, %{ok: false, reason: "invalid"})
      assert import_state(view)["step"] == "upload"
    end

    test "does not let a stale reconcile resurrect a reset queued attempt", %{
      conn: conn,
      project: project,
      user: user
    } do
      scope = Scope.for_user(user)

      assert {:ok, ready, _preview} =
               Imports.prepare_import(
                 scope,
                 project,
                 "project.yarn",
                 "title: Start\n---\nHello\n===\n"
               )

      assert {:ok, queued} = Imports.enqueue_import(scope, ready.id, :rename)
      {:ok, view, _html} = live(conn, export_url(project))

      render_hook(view, "resume_import", %{"attempt_id" => queued.id})
      assert_reply(view, %{ok: true, status: "queued"})
      assert import_state(view)["step"] == "queued"

      render_hook(view, "reset_import", %{"attempt_id" => queued.id})
      assert import_state(view)["step"] == "upload"

      render_hook(view, "reconcile_import", %{"attempt_id" => queued.id})
      assert_reply(view, %{ok: false, reason: "stale"})
      assert import_state(view)["step"] == "upload"
    end

    test "reset cancels a queued attempt so a later mount does not restore it", %{
      conn: conn,
      project: project,
      user: user
    } do
      scope = Scope.for_user(user)

      assert {:ok, ready, _preview} =
               Imports.prepare_import(scope, project, "project.yarn", "title: Start\n---\nHi\n===\n")

      assert {:ok, queued} = Imports.enqueue_import(scope, ready.id, :rename)

      {:ok, view, _html} = live(conn, export_url(project))
      render_hook(view, "resume_import", %{"attempt_id" => queued.id})
      assert_reply(view, %{ok: true, status: "queued"})
      assert import_state(view)["step"] == "queued"

      render_hook(view, "reset_import", %{"attempt_id" => queued.id})
      assert import_state(view)["step"] == "upload"

      # The durable attempt is what `mount/3` reads, so clearing the panel is
      # not enough: a live attempt comes straight back on the next navigation.
      assert Repo.get!(ProjectImportAttempt, queued.id).status == "expired"

      {:ok, remounted, _html} = live(conn, export_url(project))
      assert import_state(remounted)["step"] == "upload"
      refute import_state(remounted)["attemptId"]
    end

    test "reset refuses to dismiss a running import", %{conn: conn, project: project, user: user} do
      scope = Scope.for_user(user)

      assert {:ok, ready, _preview} =
               Imports.prepare_import(scope, project, "project.yarn", "title: Start\n---\nHi\n===\n")

      assert {:ok, queued} = Imports.enqueue_import(scope, ready.id, :rename)

      running =
        queued
        |> ProjectImportAttempt.running_changeset(TimeHelpers.now())
        |> Repo.update!()

      {:ok, view, _html} = live(conn, export_url(project))
      render_hook(view, "resume_import", %{"attempt_id" => running.id})
      assert_reply(view, %{ok: true, status: "running"})

      render_hook(view, "reset_import", %{"attempt_id" => running.id})
      # The refusal reason is what the client special-cases: it keeps the
      # durable browser reference when it sees it.
      assert_reply(view, %{ok: false, reason: "import_not_cancellable"})

      # An import that is materializing must stay on screen: it is writing.
      assert import_state(view)["step"] == "queued"
      assert Repo.get!(ProjectImportAttempt, running.id).status == "running"
    end

    test "a preview that cannot be rebuilt is shown as a resettable error", %{
      conn: conn,
      project: project,
      user: user
    } do
      scope = Scope.for_user(user)

      assert {:ok, ready, _preview} =
               Imports.prepare_import(scope, project, "project.yarn", "title: Start\n---\nHello\n===\n")

      # The encrypted plan is gone; the attempt survives. A silently empty
      # uploader left no way to clear it — it must surface as an error with
      # the attempt id on screen so Reset can terminalize it.
      :ok = PlanStorage.delete(ready.plan_storage_key)

      {:ok, view, _html} = live(conn, export_url(project))

      state = import_state(view)
      assert state["step"] == "error"
      assert state["attemptId"] == ready.id
      assert state["errorCode"] == "import_plan_unavailable"
      refute Map.has_key?(state, "error")

      render_hook(view, "reset_import", %{"attempt_id" => ready.id})
      assert_reply(view, %{ok: true})

      assert import_state(view)["step"] == "upload"
      assert Repo.get!(ProjectImportAttempt, ready.id).status == "expired"
    end

    test "reset terminalizes a ready attempt after enqueue cannot load its plan", %{
      conn: conn,
      project: project,
      user: user
    } do
      scope = Scope.for_user(user)

      assert {:ok, ready, _preview} =
               Imports.prepare_import(scope, project, "project.yarn", "title: Start\n---\nHello\n===\n")

      {:ok, view, _html} = live(conn, export_url(project))
      assert import_state(view)["attemptId"] == ready.id
      assert import_state(view)["status"] == "ready"

      # A transient storage failure during enqueue does not change the durable
      # attempt. The error projection must retain that ready status so Reset
      # cancels it instead of merely hiding it until the next mount.
      :ok = PlanStorage.delete(ready.plan_storage_key)

      render_hook(view, "execute_import", %{
        "attempt_id" => ready.id,
        "review_confirmation_fingerprint" => "not-required"
      })

      assert_reply(view, %{ok: false, reason: "unavailable"})
      assert import_state(view)["step"] == "error"
      assert import_state(view)["status"] == "ready"
      assert Repo.get!(ProjectImportAttempt, ready.id).status == "ready"

      render_hook(view, "reset_import", %{"attempt_id" => ready.id})
      assert_reply(view, %{ok: true})

      assert import_state(view)["step"] == "upload"
      assert Repo.get!(ProjectImportAttempt, ready.id).status == "expired"

      {:ok, remounted, _html} = live(conn, export_url(project))
      assert import_state(remounted)["step"] == "upload"
      refute import_state(remounted)["attemptId"]
    end

    test "an expired preview is reported as expired, not as a failure", %{
      conn: conn,
      project: project,
      user: user
    } do
      scope = Scope.for_user(user)

      assert {:ok, ready, _preview} =
               Imports.prepare_import(scope, project, "project.yarn", "title: Start\n---\nHi\n===\n")

      expired =
        ready
        |> ProjectImportAttempt.expired_changeset(TimeHelpers.now())
        |> Repo.update!()

      {:ok, view, _html} = live(conn, export_url(project))
      render_hook(view, "resume_import", %{"attempt_id" => expired.id})
      assert_reply(view, %{ok: true, status: "expired"})

      state = import_state(view)
      assert state["step"] == "error"
      assert state["errorCode"] == nil
      refute Map.has_key?(state, "error")
    end

    test "renders terminal failures from their code instead of persisted English copy", %{
      conn: conn,
      project: project,
      user: user
    } do
      scope = Scope.for_user(user)

      assert {:ok, ready, _preview} =
               Imports.prepare_import(scope, project, "failed.yarn", "title: Start\n---\nHi\n===\n")

      assert {:ok, queued} = Imports.enqueue_import(scope, ready.id, :rename)
      persisted_copy = "The import could not be completed. It may be retried automatically."

      failed =
        queued
        |> ProjectImportAttempt.failed_changeset(%{
          status: "failed",
          stage: "failed",
          error_code: "unexpected_import_error",
          error_message: persisted_copy,
          error_report: %{"attempt" => 3, "max_attempts" => 3},
          completed_at: TimeHelpers.now()
        })
        |> Repo.update!()

      {:ok, view, _html} = live(conn, export_url(project))
      render_hook(view, "resume_import", %{"attempt_id" => failed.id})
      assert_reply(view, %{ok: true, status: "failed"})

      state = import_state(view)
      assert state["errorCode"] == "unexpected_import_error"
      refute Map.has_key?(state, "error")
    end

    test "an editor sees no import surface", %{project: project} do
      editor = user_fixture()
      membership_fixture(project, editor, "editor")

      {:ok, view, _html} =
        build_conn()
        |> log_in_user(editor)
        |> live(export_url(project))

      vue = get_export_vue(view)

      refute vue.props["can-import"]
      refute vue.props["upload-config"]
    end

    test "stays connected when a linked process exits normally", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_url(project))

      send(view.pid, {:EXIT, self(), :normal})

      assert render(view)
      assert import_state(view)["step"] == "upload"
    end

    test "shows materialized counts and ignores stale import broadcasts", %{
      project: project,
      user: user
    } do
      _existing = flow_fixture(project, %{name: "Start"})
      scope = Scope.for_user(user)

      assert {:ok, ready, preview} =
               Imports.prepare_import(
                 scope,
                 project,
                 "project.yarn",
                 "title: Start\n---\nHello\n===\n"
               )

      assert {:ok, queued} = Imports.enqueue_import(scope, ready.id, :skip)
      assert queued.status == "queued"
      assert {:ok, completed} = Imports.perform_import(queued.id, attempt: 1, max_attempts: 3)

      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          current_scope: scope,
          import_state: %{
            step: "queued",
            attempt_id: queued.id,
            preview: %{
              counts: Map.new(preview.counts, fn {key, value} -> {to_string(key), value} end),
              conflicts: %{},
              has_conflicts: false
            },
            error: nil,
            conflict_strategy: "skip",
            warning_codes: [],
            status: "queued"
          }
        }
      }

      assert {:noreply, completed_socket} =
               Index.handle_info(
                 {:project_import_updated, completed},
                 socket
               )

      completed_state = completed_socket.assigns.import_state
      assert completed_state.step == "done"
      assert completed_state.preview.counts == completed.counts
      assert completed.counts["flows"] == 0
      assert completed.counts["nodes"] == 0

      assert {:noreply, after_stale_socket} =
               Index.handle_info(
                 {:project_import_updated, queued},
                 completed_socket
               )

      assert after_stale_socket.assigns.import_state.step == "done"
      assert after_stale_socket.assigns.import_state.preview.counts == completed.counts
    end

    test "does not expose Storyarn JSON as a visible export format", %{conn: conn, project: project} do
      {:ok, view, html} = live(conn, export_url(project))

      formats = visible_formats(view)
      assert is_list(formats)
      refute Enum.any?(formats, &(&1["format"] == "storyarn"))
      refute html =~ "Storyarn JSON"
    end

    test "defaults to the first visible engine format", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_url(project))

      assert selected_format(view) == "ink"
      assert format_extension(view) == "zip"
      assert download_url(view) =~ "/export/ink"
      refute download_url(view) =~ "/export/storyarn"
    end

    test "exposes supported content sections", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_url(project))

      section_config = export_config(view)["sectionConfig"]

      for section <- ~w(sheets flows scenes localization) do
        assert section in section_config["selected"]
      end
    end

    test "exposes the default export options", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_url(project))

      options = export_config(view)["options"]
      assert options["assetMode"] == "references"
      assert options["localizationPolicy"] == "release"
      assert options["validateBeforeExport"] == true
      assert options["prettyPrint"] == true
      assert export_config(view)["validation"] == nil
    end
  end

  describe "format selection" do
    test "lists only public engine formats", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_url(project))

      labels = Enum.map(visible_formats(view), & &1["label"])

      assert "Ink (.ink)" in labels
      assert "Yarn Spinner (.yarn)" in labels
      assert "Unity Dialogue System (JSON)" in labels
      assert "Godot Dialogic (.dtl)" in labels
      assert "Unreal Engine (CSV)" in labels
      assert "articy:draft (XML)" in labels
      refute "Storyarn JSON" in labels

      assert Enum.all?(visible_formats(view), &(&1["localizationMode"] in ~w(embedded external_catalog)))
    end

    test "switching format updates the displayed download extension", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_url(project))

      render_click(view, "set_format", %{"format" => "yarn"})

      assert selected_format(view) == "yarn"
      assert format_extension(view) == "zip"
      assert download_url(view) =~ "/export/yarn"

      render_click(view, "set_format", %{"format" => "unity"})

      assert selected_format(view) == "unity"
      assert format_extension(view) == "json"
      assert download_url(view) =~ "/export/unity"
    end

    test "invalid format is ignored", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_url(project))

      render_click(view, "set_format", %{"format" => "nonexistent_format"})

      assert selected_format(view) == "ink"
      assert format_extension(view) == "zip"
    end

    test "hidden storyarn format is ignored by the page", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_url(project))

      render_click(view, "set_format", %{"format" => "storyarn"})

      assert selected_format(view) == "ink"
      assert format_extension(view) == "zip"
      refute download_url(view) =~ "/export/storyarn"
    end
  end

  describe "export options" do
    test "toggling content sections updates selected sections", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_url(project))

      render_click(view, "toggle_section", %{"section" => "sheets"})

      refute "sheets" in export_config(view)["sectionConfig"]["selected"]
      assert download_url(view) =~ "sheets=false"
    end

    test "toggling options builds the expected query string", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_url(project))

      render_click(view, "toggle_option", %{"option" => "validate_before_export"})
      render_click(view, "toggle_option", %{"option" => "pretty_print"})
      render_click(view, "set_asset_mode", %{"mode" => "embedded"})

      url = download_url(view)
      assert url =~ "validate=false"
      assert url =~ "pretty=false"
      assert url =~ "assets=embedded"
    end

    test "invalid asset mode is ignored", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_url(project))

      render_click(view, "set_asset_mode", %{"mode" => "invalid"})

      assert export_config(view)["options"]["assetMode"] == "references"
    end

    test "localization policy is validated and included in the download URL", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_url(project))

      render_click(view, "set_localization_policy", %{"policy" => "preview"})

      assert export_config(view)["options"]["localizationPolicy"] == "preview"
      assert download_url(view) =~ "localization_policy=preview"

      render_click(view, "set_localization_policy", %{"policy" => "unsafe"})

      assert export_config(view)["options"]["localizationPolicy"] == "preview"
    end

    test "switching localization policy preserves validation findings", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_url(project))

      render_click(view, "validate_export", %{})
      status = validation_status(view)
      refute validation_stale?(view)

      render_click(view, "set_localization_policy", %{"policy" => "preview"})
      assert validation_status(view) == status
      assert validation_stale?(view)

      render_click(view, "validate_export", %{})
      refute validation_stale?(view)
    end

    test "format-specific findings stay visible but stale until the new format is validated", %{
      conn: conn,
      project: project
    } do
      sheet = sheet_fixture(project, %{name: "Variables"})
      flow = flow_fixture(project, %{name: "Stale References"})

      condition_node =
        node_fixture(flow, %{
          type: "condition",
          data: %{"condition" => condition(sheet.shortcut, "missing_variable")}
        })

      connect_from_entry(flow, condition_node)

      {:ok, view, _html} = live(conn, export_url(project))

      render_click(view, "validate_export", %{})

      assert validation_status(view) == "errors"
      refute validation_stale?(view)
      assert finding_rule?(view, "errors", "stale_variable_reference")

      render_click(view, "set_format", %{"format" => "unity"})

      assert validation_status(view) == "errors"
      assert validation_stale?(view)
      assert finding_rule?(view, "errors", "stale_variable_reference")
      assert download_url(view) =~ "/export/unity"

      render_click(view, "validate_export", %{})

      assert validation_status(view) == "warnings"
      refute validation_stale?(view)
      assert finding_rule?(view, "warnings", "stale_variable_reference")

      render_click(view, "set_format", %{"format" => "ink"})

      assert validation_status(view) == "warnings"
      assert validation_stale?(view)
      assert finding_rule?(view, "warnings", "stale_variable_reference")

      render_click(view, "validate_export", %{})

      assert validation_status(view) == "errors"
      refute validation_stale?(view)
      assert finding_rule?(view, "errors", "stale_variable_reference")
    end

    test "changing export settings preserves findings but invalidates their verdict", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, export_url(project))

      changes = [
        {"toggle_section", %{"section" => "sheets"}},
        {"set_asset_mode", %{"mode" => "embedded"}},
        {"toggle_option", %{"option" => "validate_before_export"}},
        {"toggle_option", %{"option" => "pretty_print"}}
      ]

      for {event, params} <- changes do
        render_click(view, "validate_export", %{})
        status = validation_status(view)
        refute validation_stale?(view)

        render_click(view, event, params)

        assert validation_status(view) == status
        assert validation_stale?(view)
      end
    end
  end

  describe "validation and counts" do
    test "validate_export produces a validation result", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_url(project))

      render_click(view, "validate_export", %{})

      assert validation_status(view) in ~w(passed warnings errors)
      refute validation_stale?(view)
    end

    test "serializes actionable findings with rule, count, and dashboard link", %{
      conn: conn,
      project: project
    } do
      flow = flow_fixture(project, %{name: "Editorial"})

      dialogue =
        node_fixture(flow, %{type: "dialogue", data: %{"text" => "", "responses" => []}})

      connect_from_entry(flow, dialogue)
      {:ok, view, _html} = live(conn, export_url(project))

      render_click(view, "validate_export", %{})

      finding = Enum.find(export_config(view)["validation"]["warnings"], &(&1["rule"] == "empty_dialogue"))

      assert finding["count"] == 1

      assert finding["href"] ==
               ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows"
    end

    test "node health findings focus the affected node when only entity_id is available", %{
      conn: conn,
      project: project
    } do
      flow = flow_fixture(project, %{name: "Stale Output"})

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Choose",
            "localization_id" => "dialogue_stale_output",
            "responses" => [%{"id" => "response_valid", "text" => "Continue"}]
          }
        })

      exit_node = node_fixture(flow, %{type: "exit", data: %{}})

      Repo.insert!(%FlowConnection{
        flow_id: flow.id,
        source_node_id: dialogue.id,
        target_node_id: exit_node.id,
        source_pin: "removed_response",
        target_pin: "input"
      })

      connect_from_entry(flow, dialogue)
      {:ok, view, _html} = live(conn, export_url(project))

      render_click(view, "validate_export", %{})

      finding =
        Enum.find(
          export_config(view)["validation"]["errors"],
          &(&1["rule"] == "invalid_output_pins")
        )

      base =
        ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"

      assert finding["href"] == "#{base}?highlight=node:#{dialogue.id}"
    end

    test "loads entity counts asynchronously", %{conn: conn, project: project} do
      import Storyarn.FlowsFixtures
      import Storyarn.SheetsFixtures

      _sheet = sheet_fixture(project)
      _flow = flow_fixture(project)

      {:ok, view, _html} = live(conn, export_url(project))
      _ = await_async(view)

      counts = entity_counts(view)
      assert counts["sheets"] >= 1
      assert counts["flows"] >= 1
    end
  end

  describe "authorization" do
    test "unauthenticated user gets redirected to login" do
      conn =
        build_conn()
        |> put_req_header("accept-language", "en")
        |> init_test_session(%{})

      assert {:error, redirect} =
               live(conn, ~p"/workspaces/some-ws/projects/some-proj/settings/export-import")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "user without project access gets redirected", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      other_user = user_fixture()
      project = other_user |> project_fixture() |> Repo.preload(:workspace)

      assert {:error, {:redirect, %{to: "/workspaces", flash: %{"error" => error_msg}}}} =
               live(conn, export_url(project))

      assert error_msg =~ "access"
    end

    test "viewer can export but receives a read-only importer", %{conn: conn} do
      viewer = user_fixture()
      conn = log_in_user(conn, viewer)

      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, viewer, "viewer")

      {:ok, view, html} = live(conn, export_url(project))

      assert html =~ "Export"
      assert get_export_vue(view).props["can-edit"] == false
      assert get_export_vue(view).props["upload-config"] == nil
      assert import_state(view)["step"] == "upload"
      assert download_url(view) =~ "/export/ink"
    end
  end

  defp finding_rule?(view, severity, rule) do
    view
    |> export_config()
    |> get_in(["validation", severity])
    |> Enum.any?(&(&1["rule"] == rule))
  end

  defp connect_from_entry(flow, node) do
    entry = flow.id |> Storyarn.Flows.list_nodes() |> Enum.find(&(&1.type == "entry"))
    connection_fixture(flow, entry, node)
  end

  defp condition(sheet, variable) do
    %{
      "logic" => "all",
      "blocks" => [
        %{
          "id" => "block_1",
          "type" => "block",
          "logic" => "all",
          "rules" => [
            %{
              "id" => "rule_1",
              "sheet" => sheet,
              "variable" => variable,
              "operator" => "equals",
              "value" => "value"
            }
          ]
        }
      ]
    }
  end
end

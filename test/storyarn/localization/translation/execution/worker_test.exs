defmodule Storyarn.Localization.Translation.Execution.WorkerTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import ExUnit.CaptureLog
  import Storyarn.AccountsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Localization
  alias Storyarn.Localization.ProviderConfig
  alias Storyarn.Localization.Translation
  alias Storyarn.Localization.TranslationRun
  alias Storyarn.Platform.Notifications
  alias Storyarn.Platform.Notifications.Notification
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.TestSupport.FakeTranslationProvider
  alias Storyarn.Workers.LocalizationBatchTranslationWorker

  setup do
    Application.put_env(:storyarn, :localization_translation_provider, FakeTranslationProvider)
    on_exit(fn -> Application.delete_env(:storyarn, :localization_translation_provider) end)

    user = user_fixture()
    project = project_fixture(user)
    _source = source_language_fixture(project)
    target = language_fixture(project, %{locale_code: "es", name: "Spanish"})
    create_provider_config(project.id)

    %{user: user, project: project, target: target}
  end

  test "enqueues and completes a persisted translation run", %{user: user, project: project} do
    for index <- 1..3 do
      localized_text_fixture(project.id, %{
        source_id: index,
        source_text: "Text #{index}",
        source_text_hash: source_text_hash("Text #{index}")
      })
    end

    Phoenix.PubSub.subscribe(Storyarn.PubSub, Translation.topic(project.id))
    :ok = Notifications.subscribe(user_scope_fixture(user))

    assert {:ok, run} = Localization.enqueue_batch_translation(project.id, "es", user.id)
    assert run.status == "queued"
    assert run.requested_by_id == user.id
    assert run.total_count == 3
    assert run.oban_job_id
    assert_enqueued(worker: LocalizationBatchTranslationWorker, args: %{run_id: run.id})

    queued_job = Storyarn.Repo.get!(Oban.Job, run.oban_job_id)
    assert queued_job.worker == inspect(LocalizationBatchTranslationWorker)
    assert queued_job.queue == "localization"
    assert queued_job.max_attempts == 3

    {lock_marker, lock_handler_id} = attach_terminal_lock_probe("localization_translation_runs")
    on_exit(fn -> :telemetry.detach(lock_handler_id) end)

    assert :ok = perform_job(LocalizationBatchTranslationWorker, %{run_id: run.id})

    assert_receive {^lock_marker, first_lock}
    assert_receive {^lock_marker, second_lock}
    assert_receive {^lock_marker, third_lock}
    assert [first_lock, second_lock, third_lock] == [:project, :requester, :run]

    completed = Localization.get_translation_run(project.id, run.id)
    assert completed.status == "completed"
    assert completed.processed_count == 3
    assert completed.translated_count == 3
    assert completed.failed_count == 0
    assert completed.completed_at
    assert_received {:translation_run_updated, %{status: "running"}}
    assert_received {:translation_run_updated, %{status: "completed"}}
    assert_received :notifications_changed

    notification = notification_for!(user.id, run.id)
    assert notification.kind == "async_operation"
    assert notification.entity_name == "es"
    assert notification.project_id == project.id
    assert notification.status == "success"
    assert notification.dedupe_key == "localization_batch:#{run.id}:success"

    assert Enum.all?(Localization.list_texts(project.id), fn text ->
             text.status == "draft" and
               text.translated_source_hash == text.source_text_hash
           end)

    assert :ok = perform_job(LocalizationBatchTranslationWorker, %{run_id: run.id})
    assert notification_count(user.id, run.id) == 1
  end

  test "prevents concurrent runs for the same locale", %{user: user, project: project} do
    assert {:ok, _run} = Localization.enqueue_batch_translation(project.id, "es", user.id)
    assert {:error, :already_running} = Localization.enqueue_batch_translation(project.id, "es", user.id)
  end

  test "terminalizes without a notification after the requester is nilified", %{
    user: user,
    project: project
  } do
    localized_text_fixture(project.id, %{source_text: "Translate after requester deletion"})

    assert {:ok, run} = Localization.enqueue_batch_translation(project.id, "es", user.id)

    assert {1, _rows} =
             Repo.update_all(
               from(candidate in TranslationRun, where: candidate.id == ^run.id),
               set: [requested_by_id: nil]
             )

    assert :ok = perform_job(LocalizationBatchTranslationWorker, %{run_id: run.id})

    completed = Localization.get_translation_run(project.id, run.id)
    assert completed.status == "completed"
    assert is_nil(completed.requested_by_id)
    assert notification_count(user.id, run.id) == 0
  end

  test "rolls back the terminal run and notification together", %{user: user, project: project} do
    localized_text_fixture(project.id, %{source_text: "Roll back this translation"})

    assert {:ok, run} = Localization.enqueue_batch_translation(project.id, "es", user.id)

    Phoenix.PubSub.subscribe(Storyarn.PubSub, Translation.topic(project.id))
    :ok = Notifications.subscribe(user_scope_fixture(user))

    assert {:error, :forced_rollback} =
             Repo.transact(fn ->
               assert {:ok, {completed, {:created, _notification}}} =
                        Translation.transition_terminal(run.id, %{
                          status: "completed",
                          processed_count: 1,
                          translated_count: 1,
                          failed_count: 0,
                          completed_at: TimeHelpers.now()
                        })

               assert completed.status == "completed"
               assert notification_count(user.id, run.id) == 1
               refute_receive {:translation_run_updated, _run}
               refute_receive :notifications_changed

               {:error, :forced_rollback}
             end)

    persisted = Localization.get_translation_run(project.id, run.id)
    assert persisted.status == "queued"
    assert persisted.processed_count == 0
    assert persisted.translated_count == 0
    assert is_nil(persisted.completed_at)
    assert notification_count(user.id, run.id) == 0
    refute_receive {:translation_run_updated, _run}
    refute_receive :notifications_changed
  end

  test "reports a completed batch with item failures as a successful outcome", %{
    user: user,
    project: project
  } do
    localized_text_fixture(project.id, %{source_text: "Translate me"})
    localized_text_fixture(project.id, %{source_text: nil, source_text_hash: nil, word_count: 0})

    assert {:ok, run} = Localization.enqueue_batch_translation(project.id, "es", user.id)
    assert :ok = perform_job(LocalizationBatchTranslationWorker, %{run_id: run.id})

    completed = Localization.get_translation_run(project.id, run.id)
    assert completed.status == "completed"
    assert completed.processed_count == 2
    assert completed.translated_count == 1
    assert completed.failed_count == 1

    notification = notification_for!(user.id, run.id)
    assert notification.status == "success"
    assert notification.dedupe_key == "localization_batch:#{run.id}:success"
  end

  test "rejects a non-terminal transition before updating the run", %{user: user, project: project} do
    assert {:ok, run} = Localization.enqueue_batch_translation(project.id, "es", user.id)

    assert {:error, :invalid_terminal_status} =
             Translation.transition_terminal(run.id, %{status: "running", error: "invalid"})

    persisted = Localization.get_translation_run(project.id, run.id)
    assert persisted.status == "queued"
    assert is_nil(persisted.error)
    assert notification_count(user.id, run.id) == 0
  end

  test "rolls back the terminal run and its notification together", %{user: user, project: project} do
    assert {:ok, run} = Localization.enqueue_batch_translation(project.id, "es", user.id)
    :ok = Notifications.subscribe(user_scope_fixture(user))

    assert {:error, :simulated_rollback} =
             Repo.transact(fn ->
               assert {:ok, {completed, {:created, %Notification{}}}} =
                        Translation.transition_terminal(run.id, %{
                          status: "completed",
                          completed_at: TimeHelpers.now()
                        })

               assert completed.status == "completed"
               assert notification_count(user.id, run.id) == 1
               refute_receive :notifications_changed
               {:error, :simulated_rollback}
             end)

    assert Localization.get_translation_run(project.id, run.id).status == "queued"
    assert notification_count(user.id, run.id) == 0
    refute_receive :notifications_changed
  end

  test "rejects an unsupported text status before enqueuing", %{user: user, project: project} do
    assert {:error, changeset} =
             Localization.enqueue_batch_translation(project.id, "es", user.id, status: "not-a-workflow-status")

    assert %{text_status: ["is invalid"]} = errors_on(changeset)
    refute_enqueued(worker: LocalizationBatchTranslationWorker)
  end

  test "cancels a queued run idempotently", %{user: user, project: project} do
    assert {:ok, run} = Localization.enqueue_batch_translation(project.id, "es", user.id)
    assert {:ok, cancelled} = Localization.cancel_translation_run(run)
    assert cancelled.status == "cancelled"
    assert cancelled.cancelled_at

    assert :ok = perform_job(LocalizationBatchTranslationWorker, %{run_id: run.id})
    assert Localization.get_translation_run(project.id, run.id).status == "cancelled"
    assert notification_count(user.id, run.id) == 0
  end

  test "archiving a target language cancels its active run", %{
    user: user,
    project: project,
    target: target
  } do
    assert {:ok, run} = Localization.enqueue_batch_translation(project.id, "es", user.id)

    assert {:ok, _archived} = Localization.remove_language(target)

    assert Localization.get_translation_run(project.id, run.id).status == "cancelled"
    assert :ok = perform_job(LocalizationBatchTranslationWorker, %{run_id: run.id})
  end

  test "keeps cumulative progress across a retry", %{user: user, project: project} do
    for index <- 1..101 do
      localized_text_fixture(project.id, %{
        source_id: index,
        source_text: "Text #{index}",
        source_text_hash: source_text_hash("Text #{index}")
      })
    end

    Process.put(:fake_translation_provider_responses, [:ok, {:error, :temporary}, :ok])
    on_exit(fn -> Process.delete(:fake_translation_provider_responses) end)

    assert {:ok, run} = Localization.enqueue_batch_translation(project.id, "es", user.id)

    assert {:error, :temporary} =
             LocalizationBatchTranslationWorker.perform(%Oban.Job{
               args: %{"run_id" => run.id},
               attempt: 1,
               max_attempts: 3
             })

    retrying = Localization.get_translation_run(project.id, run.id)
    assert retrying.status == "running"
    assert retrying.processed_count == 100
    assert retrying.translated_count == 100
    assert notification_count(user.id, run.id) == 0

    assert :ok =
             LocalizationBatchTranslationWorker.perform(%Oban.Job{
               args: %{"run_id" => run.id},
               attempt: 2,
               max_attempts: 3
             })

    completed = Localization.get_translation_run(project.id, run.id)
    assert completed.status == "completed"
    assert completed.processed_count == 101
    assert completed.translated_count == 101

    notification = notification_for!(user.id, run.id)
    assert notification.status == "success"
    assert notification.dedupe_key == "localization_batch:#{run.id}:success"
  end

  test "only marks provider errors failed on the final attempt", %{user: user, project: project} do
    localized_text_fixture(project.id, %{source_text: "Retry me"})
    Process.put(:fake_translation_provider_responses, [{:error, :temporary}])
    on_exit(fn -> Process.delete(:fake_translation_provider_responses) end)

    assert {:ok, run} = Localization.enqueue_batch_translation(project.id, "es", user.id)

    assert {:error, :temporary} =
             LocalizationBatchTranslationWorker.perform(%Oban.Job{
               args: %{"run_id" => run.id},
               attempt: 3,
               max_attempts: 3
             })

    failed = Localization.get_translation_run(project.id, run.id)
    assert failed.status == "failed"
    assert failed.completed_at

    notification = notification_for!(user.id, run.id)
    assert notification.kind == "async_operation"
    assert notification.entity_name == "es"
    assert notification.project_id == project.id
    assert notification.status == "failure"
    assert notification.dedupe_key == "localization_batch:#{run.id}:failure"
  end

  test "re-raises provider exceptions with their stacktrace and only notifies on the final attempt", %{
    user: user,
    project: project
  } do
    localized_text_fixture(project.id, %{source_text: "Raise while translating"})
    Process.put(:fake_translation_provider_responses, [:unexpected, :unexpected])
    on_exit(fn -> Process.delete(:fake_translation_provider_responses) end)

    assert {:ok, run} = Localization.enqueue_batch_translation(project.id, "es", user.id)

    retry_log =
      capture_log(fn ->
        assert_provider_exception(fn ->
          LocalizationBatchTranslationWorker.perform(%Oban.Job{
            args: %{"run_id" => run.id},
            attempt: 1,
            max_attempts: 3
          })
        end)
      end)

    assert retry_log =~ "Unexpected localization batch translation exception run_id=#{run.id}"
    assert retry_log =~ "FunctionClauseError"
    assert retry_log =~ "fake_translation_provider.ex"

    retrying = Localization.get_translation_run(project.id, run.id)
    assert retrying.status == "running"
    assert retrying.error =~ "FunctionClauseError"
    refute retrying.error =~ "FakeTranslationProvider"
    refute retrying.completed_at
    assert notification_count(user.id, run.id) == 0

    capture_log(fn ->
      assert_provider_exception(fn ->
        LocalizationBatchTranslationWorker.perform(%Oban.Job{
          args: %{"run_id" => run.id},
          attempt: 3,
          max_attempts: 3
        })
      end)
    end)

    failed = Localization.get_translation_run(project.id, run.id)
    assert failed.status == "failed"
    assert failed.error =~ "FunctionClauseError"
    refute failed.error =~ "FakeTranslationProvider"
    assert failed.completed_at

    notification = notification_for!(user.id, run.id)
    assert notification.status == "failure"
    assert notification.dedupe_key == "localization_batch:#{run.id}:failure"

    assert :ok =
             LocalizationBatchTranslationWorker.perform(%Oban.Job{
               args: %{"run_id" => run.id},
               attempt: 3,
               max_attempts: 3
             })

    assert notification_count(user.id, run.id) == 1
  end

  defp notification_for!(user_id, run_id) do
    Repo.get_by!(Notification,
      recipient_id: user_id,
      entity_type: "localization_batch",
      entity_id: run_id
    )
  end

  defp assert_provider_exception(fun) do
    fun.()
    flunk("expected the translation provider to raise")
  rescue
    exception in FunctionClauseError ->
      assert Enum.any?(__STACKTRACE__, fn
               {FakeTranslationProvider, :respond, _args_or_arity, _location} -> true
               _frame -> false
             end)

      exception
  end

  defp notification_count(user_id, run_id) do
    Repo.aggregate(
      from(notification in Notification,
        where:
          notification.recipient_id == ^user_id and
            notification.entity_type == "localization_batch" and
            notification.entity_id == ^run_id
      ),
      :count
    )
  end

  defp attach_terminal_lock_probe(source_table) do
    handler_id = "localization-terminal-lock-order-#{System.unique_integer([:positive])}"
    marker = make_ref()
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:storyarn, :repo, :query],
        &handle_terminal_lock_query/4,
        {test_pid, marker, source_table}
      )

    {marker, handler_id}
  end

  defp handle_terminal_lock_query(_event, _measurements, %{query: query}, {pid, ref, table}) do
    if self() == pid, do: maybe_send_terminal_lock(pid, ref, terminal_lock(query, table))
  end

  defp terminal_lock(query, table) do
    cond do
      String.contains?(query, ~s(FROM "projects")) and String.contains?(query, "FOR SHARE") -> :project
      String.contains?(query, ~s(FROM "users")) and String.contains?(query, "FOR KEY SHARE") -> :requester
      String.contains?(query, ~s(FROM "#{table}")) and String.contains?(query, "FOR UPDATE") -> :run
      true -> nil
    end
  end

  defp maybe_send_terminal_lock(_pid, _ref, nil), do: :ok
  defp maybe_send_terminal_lock(pid, ref, lock), do: send(pid, {ref, lock})

  defp create_provider_config(project_id) do
    %ProviderConfig{project_id: project_id}
    |> ProviderConfig.changeset(%{
      "provider" => "deepl",
      "api_key_encrypted" => "test-key-123",
      "api_endpoint" => "https://api-free.deepl.com",
      "is_active" => true
    })
    |> Storyarn.Repo.insert!()
  end

  defp source_text_hash(text) do
    :sha256
    |> :crypto.hash(text)
    |> Base.encode16(case: :lower)
  end
end

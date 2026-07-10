defmodule Storyarn.Workers.LocalizationBatchTranslationWorkerTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Storyarn.AccountsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Localization
  alias Storyarn.Localization.ProviderConfig
  alias Storyarn.Localization.TranslationRunCrud
  alias Storyarn.TestSupport.FakeTranslationProvider
  alias Storyarn.Workers.LocalizationBatchTranslationWorker

  setup do
    Application.put_env(:storyarn, :localization_translation_provider, FakeTranslationProvider)
    on_exit(fn -> Application.delete_env(:storyarn, :localization_translation_provider) end)

    user = user_fixture()
    project = project_fixture(user)
    _source = source_language_fixture(project)
    _target = language_fixture(project, %{locale_code: "es", name: "Spanish"})
    create_provider_config(project.id)

    %{user: user, project: project}
  end

  test "enqueues and completes a persisted translation run", %{user: user, project: project} do
    for index <- 1..3 do
      localized_text_fixture(project.id, %{
        source_id: index,
        source_text: "Text #{index}",
        source_text_hash: source_text_hash("Text #{index}")
      })
    end

    Phoenix.PubSub.subscribe(Storyarn.PubSub, TranslationRunCrud.topic(project.id))

    assert {:ok, run} = Localization.enqueue_batch_translation(project.id, "es", user.id)
    assert run.status == "queued"
    assert run.total_count == 3
    assert run.oban_job_id
    assert_enqueued(worker: LocalizationBatchTranslationWorker, args: %{run_id: run.id})

    assert :ok = perform_job(LocalizationBatchTranslationWorker, %{run_id: run.id})

    completed = Localization.get_translation_run(project.id, run.id)
    assert completed.status == "completed"
    assert completed.processed_count == 3
    assert completed.translated_count == 3
    assert completed.failed_count == 0
    assert completed.completed_at
    assert_received {:translation_run_updated, %{status: "running"}}
    assert_received {:translation_run_updated, %{status: "completed"}}

    assert Enum.all?(Localization.list_texts(project.id), fn text ->
             text.status == "draft" and
               text.translated_source_hash == text.source_text_hash
           end)
  end

  test "prevents concurrent runs for the same locale", %{user: user, project: project} do
    assert {:ok, _run} = Localization.enqueue_batch_translation(project.id, "es", user.id)
    assert {:error, :already_running} = Localization.enqueue_batch_translation(project.id, "es", user.id)
  end

  test "cancels a queued run idempotently", %{user: user, project: project} do
    assert {:ok, run} = Localization.enqueue_batch_translation(project.id, "es", user.id)
    assert {:ok, cancelled} = Localization.cancel_translation_run(run)
    assert cancelled.status == "cancelled"
    assert cancelled.cancelled_at

    assert :ok = perform_job(LocalizationBatchTranslationWorker, %{run_id: run.id})
    assert Localization.get_translation_run(project.id, run.id).status == "cancelled"
  end

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

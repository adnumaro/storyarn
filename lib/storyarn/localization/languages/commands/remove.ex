defmodule Storyarn.Localization.Languages.Commands.Remove do
  @moduledoc false

  alias Storyarn.Localization.Languages.Adapters.Notifications.Delivery
  alias Storyarn.Localization.Languages.Commands.Locks
  alias Storyarn.Localization.ProjectLanguage
  alias Storyarn.Localization.Texts
  alias Storyarn.Localization.Translation
  alias Storyarn.Repo

  def run(%ProjectLanguage{} = language), do: run_for_actor(nil, language)

  def run(%{user: %{id: actor_id}} = actor_scope, %ProjectLanguage{} = language)
      when is_integer(actor_id) and actor_id > 0 do
    result = run_for_actor(actor_scope, language)

    case result do
      {:ok, {archived, notification_outcome}} ->
        Delivery.publish_committed(notification_outcome)
        {:ok, archived}

      other ->
        other
    end
  end

  def run(%{user: _user}, %ProjectLanguage{}), do: {:error, :not_found}

  defp run_for_actor(actor_scope, language) do
    fn ->
      project = Locks.lock_project!(language.project_id)
      :ok = Texts.lock_inventory!(language.project_id)
      locked_language = Locks.lock_language!(language.project_id, language.id)

      archived = archive_language!(locked_language)
      outcome = maybe_deliver_content_activity!(actor_scope, project, :deleted, archived)

      :ok = cancel_active_translation_run(archived)
      {archived, outcome}
    end
    |> Repo.transaction()
    |> case do
      {:ok, {archived, :suppressed}} -> {:ok, archived}
      other -> other
    end
  end

  defp archive_language!(%ProjectLanguage{is_source: true}), do: Repo.rollback(:source_language)

  defp archive_language!(%ProjectLanguage{} = language) do
    case language
         |> ProjectLanguage.update_changeset(%{
           "archived_at" => Storyarn.Platform.Shared.TimeHelpers.now()
         })
         |> Repo.update() do
      {:ok, archived} -> archived
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp maybe_deliver_content_activity!(nil, _project, _action, _language), do: :suppressed

  defp maybe_deliver_content_activity!(%{user: %{id: actor_id}}, project, action, language)
       when is_integer(actor_id) and actor_id > 0 do
    case Delivery.deliver_content_activity(
           actor_id,
           project.id,
           action,
           "localization_language",
           language
         ) do
      {:ok, outcome} -> outcome
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp cancel_active_translation_run(language) do
    case Translation.get_active(language.project_id, language.locale_code) do
      nil -> :ok
      run -> run |> Translation.cancel() |> then(fn {:ok, _run} -> :ok end)
    end
  end
end

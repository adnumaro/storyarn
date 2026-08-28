defmodule Storyarn.Projects.LocalizationSettings do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Platform
  alias Storyarn.Projects.LocalizationLanguageCatalog
  alias Storyarn.Projects.LocalizationLocaleCode
  alias Storyarn.Projects.LocalizationProjection
  alias Storyarn.Projects.LocalizationReadModel
  alias Storyarn.Projects.Persistence.LocalizedTextRecord
  alias Storyarn.Projects.Persistence.ProjectLanguageRecord
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectCrud
  alias Storyarn.Repo

  def ensure_source_language(%Project{} = project) do
    case LocalizationReadModel.get_source_language(project.id) do
      %ProjectLanguageRecord{} = language ->
        {:ok, language}

      nil ->
        Repo.transaction(fn -> ensure_source_language_in_transaction!(project.id) end)
    end
  end

  defp ensure_source_language_in_transaction!(project_id) do
    locked_project = lock_project!(project_id)
    LocalizationProjection.lock_inventory!(locked_project.id)

    case LocalizationReadModel.get_source_language(locked_project.id) do
      %ProjectLanguageRecord{} = language ->
        language

      nil ->
        project_with_workspace = Repo.preload(locked_project, :workspace)
        locale = LocalizationLocaleCode.normalize(project_with_workspace.workspace.source_locale || "en")

        ensure_source_language_record!(locked_project.id, locale)
    end
  end

  defp ensure_source_language_record!(project_id, locale_code) do
    attrs = %{
      "name" => LocalizationLanguageCatalog.name(locale_code),
      "is_source" => true,
      "position" => next_position(project_id)
    }

    result =
      case get_language_by_locale(project_id, locale_code, true) do
        %ProjectLanguageRecord{} = archived ->
          archived
          |> ProjectLanguageRecord.update_changeset(Map.put(attrs, "archived_at", nil))
          |> Repo.update()

        nil ->
          %ProjectLanguageRecord{project_id: project_id}
          |> ProjectLanguageRecord.create_changeset(Map.put(attrs, "locale_code", locale_code))
          |> Repo.insert()
      end

    case result do
      {:ok, language} -> language
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  def change_source_language(%{user: %{id: actor_id}} = actor_scope, %Project{} = project, locale_code, opts)
      when is_integer(actor_id) and actor_id > 0 and is_binary(locale_code) and is_list(opts) do
    case change_source_language_for_actor(actor_scope, project, locale_code, opts) do
      {:ok, {language, notification_outcome}} ->
        Platform.publish_notification_delivery(notification_outcome)
        {:ok, language}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp change_source_language_for_actor(actor_scope, project, locale_code, opts) do
    locale_code = LocalizationLocaleCode.normalize(locale_code)
    reset_translations? = Keyword.get(opts, :reset_translations, false)

    Repo.transaction(fn ->
      locked_project = lock_project!(project.id)
      LocalizationProjection.lock_inventory!(locked_project.id)

      with {:ok, authorized_project} <- authorize_actor_project(actor_scope, locked_project),
           {language, persistence} <-
             change_source_in_transaction(locked_project.id, locale_code, reset_translations?),
           {:ok, _count} <- LocalizationProjection.extract_all(locked_project.id) do
        notification_outcome =
          maybe_deliver_created_content_activity!(
            actor_scope,
            authorized_project,
            language,
            persistence
          )

        {language, notification_outcome}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp change_source_in_transaction(project_id, locale_code, reset_translations?) do
    current_source =
      LocalizationReadModel.get_source_language(project_id) || Repo.rollback(:no_source_language)

    cond do
      current_source.locale_code == locale_code ->
        {current_source, :existing}

      translations_exist?(project_id) and not reset_translations? ->
        Repo.rollback(:translations_exist)

      true ->
        {candidate, persistence} = find_or_create_source_candidate(project_id, locale_code)
        language = promote_source_language(candidate, project_id)
        if reset_translations?, do: reset_translations(project_id)
        {language, persistence}
    end
  end

  defp find_or_create_source_candidate(project_id, locale_code) do
    case get_language_by_locale(project_id, locale_code, false) do
      %ProjectLanguageRecord{} = language ->
        {language, :existing}

      nil ->
        case get_language_by_locale(project_id, locale_code, true) do
          %ProjectLanguageRecord{} = archived ->
            language =
              archived
              |> ProjectLanguageRecord.update_changeset(%{"archived_at" => nil})
              |> Repo.update!()

            {language, :reactivated}

          nil ->
            language =
              %ProjectLanguageRecord{project_id: project_id}
              |> ProjectLanguageRecord.create_changeset(%{
                "locale_code" => locale_code,
                "name" => LocalizationLanguageCatalog.name(locale_code),
                "is_source" => false,
                "position" => next_position(project_id)
              })
              |> Repo.insert!()

            {language, :inserted}
        end
    end
  end

  defp promote_source_language(next_source, project_id) do
    Repo.update_all(
      from(language in ProjectLanguageRecord,
        where: language.project_id == ^project_id and language.is_source == true
      ),
      set: [is_source: false]
    )

    case next_source
         |> ProjectLanguageRecord.update_changeset(%{"is_source" => true, "archived_at" => nil})
         |> Repo.update() do
      {:ok, updated} -> updated
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp get_language_by_locale(project_id, locale_code, archived?) do
    archive_condition =
      if archived?,
        do: dynamic([language], not is_nil(language.archived_at)),
        else: dynamic([language], is_nil(language.archived_at))

    ProjectLanguageRecord
    |> where([language], language.project_id == ^project_id and language.locale_code == ^locale_code)
    |> where(^archive_condition)
    |> order_by([language], desc: language.archived_at, desc: language.id)
    |> limit(1)
    |> Repo.one()
  end

  defp translations_exist?(project_id) do
    Repo.exists?(from(text in LocalizedTextRecord, where: text.project_id == ^project_id))
  end

  defp reset_translations(project_id) do
    Repo.delete_all(from(text in LocalizedTextRecord, where: text.project_id == ^project_id))
  end

  defp next_position(project_id) do
    ProjectLanguageRecord
    |> where([language], language.project_id == ^project_id)
    |> select([language], coalesce(max(language.position), -1))
    |> Repo.one!()
    |> Kernel.+(1)
  end

  defp authorize_actor_project(%{user: nil}, _project), do: {:error, :not_found}

  defp authorize_actor_project(%{user: %{id: actor_id}} = actor_scope, project)
       when is_integer(actor_id) and actor_id > 0 do
    case ProjectCrud.get_project(actor_scope, project.id) do
      {:ok, authorized_project, _membership} -> {:ok, authorized_project}
      {:error, _reason} -> {:error, :not_found}
    end
  end

  defp maybe_deliver_created_content_activity!(_scope, _project, _language, persistence)
       when persistence in [:existing, :reactivated], do: :suppressed

  defp maybe_deliver_created_content_activity!(actor_scope, project, language, :inserted) do
    case Platform.deliver_content_activity_by_ids(
           actor_scope.user.id,
           project.id,
           :created,
           "localization_language",
           language
         ) do
      {:ok, outcome} -> outcome
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp lock_project!(project_id) do
    case Repo.one(from(project in Project, where: project.id == ^project_id, lock: "FOR UPDATE")) do
      %Project{deleted_at: nil} = project -> project
      %Project{} -> Repo.rollback(:project_not_active)
      nil -> Repo.rollback(:project_not_found)
    end
  end
end

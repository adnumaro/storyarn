defmodule Storyarn.Localization.Languages.Commands.ChangeSource do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Localization.Languages.Adapters.Notifications.Delivery
  alias Storyarn.Localization.Languages.Commands.Locks
  alias Storyarn.Localization.Languages.Projections.ProjectRecord
  alias Storyarn.Localization.Languages.Queries.Languages, as: LanguageQueries
  alias Storyarn.Localization.Languages.ReferenceData.Catalog
  alias Storyarn.Localization.LocaleCode
  alias Storyarn.Localization.ProjectAccess
  alias Storyarn.Localization.ProjectLanguage
  alias Storyarn.Localization.Texts
  alias Storyarn.Repo

  defguardp is_positive_id(value) when is_integer(value) and value > 0

  def set(%ProjectLanguage{} = language) do
    ProjectRecord
    |> Repo.get!(language.project_id)
    |> run(language.locale_code)
  end

  def run(%{id: project_id} = project, locale_code)
      when is_integer(project_id) and project_id > 0 and is_binary(locale_code) do
    run(project, locale_code, [])
  end

  def run(%{user: %{id: actor_id}} = actor_scope, %{id: project_id} = project, locale_code)
      when is_positive_id(actor_id) and is_positive_id(project_id) and is_binary(locale_code) do
    run(actor_scope, project, locale_code, [])
  end

  def run(%{user: _user}, %{id: project_id}, locale_code)
      when is_integer(project_id) and project_id > 0 and is_binary(locale_code), do: {:error, :not_found}

  def run(%{id: project_id} = project, locale_code, opts)
      when is_integer(project_id) and project_id > 0 and is_binary(locale_code) do
    case run_for_actor(nil, project, locale_code, opts) do
      {:ok, {language, _notification_outcome}} -> {:ok, language}
      {:error, reason} -> {:error, reason}
    end
  end

  def run(%{user: %{id: actor_id}} = actor_scope, %{id: project_id} = project, locale_code, opts)
      when is_positive_id(actor_id) and is_positive_id(project_id) and is_binary(locale_code) do
    case run_for_actor(actor_scope, project, locale_code, opts) do
      {:ok, {language, notification_outcome}} ->
        Delivery.publish_committed(notification_outcome)
        {:ok, language}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def run(%{user: _user}, %{id: project_id}, locale_code, _opts)
      when is_integer(project_id) and project_id > 0 and is_binary(locale_code), do: {:error, :not_found}

  defp run_for_actor(actor_scope, project, locale_code, opts) do
    locale_code = LocaleCode.normalize(locale_code)
    reset_translations? = Keyword.get(opts, :reset_translations, false)

    Repo.transaction(fn ->
      locked_project = Locks.lock_project!(project.id)
      :ok = Texts.lock_inventory!(project.id)

      with {:ok, authorized_project} <- authorize_actor_project(actor_scope, locked_project),
           {language, persistence} <-
             change_source_in_transaction(project.id, locale_code, reset_translations?),
           {:ok, _count} <- Texts.extract_all(project.id) do
        notification_outcome =
          maybe_deliver_created_content_activity!(actor_scope, authorized_project, language, persistence)

        {language, notification_outcome}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp authorize_actor_project(nil, project), do: {:ok, project}
  defp authorize_actor_project(%{user: nil}, _project), do: {:error, :not_found}

  defp authorize_actor_project(%{user: %{id: actor_id}} = actor_scope, project)
       when is_integer(actor_id) and actor_id > 0 do
    case ProjectAccess.get_project(actor_scope, project.id) do
      {:ok, authorized_project, _membership} -> {:ok, authorized_project}
      {:error, _reason} -> {:error, :not_found}
    end
  end

  defp authorize_actor_project(_actor_scope, _project), do: {:error, :not_found}

  defp maybe_deliver_created_content_activity!(_actor_scope, _project, _language, :reactivated), do: :suppressed

  defp maybe_deliver_created_content_activity!(_actor_scope, _project, _language, :existing), do: :suppressed

  defp maybe_deliver_created_content_activity!(actor_scope, project, language, :inserted) do
    maybe_deliver_content_activity!(actor_scope, project, :created, language)
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

  defp change_source_in_transaction(project_id, locale_code, reset_translations?) do
    current_source = current_source_or_rollback(project_id)

    cond do
      current_source.locale_code == locale_code ->
        {current_source, :existing}

      LanguageQueries.translations_exist?(project_id) and not reset_translations? ->
        Repo.rollback(:translations_exist)

      true ->
        {candidate, persistence} = find_or_create_source_candidate(project_id, locale_code)

        language =
          candidate
          |> promote_source_language(project_id)
          |> maybe_reset_translations(project_id, reset_translations?)

        {language, persistence}
    end
  end

  defp current_source_or_rollback(project_id) do
    case LanguageQueries.get_source(project_id) do
      %ProjectLanguage{} = language -> language
      nil -> Repo.rollback(:no_source_language)
    end
  end

  defp find_or_create_source_candidate(project_id, locale_code) do
    case LanguageQueries.get_by_locale(project_id, locale_code) do
      %ProjectLanguage{} = language ->
        {language, :existing}

      nil ->
        reactivate_or_insert_source_candidate(project_id, locale_code)
    end
  end

  defp reactivate_or_insert_source_candidate(project_id, locale_code) do
    case LanguageQueries.get_archived_by_locale(project_id, locale_code) do
      %ProjectLanguage{} = archived ->
        language =
          archived
          |> ProjectLanguage.update_changeset(%{"archived_at" => nil})
          |> Repo.update!()

        {language, :reactivated}

      nil ->
        language =
          %ProjectLanguage{project_id: project_id}
          |> ProjectLanguage.create_changeset(%{
            "locale_code" => locale_code,
            "name" => Catalog.name(locale_code),
            "is_source" => false,
            "position" => LanguageQueries.next_position(project_id)
          })
          |> Repo.insert!()

        {language, :inserted}
    end
  end

  defp promote_source_language(next_source, project_id) do
    Repo.update_all(
      from(language in ProjectLanguage,
        where: language.project_id == ^project_id and language.is_source == true
      ),
      set: [is_source: false]
    )

    case next_source
         |> ProjectLanguage.update_changeset(%{"is_source" => true, "archived_at" => nil})
         |> Repo.update() do
      {:ok, updated} -> updated
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp maybe_reset_translations(language, project_id, true) do
    Texts.reset_project_texts(project_id)
    language
  end

  defp maybe_reset_translations(language, _project_id, false), do: language
end

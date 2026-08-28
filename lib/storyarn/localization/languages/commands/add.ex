defmodule Storyarn.Localization.Languages.Commands.Add do
  @moduledoc false

  alias Storyarn.Localization.Languages.Adapters.Notifications.Delivery
  alias Storyarn.Localization.Languages.Commands.Locks
  alias Storyarn.Localization.Languages.Queries.Languages, as: LanguageQueries
  alias Storyarn.Localization.ProjectAccess
  alias Storyarn.Localization.ProjectLanguage
  alias Storyarn.Localization.Texts
  alias Storyarn.Platform.Kernel.MapAccess
  alias Storyarn.Repo

  def run(%{user: %{id: actor_id}} = actor_scope, %{id: project_id} = project, attrs)
      when is_integer(actor_id) and actor_id > 0 and is_integer(project_id) and project_id > 0 do
    case run_with_count(actor_scope, project, attrs) do
      {:ok, %{language: language}} -> {:ok, language}
      {:error, reason} -> {:error, reason}
    end
  end

  def run(%{user: _user}, %{id: project_id}, _attrs) when is_integer(project_id) and project_id > 0,
    do: {:error, :not_found}

  def run(%{id: project_id} = project, attrs) when is_integer(project_id) and project_id > 0 do
    case run_with_count(project, attrs) do
      {:ok, %{language: language}} -> {:ok, language}
      {:error, reason} -> {:error, reason}
    end
  end

  def run_with_count(%{user: %{id: actor_id}} = actor_scope, %{id: project_id} = project, attrs)
      when is_integer(actor_id) and actor_id > 0 and is_integer(project_id) and project_id > 0 do
    result = run_with_count_for_actor(actor_scope, project, attrs)

    case result do
      {:ok, %{notification_outcome: outcome} = value} ->
        Delivery.publish_committed(outcome)
        {:ok, Map.delete(value, :notification_outcome)}

      other ->
        other
    end
  end

  def run_with_count(%{user: _user}, %{id: project_id}, _attrs) when is_integer(project_id) and project_id > 0,
    do: {:error, :not_found}

  def run_with_count(%{id: project_id} = project, attrs) when is_integer(project_id) and project_id > 0 do
    case run_with_count_for_actor(nil, project, attrs) do
      {:ok, value} -> {:ok, Map.delete(value, :notification_outcome)}
      other -> other
    end
  end

  defp run_with_count_for_actor(actor_scope, project, attrs) do
    attrs = MapAccess.stringify_keys(attrs)

    Repo.transaction(fn ->
      Locks.lock_project!(project.id)
      :ok = Texts.lock_inventory!(project.id)

      with {:ok, authorized_project} <- authorize_actor_project(actor_scope, project),
           {:ok, {language, persistence}} <- persist_language(authorized_project, attrs),
           {:ok, count} <- collect_existing_sources(project.id, language) do
        outcome =
          maybe_deliver_created_content_activity!(actor_scope, authorized_project, language, persistence)

        %{language: language, extracted_count: count, notification_outcome: outcome}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp persist_language(project, attrs) do
    case LanguageQueries.get_archived_by_locale(project.id, attrs["locale_code"]) do
      %ProjectLanguage{} = archived ->
        tag_language_persistence(reactivate_language(archived, project.id, attrs), :reactivated)

      nil ->
        tag_language_persistence(insert_language(project.id, attrs), :inserted)
    end
  end

  defp tag_language_persistence({:ok, language}, persistence), do: {:ok, {language, persistence}}
  defp tag_language_persistence({:error, reason}, _persistence), do: {:error, reason}

  defp reactivate_language(archived, project_id, attrs) do
    archived
    |> ProjectLanguage.update_changeset(%{
      "archived_at" => nil,
      "is_source" => Map.get(attrs, "is_source", archived.is_source),
      "name" => attrs["name"] || archived.name,
      "position" => attrs["position"] || LanguageQueries.next_position(project_id)
    })
    |> Repo.update()
  end

  defp insert_language(project_id, attrs) do
    position = attrs["position"] || LanguageQueries.next_position(project_id)

    %ProjectLanguage{project_id: project_id}
    |> ProjectLanguage.create_changeset(Map.put(attrs, "position", position))
    |> Repo.insert()
  end

  defp collect_existing_sources(_project_id, %ProjectLanguage{is_source: true}), do: {:ok, 0}

  defp collect_existing_sources(project_id, %ProjectLanguage{is_source: false} = language) do
    case Texts.extract_locale(project_id, language.locale_code) do
      {:ok, count} -> {:ok, count}
      {:error, reason} -> {:error, {:localization_sync_failed, reason}}
    end
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
end

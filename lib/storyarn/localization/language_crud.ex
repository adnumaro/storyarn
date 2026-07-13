defmodule Storyarn.Localization.LanguageCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Localization.Languages
  alias Storyarn.Localization.LocalizableWords
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Localization.ProjectLanguage
  alias Storyarn.Localization.TranslationRunCrud
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Shared.MapUtils
  alias Storyarn.Shared.TreeOperations

  # =============================================================================
  # Queries
  # =============================================================================

  def list_languages(project_id) do
    Repo.all(
      from(l in ProjectLanguage,
        where: l.project_id == ^project_id and is_nil(l.archived_at),
        order_by: [asc: l.position, asc: l.name]
      )
    )
  end

  @doc "Lists active and archived languages for native backup and version snapshots."
  def list_languages_for_backup(project_id) do
    Repo.all(
      from(l in ProjectLanguage,
        where: l.project_id == ^project_id,
        order_by: [asc: l.position, asc: l.name]
      )
    )
  end

  def get_language(project_id, language_id) do
    Repo.one(
      from(l in ProjectLanguage,
        where: l.project_id == ^project_id and l.id == ^language_id and is_nil(l.archived_at)
      )
    )
  end

  def get_language_by_locale(project_id, locale_code) do
    Repo.one(
      from(l in ProjectLanguage,
        where: l.project_id == ^project_id and l.locale_code == ^locale_code and is_nil(l.archived_at)
      )
    )
  end

  def get_source_language(project_id) do
    Repo.one(
      from(l in ProjectLanguage,
        where: l.project_id == ^project_id and l.is_source == true and is_nil(l.archived_at)
      )
    )
  end

  def get_target_languages(project_id) do
    Repo.all(
      from(l in ProjectLanguage,
        where: l.project_id == ^project_id and l.is_source == false and is_nil(l.archived_at),
        order_by: [asc: l.position, asc: l.name]
      )
    )
  end

  # =============================================================================
  # Mutations
  # =============================================================================

  def add_language(%Project{} = project, attrs) do
    case add_language_with_count(project, attrs) do
      {:ok, %{language: language}} -> {:ok, language}
      {:error, reason} -> {:error, reason}
    end
  end

  def add_language_with_count(%Project{} = project, attrs) do
    attrs = MapUtils.stringify_keys(attrs)

    Repo.transaction(fn ->
      with {:ok, language} <- persist_language(project, attrs),
           {:ok, count} <- collect_existing_sources(project.id, language) do
        %{language: language, extracted_count: count}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp persist_language(project, attrs) do
    case get_archived_language_by_locale(project.id, attrs["locale_code"]) do
      %ProjectLanguage{} = archived -> reactivate_language(archived, project.id, attrs)
      nil -> insert_language(project.id, attrs)
    end
  end

  defp reactivate_language(archived, project_id, attrs) do
    archived
    |> ProjectLanguage.update_changeset(%{
      "archived_at" => nil,
      "is_source" => Map.get(attrs, "is_source", archived.is_source),
      "name" => attrs["name"] || archived.name,
      "position" => attrs["position"] || next_position(project_id)
    })
    |> Repo.update()
  end

  defp insert_language(project_id, attrs) do
    position = attrs["position"] || next_position(project_id)

    %ProjectLanguage{project_id: project_id}
    |> ProjectLanguage.create_changeset(Map.put(attrs, "position", position))
    |> Repo.insert()
  end

  defp collect_existing_sources(_project_id, %ProjectLanguage{is_source: true}), do: {:ok, 0}

  defp collect_existing_sources(project_id, %ProjectLanguage{is_source: false}) do
    LocalizableWords.extract_all(project_id)
  end

  def update_language(%ProjectLanguage{} = language, attrs) do
    attrs = MapUtils.stringify_keys(attrs)

    language
    |> ProjectLanguage.update_changeset(attrs)
    |> Repo.update()
  end

  def remove_language(%ProjectLanguage{} = language) do
    if language.is_source do
      {:error, :source_language}
    else
      with {:ok, archived} <-
             language
             |> ProjectLanguage.update_changeset(%{"archived_at" => Storyarn.Shared.TimeHelpers.now()})
             |> Repo.update(),
           :ok <- cancel_active_translation_run(archived) do
        {:ok, archived}
      end
    end
  end

  @doc """
  Sets a language as the source language for its project.
  Uses the same safety rules as `change_source_language/3`.
  """
  def set_source_language(%ProjectLanguage{} = language) do
    Project
    |> Repo.get!(language.project_id)
    |> change_source_language(language.locale_code)
  end

  @doc """
  Changes the project's source language to `locale_code`.

  If the locale already exists as a target language, it is promoted to source.
  Otherwise a new source language row is created. The previous source remains
  available as a target. Existing translations require an explicit reset.
  """
  def change_source_language(%Project{} = project, locale_code, opts \\ []) when is_binary(locale_code) do
    reset_translations? = Keyword.get(opts, :reset_translations, false)

    fn -> change_source_in_transaction(project.id, locale_code, reset_translations?) end
    |> Repo.transaction()
    |> case do
      {:ok, %ProjectLanguage{} = language} ->
        if reset_translations? do
          {:ok, _count} = LocalizableWords.extract_all(project.id)
          {:ok, language}
        else
          {:ok, language}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Reorders languages by setting their positions based on the provided list of IDs.
  """
  def reorder_languages(project_id, language_ids) when is_list(language_ids) do
    pairs = Enum.with_index(language_ids)

    Repo.transaction(fn ->
      TreeOperations.batch_set_positions("project_languages", pairs, scope: {"project_id", project_id})
    end)
  end

  @doc """
  Ensures a source language exists for the project.

  If no source language is configured, reads the workspace's `source_locale`
  and creates a ProjectLanguage with `is_source: true`.

  Returns `{:ok, source_language}` in all cases.
  """
  def ensure_source_language(%Project{} = project) do
    case get_source_language(project.id) do
      %ProjectLanguage{} = lang ->
        {:ok, lang}

      nil ->
        project = Repo.preload(project, :workspace)
        locale = project.workspace.source_locale || "en"
        name = Languages.name(locale)

        add_language(project, %{
          "locale_code" => locale,
          "name" => name,
          "is_source" => true
        })
    end
  end

  # =============================================================================
  # Import helpers (raw insert, no side effects)
  # =============================================================================

  @doc """
  Creates a language for import. Raw insert — no auto-position.
  Returns `{:ok, language}` or `{:error, changeset}`.
  """
  def import_language(project_id, attrs) do
    %ProjectLanguage{project_id: project_id}
    |> ProjectLanguage.create_changeset(attrs)
    |> Repo.insert()
  end

  # =============================================================================
  # Private
  # =============================================================================

  defp next_position(project_id) do
    from(l in ProjectLanguage,
      where: l.project_id == ^project_id,
      select: coalesce(max(l.position), -1)
    )
    |> Repo.one!()
    |> Kernel.+(1)
  end

  defp cancel_active_translation_run(language) do
    case TranslationRunCrud.get_active(language.project_id, language.locale_code) do
      nil -> :ok
      run -> run |> TranslationRunCrud.cancel() |> then(fn {:ok, _run} -> :ok end)
    end
  end

  defp current_source_or_rollback(project_id) do
    case get_source_language(project_id) do
      %ProjectLanguage{} = language -> language
      nil -> Repo.rollback(:no_source_language)
    end
  end

  defp change_source_in_transaction(project_id, locale_code, reset_translations?) do
    current_source = current_source_or_rollback(project_id)

    cond do
      current_source.locale_code == locale_code ->
        current_source

      translations_exist?(project_id) and not reset_translations? ->
        Repo.rollback(:translations_exist)

      true ->
        project_id
        |> find_or_create_source_candidate(locale_code)
        |> promote_source_language(project_id)
        |> maybe_reset_translations(project_id, reset_translations?)
    end
  end

  defp maybe_reset_translations(language, project_id, true) do
    reset_translations(project_id)
    language
  end

  defp maybe_reset_translations(language, _project_id, false), do: language

  defp find_or_create_source_candidate(project_id, locale_code) do
    case get_language_by_locale(project_id, locale_code) do
      %ProjectLanguage{} = language ->
        language

      nil ->
        case get_archived_language_by_locale(project_id, locale_code) do
          %ProjectLanguage{} = archived ->
            archived
            |> ProjectLanguage.update_changeset(%{"archived_at" => nil})
            |> Repo.update!()

          nil ->
            %ProjectLanguage{project_id: project_id}
            |> ProjectLanguage.create_changeset(%{
              "locale_code" => locale_code,
              "name" => Languages.name(locale_code),
              "is_source" => false,
              "position" => next_position(project_id)
            })
            |> Repo.insert!()
        end
    end
  end

  defp promote_source_language(next_source, project_id) do
    Repo.update_all(from(l in ProjectLanguage, where: l.project_id == ^project_id and l.is_source == true),
      set: [is_source: false]
    )

    case next_source
         |> ProjectLanguage.update_changeset(%{"is_source" => true, "archived_at" => nil})
         |> Repo.update() do
      {:ok, updated} -> updated
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp get_archived_language_by_locale(_project_id, nil), do: nil

  defp get_archived_language_by_locale(project_id, locale_code) do
    Repo.one(
      from(l in ProjectLanguage,
        where: l.project_id == ^project_id and l.locale_code == ^locale_code and not is_nil(l.archived_at)
      )
    )
  end

  defp translations_exist?(project_id) do
    Repo.exists?(from(t in LocalizedText, where: t.project_id == ^project_id))
  end

  defp reset_translations(project_id) do
    Repo.delete_all(from(t in LocalizedText, where: t.project_id == ^project_id))
  end
end

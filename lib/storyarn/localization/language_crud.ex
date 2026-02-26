defmodule Storyarn.Localization.LanguageCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Localization.Languages
  alias Storyarn.Localization.ProjectLanguage
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Shared.MapUtils

  # =============================================================================
  # Queries
  # =============================================================================

  def list_languages(project_id) do
    from(l in ProjectLanguage,
      where: l.project_id == ^project_id,
      order_by: [asc: l.position, asc: l.name]
    )
    |> Repo.all()
  end

  def get_language(project_id, language_id) do
    from(l in ProjectLanguage,
      where: l.project_id == ^project_id and l.id == ^language_id
    )
    |> Repo.one()
  end

  def get_language_by_locale(project_id, locale_code) do
    from(l in ProjectLanguage,
      where: l.project_id == ^project_id and l.locale_code == ^locale_code
    )
    |> Repo.one()
  end

  def get_source_language(project_id) do
    from(l in ProjectLanguage,
      where: l.project_id == ^project_id and l.is_source == true
    )
    |> Repo.one()
  end

  def get_target_languages(project_id) do
    from(l in ProjectLanguage,
      where: l.project_id == ^project_id and l.is_source == false,
      order_by: [asc: l.position, asc: l.name]
    )
    |> Repo.all()
  end

  # =============================================================================
  # Mutations
  # =============================================================================

  def add_language(%Project{} = project, attrs) do
    attrs = MapUtils.stringify_keys(attrs)
    position = attrs["position"] || next_position(project.id)

    %ProjectLanguage{project_id: project.id}
    |> ProjectLanguage.create_changeset(Map.put(attrs, "position", position))
    |> Repo.insert()
  end

  def update_language(%ProjectLanguage{} = language, attrs) do
    attrs = MapUtils.stringify_keys(attrs)

    language
    |> ProjectLanguage.update_changeset(attrs)
    |> Repo.update()
  end

  def remove_language(%ProjectLanguage{} = language) do
    Repo.delete(language)
  end

  @doc """
  Sets a language as the source language for its project.
  Unsets any existing source language first (within a transaction).
  """
  def set_source_language(%ProjectLanguage{} = language) do
    Repo.transaction(fn ->
      # Unset any existing source language
      from(l in ProjectLanguage,
        where: l.project_id == ^language.project_id and l.is_source == true
      )
      |> Repo.update_all(set: [is_source: false])

      # Set the new source language
      language
      |> ProjectLanguage.update_changeset(%{"is_source" => true})
      |> Repo.update!()
    end)
  end

  @doc """
  Reorders languages by setting their positions based on the provided list of IDs.
  """
  def reorder_languages(project_id, language_ids) when is_list(language_ids) do
    Repo.transaction(fn ->
      language_ids
      |> Enum.with_index()
      |> Enum.each(fn {id, index} ->
        from(l in ProjectLanguage,
          where: l.project_id == ^project_id and l.id == ^id
        )
        |> Repo.update_all(set: [position: index])
      end)
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
end

defmodule Storyarn.LocalizationFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Storyarn.Localization` context.
  """

  alias Storyarn.Localization
  alias Storyarn.ProjectsFixtures

  def valid_language_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      locale_code: "es",
      name: "Spanish"
    })
  end

  @doc """
  Creates a project language.
  """
  def language_fixture(project \\ nil, attrs \\ %{}) do
    project = project || ProjectsFixtures.project_fixture()

    {:ok, language} =
      attrs
      |> valid_language_attributes()
      |> then(&Localization.add_language(project, &1))

    language
  end

  @doc """
  Creates a source language for a project.
  """
  def source_language_fixture(project \\ nil, attrs \\ %{}) do
    project = project || ProjectsFixtures.project_fixture()

    attrs =
      attrs
      |> Enum.into(%{
        locale_code: "en",
        name: "English",
        is_source: true
      })

    {:ok, language} = Localization.add_language(project, attrs)
    language
  end

  @doc """
  Creates a localized text.
  """
  def localized_text_fixture(project_id, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        source_type: "flow_node",
        source_id: System.unique_integer([:positive]),
        source_field: "text",
        source_text: "Hello world",
        source_text_hash: :crypto.hash(:sha256, "Hello world") |> Base.encode16(case: :lower),
        locale_code: "es",
        word_count: 2
      })

    {:ok, text} = Localization.create_text(project_id, attrs)
    text
  end
end

defmodule Storyarn.LocalizationFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Storyarn.Localization` context.
  """

  alias Storyarn.Localization
  alias Storyarn.Localization.SourceContract
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

    attrs = Enum.into(attrs, %{locale_code: "en", name: "English", is_source: true})

    {:ok, language} = Localization.add_language(project, attrs)
    language
  end

  @doc """
  Creates a localized text.
  """
  def localized_text_fixture(project_id, attrs \\ %{}) do
    attrs =
      if Map.get(attrs, :source_type) == "block" and not Map.has_key?(attrs, :source_field) do
        Map.put(attrs, :source_field, "value.content")
      else
        attrs
      end

    attrs =
      Enum.into(attrs, %{
        source_type: "flow_node",
        source_id: System.unique_integer([:positive]),
        source_field: "text",
        source_text: "Hello world",
        source_text_hash: :sha256 |> :crypto.hash("Hello world") |> Base.encode16(case: :lower),
        locale_code: "es",
        word_count: 2
      })

    metadata = SourceContract.field_metadata(attrs.source_type, attrs.source_field)

    attrs =
      attrs
      |> Map.put_new(:content_role, metadata && metadata.content_role)
      |> Map.put_new(:vo_eligible, metadata && metadata.vo_eligible)

    attrs =
      if attrs[:status] == "final" do
        Map.put_new(attrs, :translated_text, attrs[:source_text] || "Translated text")
      else
        attrs
      end

    case Localization.get_text_by_source(
           attrs.source_type,
           attrs.source_id,
           attrs.source_field,
           attrs.locale_code
         ) do
      nil ->
        {:ok, text} = Localization.create_text(project_id, attrs)
        text

      _existing ->
        source_attrs =
          Map.take(attrs, [
            :source_type,
            :source_id,
            :source_field,
            :source_text,
            :source_text_hash,
            :locale_code,
            :word_count,
            :speaker_sheet_id,
            :content_role,
            :vo_eligible
          ])

        {:ok, refreshed} = Localization.upsert_text(project_id, source_attrs)
        {:ok, text} = Localization.update_text(refreshed, attrs)
        text
    end
  end
end

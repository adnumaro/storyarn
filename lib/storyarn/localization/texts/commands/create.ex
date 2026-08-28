defmodule Storyarn.Localization.Texts.Commands.Create do
  @moduledoc "Creates Texts inventory rows while deriving runtime metadata."

  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Localization.Texts.Commands.TranslationAttributes
  alias Storyarn.Platform.Kernel.MapAccess
  alias Storyarn.Repo

  def create_text(project_id, attrs) do
    attrs =
      attrs
      |> MapAccess.stringify_keys()
      |> TranslationAttributes.apply_source_metadata()
      |> TranslationAttributes.prepare_create_translation_attrs()

    %LocalizedText{project_id: project_id}
    |> LocalizedText.create_changeset(attrs)
    |> Repo.insert()
  end
end

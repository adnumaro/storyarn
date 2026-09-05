defmodule StoryarnWeb.FlowLive.Helpers.DialogueLocalizationTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Localization
  alias StoryarnWeb.FlowLive.Helpers.DialogueLocalization
  alias StoryarnWeb.PrivateMedia

  setup do
    user = user_fixture()
    project = project_fixture(user)
    source_language_fixture(project, %{locale_code: "en", name: "English"})
    language_fixture(project, %{locale_code: "es", name: "Spanish"})
    speaker = sheet_fixture(project, %{name: "Aria Vale"})
    flow = flow_fixture(project)

    node =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{
          "text" => "Hello {{ hero.name }}",
          "stage_directions" => "She enters.",
          "menu_text" => "Greet Aria",
          "speaker_sheet_id" => speaker.id,
          "responses" => [%{"id" => "answer-1", "text" => "Welcome"}]
        }
      })

    %{user: user, project: project, speaker: speaker, node: node}
  end

  test "source locale uses original narrative, speaker, responses, and node voice", context do
    asset = audio_asset_fixture(context.project, context.user)
    node = %{context.node | data: Map.put(context.node.data, "audio_asset_id", asset.id)}

    result = resolve(node, context, "en")

    assert result.content.text == "Hello {{ hero.name }}"
    assert result.content.stage_directions == "She enters."
    assert result.content.response_texts == %{"answer-1" => "Welcome"}
    assert result.content.speaker_name == "Aria Vale"

    assert result.localization == %{
             locale: "en",
             sourceLocale: "en",
             isSource: true,
             status: "source",
             stale: false,
             fallback: false,
             fields: result.localization.fields
           }

    assert result.voice.status == "recorded"
    assert result.voice.available
    assert result.voice.url == PrivateMedia.asset_url(asset)
  end

  test "target locale uses current translations for narrative, responses, and speaker", context do
    current_translation(context.project.id, context.node.id, "text", "Hello {{ hero.name }}", "Hola {{ hero.name }}")

    current_translation(
      context.project.id,
      context.node.id,
      "stage_directions",
      "She enters.",
      "Ella entra."
    )

    current_translation(
      context.project.id,
      context.node.id,
      "response.answer-1.text",
      "Welcome",
      "Bienvenida"
    )

    current_translation(context.project.id, context.speaker.id, "name", "Aria Vale", "Aria del Valle", "sheet")

    result = resolve(context.node, context, "es")

    assert result.content.text == "Hola {{ hero.name }}"
    assert result.content.stage_directions == "Ella entra."
    assert result.content.response_texts["answer-1"] == "Bienvenida"
    assert result.content.speaker_name == "Aria del Valle"
    assert result.localization.status == "draft"
    refute result.localization.stale
    assert result.localization.fields.speakerName.fallback == false
  end

  test "missing target text explicitly falls back without borrowing source voice", context do
    source_asset = audio_asset_fixture(context.project, context.user)
    node = %{context.node | data: Map.put(context.node.data, "audio_asset_id", source_asset.id)}

    result = resolve(node, context, "es")

    assert result.content.text == "Hello {{ hero.name }}"
    assert result.localization.fallback
    assert result.localization.fields.text == %{status: "pending", stale: false, fallback: true}
    assert result.voice.status == "none"
    refute result.voice.available
    assert is_nil(result.voice.url)
  end

  test "stale target text remains visible and makes recorded target voice unavailable", context do
    asset = audio_asset_fixture(context.project, context.user)

    row =
      localized_text_fixture(context.project.id, %{
        source_id: context.node.id,
        source_field: "text",
        source_text: "Hello {{ hero.name }}",
        source_text_hash: hash("old source"),
        translated_text: "Hola, {{ hero.name }}",
        status: "review"
      })

    {:ok, row} = Localization.update_text(row, %{vo_status: "recorded", vo_asset_id: asset.id})
    row = Repo.update!(change(row, source_text_hash: hash("new source")))
    assert row.vo_status == "recorded"
    result = resolve(context.node, context, "es")

    assert result.content.text == "Hola, {{ hero.name }}"
    assert result.localization.stale
    assert result.localization.fields.text.stale
    assert result.voice.status == "recorded"
    assert result.voice.stale
    refute result.voice.available
    assert is_nil(result.voice.url)
  end

  test "target VO exposes none, needed, recorded, and approved without implicit fallback", context do
    asset = audio_asset_fixture(context.project, context.user)

    row =
      current_translation(
        context.project.id,
        context.node.id,
        "text",
        "Hello {{ hero.name }}",
        "Hola {{ hero.name }}"
      )

    none = resolve(context.node, context, "es").voice
    assert %{status: "none", available: false, url: nil} = none

    {:ok, row} = Localization.update_text(row, %{vo_status: "needed"})
    needed = resolve(context.node, context, "es").voice
    assert %{status: "needed", available: false, url: nil} = needed

    {:ok, row} = Localization.update_text(row, %{vo_status: "recorded", vo_asset_id: asset.id})
    recorded = resolve(context.node, context, "es").voice
    assert recorded.status == "recorded"
    assert recorded.available
    assert recorded.url == PrivateMedia.asset_url(asset)

    {:ok, _row} = Localization.update_text(row, %{vo_status: "approved"})
    approved = resolve(context.node, context, "es").voice
    assert approved.status == "approved"
    assert approved.available
    assert approved.url == PrivateMedia.asset_url(asset)
  end

  defp resolve(node, context, locale) do
    DialogueLocalization.resolve(
      node,
      %{to_string(context.speaker.id) => %{name: context.speaker.name}},
      context.project.id,
      "en",
      locale
    )
  end

  defp current_translation(project_id, source_id, field, source, translated, source_type \\ "flow_node") do
    source_hash = hash(source)

    localized_text_fixture(project_id, %{
      source_type: source_type,
      source_id: source_id,
      source_field: field,
      source_text: source,
      source_text_hash: source_hash,
      translated_source_hash: source_hash,
      translated_text: translated,
      status: "draft"
    })
  end

  defp hash(value), do: :sha256 |> :crypto.hash(value) |> Base.encode16(case: :lower)
end

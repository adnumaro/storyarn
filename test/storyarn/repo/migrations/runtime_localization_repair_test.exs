Code.require_file(
  Path.expand(
    "../../../../priv/repo/migration_helpers/runtime_localization_repair.exs",
    __DIR__
  )
)

defmodule Storyarn.Repo.Migrations.RuntimeLocalizationRepairTest do
  use Storyarn.DataCase, async: false

  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Repo.Migrations.RuntimeLocalizationRepair

  test "preserves valid runtime IDs and avoids IDs reserved by references" do
    project = project_fixture()
    flow = flow_fixture(project)
    dialogue = node_fixture(flow)
    preserved_dialogue = node_fixture(flow)
    target = node_fixture(flow, %{type: "hub", data: %{}})

    dialogue_collision = dialogue_id(dialogue.id, 0)
    dialogue_rekey = dialogue_id(dialogue.id, 1)
    response_collision = response_id(dialogue.id, 1, 0)
    pin_reservation = response_id(dialogue.id, 1, 1)
    localized_text_reservation = response_id(dialogue.id, 1, 2)
    response_rekey = response_id(dialogue.id, 1, 3)
    direct_resp_rekey = response_id(dialogue.id, 4, 0)

    update_node_data(preserved_dialogue.id, %{
      "localization_id" => dialogue_collision,
      "responses" => []
    })

    update_node_data(dialogue.id, %{
      "localization_id" => "legacy.dialogue",
      "responses" => [
        %{"id" => "legacy.response", "text" => "Legacy"},
        %{"id" => response_collision, "text" => "Preserved"},
        "malformed response",
        %{"id" => "resp_bad.choice", "text" => "Direct resp prefix"},
        %{"id" => "bad.choice", "text" => "Prefixed resp pin"}
      ]
    })

    old_connection =
      connection_fixture(flow, dialogue, target, %{source_pin: "legacy.response"})

    _reserved_connection =
      connection_fixture(flow, dialogue, target, %{source_pin: pin_reservation})

    ambiguous_connection =
      connection_fixture(flow, dialogue, target, %{source_pin: "resp_bad.choice"})

    _reserved_text =
      localized_text_fixture(project.id, %{
        source_id: dialogue.id,
        source_field: "response.#{localized_text_reservation}.text"
      })

    legacy_text =
      localized_text_fixture(project.id, %{
        source_id: dialogue.id,
        source_field: "response.temporary.text"
      })

    drop_runtime_source_constraints()

    Repo.query!(
      "UPDATE localized_texts SET source_field = 'response.legacy.response.text' WHERE id = $1",
      [legacy_text.id]
    )

    run_runtime_id_repair()

    assert get_in(node_data(preserved_dialogue.id), ["localization_id"]) == dialogue_collision
    assert get_in(node_data(dialogue.id), ["localization_id"]) == dialogue_rekey

    responses = node_data(dialogue.id)["responses"]

    assert Enum.at(responses, 0)["id"] == response_rekey
    assert Enum.at(responses, 1)["id"] == response_collision
    assert Enum.at(responses, 2) == "malformed response"
    assert Enum.at(responses, 3)["id"] == direct_resp_rekey

    assert connection_pin(old_connection.id) == response_rekey
    assert connection_pin(ambiguous_connection.id) == direct_resp_rekey
    assert localized_source_field(legacy_text.id) == "response.#{response_rekey}.text"
  end

  test "consolidates locale case variants before lowercasing unique keys" do
    project = project_fixture()

    target_language =
      language_fixture(project, %{locale_code: "en-us", name: "English target"})

    source_language =
      source_language_fixture(project, %{locale_code: "fr", name: "English source"})

    pending_text =
      localized_text_fixture(project.id, %{
        source_id: System.unique_integer([:positive]),
        locale_code: "en-us",
        status: "pending"
      })

    final_text =
      localized_text_fixture(project.id, %{
        source_id: pending_text.source_id,
        locale_code: "fr",
        status: "final",
        translated_text: "Final translation"
      })

    drop_locale_constraints()

    Repo.query!("UPDATE project_languages SET locale_code = 'EN-US' WHERE id = $1", [
      source_language.id
    ])

    Repo.query!("UPDATE localized_texts SET locale_code = 'EN-US' WHERE id = $1", [final_text.id])

    execute_sql(RuntimeLocalizationRepair.lock_sql())
    Enum.each(RuntimeLocalizationRepair.locale_sql(), &execute_sql/1)

    assert [[source_language_id, "en-us", true]] =
             rows("""
             SELECT id, locale_code, is_source
             FROM project_languages
             WHERE project_id = #{project.id}
             """)

    assert source_language_id == source_language.id
    refute Repo.get(Storyarn.Localization.ProjectLanguage, target_language.id)

    assert [[final_text_id, "en-us", "final"]] =
             rows("""
             SELECT id, locale_code, status
             FROM localized_texts
             WHERE source_type = 'flow_node'
               AND source_id = #{pending_text.source_id}
               AND source_field = 'text'
             """)

    assert final_text_id == final_text.id
  end

  defp run_runtime_id_repair do
    execute_sql(RuntimeLocalizationRepair.lock_sql())
    Enum.each(RuntimeLocalizationRepair.runtime_id_sql(), &execute_sql/1)
  end

  defp execute_sql(sql), do: Repo.query!(sql)

  defp rows(sql), do: sql |> Repo.query!() |> Map.fetch!(:rows)

  defp update_node_data(node_id, data) do
    Repo.query!("UPDATE flow_nodes SET data = $1::jsonb WHERE id = $2", [
      data,
      node_id
    ])
  end

  defp node_data(node_id) do
    [[data]] = rows("SELECT data FROM flow_nodes WHERE id = #{node_id}")
    data
  end

  defp connection_pin(connection_id) do
    [[source_pin]] =
      rows("SELECT source_pin FROM flow_connections WHERE id = #{connection_id}")

    source_pin
  end

  defp localized_source_field(localized_text_id) do
    [[source_field]] =
      rows("SELECT source_field FROM localized_texts WHERE id = #{localized_text_id}")

    source_field
  end

  defp drop_runtime_source_constraints do
    Repo.query!("ALTER TABLE localized_texts DROP CONSTRAINT localized_texts_source_field_runtime")

    Repo.query!("ALTER TABLE localized_texts DROP CONSTRAINT localized_texts_source_metadata_runtime")
  end

  defp drop_locale_constraints do
    Repo.query!("ALTER TABLE localized_texts DROP CONSTRAINT localized_texts_locale_code_safe")

    Repo.query!("ALTER TABLE project_languages DROP CONSTRAINT project_languages_locale_code_safe")
  end

  defp dialogue_id(node_id, attempt) do
    seed = "legacy:#{node_id}" <> attempt_suffix(attempt)
    "dialogue_" <> md5(seed)
  end

  defp response_id(node_id, ordinality, attempt) do
    seed = "legacy:#{node_id}:#{ordinality}" <> attempt_suffix(attempt)
    "response_" <> md5(seed)
  end

  defp attempt_suffix(0), do: ""
  defp attempt_suffix(attempt), do: ":#{attempt}"

  defp md5(value) do
    :md5
    |> :crypto.hash(value)
    |> Base.encode16(case: :lower)
  end
end

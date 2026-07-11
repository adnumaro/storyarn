defmodule Storyarn.Localization.GlossarySyncTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Localization

  setup do
    Req.Test.verify_on_exit!()

    Application.put_env(:storyarn, :deepl_req_options,
      plug: {Req.Test, __MODULE__},
      retry: false
    )

    on_exit(fn -> Application.delete_env(:storyarn, :deepl_req_options) end)

    project = project_fixture(user_fixture())

    {:ok, _config} =
      Localization.upsert_provider_config(project, %{
        "api_key_encrypted" => "secret",
        "api_endpoint" => "https://api-free.deepl.com",
        "is_active" => true
      })

    %{project: project}
  end

  test "creates and tracks a v3 glossary for a language pair", %{project: project} do
    {:ok, _entry} =
      Localization.create_glossary_entry(project, %{
        source_term: "Eldoria",
        source_locale: "en",
        target_term: "",
        target_locale: "es",
        do_not_translate: true
      })

    Req.Test.expect(__MODULE__, fn conn ->
      {body, conn} = read_json(conn)
      assert conn.request_path == "/v3/glossaries"
      assert get_in(body, ["dictionaries", Access.at(0), "entries"]) == "Eldoria\tEldoria"

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{glossary_id: "glossary-1"})
    end)

    refute Localization.glossary_synced?(project.id, "en", "es")
    assert {:ok, config} = Localization.sync_deepl_glossary(project.id, "en", "es")
    assert config.deepl_glossary_ids["EN-ES"] == "glossary-1"
    assert Localization.glossary_synced?(project.id, "en", "es")
  end

  test "marks edited terms dirty and replaces the remote glossary", %{project: project} do
    {:ok, entry} =
      Localization.create_glossary_entry(project, %{
        source_term: "sword",
        source_locale: "en",
        target_term: "espada",
        target_locale: "es"
      })

    expect_create("glossary-1")
    assert {:ok, _config} = Localization.sync_deepl_glossary(project.id, "en", "es")
    assert {:ok, _entry} = Localization.update_glossary_entry(entry, %{target_term: "hoja"})
    refute Localization.glossary_synced?(project.id, "en", "es")

    expect_create("glossary-2")

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "DELETE"
      assert conn.request_path == "/v3/glossaries/glossary-1"
      Plug.Conn.send_resp(conn, 204, "")
    end)

    assert {:ok, config} = Localization.sync_deepl_glossary(project.id, "en", "es")
    assert config.deepl_glossary_ids["EN-ES"] == "glossary-2"
    assert Localization.glossary_synced?(project.id, "en", "es")
  end

  test "removes the remote glossary when the local pair becomes empty", %{project: project} do
    {:ok, entry} =
      Localization.create_glossary_entry(project, %{
        source_term: "sword",
        source_locale: "en",
        target_term: "espada",
        target_locale: "es"
      })

    expect_create("glossary-1")
    assert {:ok, _config} = Localization.sync_deepl_glossary(project.id, "en", "es")
    assert {:ok, _entry} = Localization.delete_glossary_entry(entry)

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.request_path == "/v3/glossaries/glossary-1"
      Plug.Conn.send_resp(conn, 204, "")
    end)

    assert {:ok, config} = Localization.sync_deepl_glossary(project.id, "en", "es")
    refute Map.has_key?(config.deepl_glossary_ids, "EN-ES")
    assert Localization.glossary_synced?(project.id, "en", "es")
  end

  test "retains the remote glossary id when deletion fails so cleanup can be retried", %{
    project: project
  } do
    {:ok, entry} =
      Localization.create_glossary_entry(project, %{
        source_term: "sword",
        source_locale: "en",
        target_term: "espada",
        target_locale: "es"
      })

    expect_create("glossary-1")
    assert {:ok, _config} = Localization.sync_deepl_glossary(project.id, "en", "es")
    assert {:ok, _entry} = Localization.delete_glossary_entry(entry)

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "DELETE"
      assert conn.request_path == "/v3/glossaries/glossary-1"
      conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{message: "temporary failure"})
    end)

    assert {:error, {:api_error, 500, _body}} =
             Localization.sync_deepl_glossary(project.id, "en", "es")

    config = Localization.get_provider_config(project.id)
    assert config.deepl_glossary_ids["EN-ES"] == "glossary-1"

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "DELETE"
      assert conn.request_path == "/v3/glossaries/glossary-1"
      Plug.Conn.send_resp(conn, 204, "")
    end)

    assert {:ok, config} = Localization.sync_deepl_glossary(project.id, "en", "es")
    refute Map.has_key?(config.deepl_glossary_ids, "EN-ES")
  end

  defp expect_create(glossary_id) do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/v3/glossaries"

      {body, conn} = read_json(conn)
      assert [%{"entries" => entries, "entries_format" => "tsv"}] = body["dictionaries"]
      assert is_binary(entries)

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{glossary_id: glossary_id})
    end)
  end

  defp read_json(conn) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    {Jason.decode!(body), conn}
  end
end

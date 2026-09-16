defmodule StoryarnWeb.StaticSeoResourcesTest do
  use StoryarnWeb.ConnCase, async: true

  test "every icon and manifest advertised by the public page is served", %{conn: conn} do
    resources =
      conn
      |> get("/")
      |> html_response(200)
      |> LazyHTML.from_document()
      |> LazyHTML.query(~s(link[rel="icon"], link[rel="apple-touch-icon"], link[rel="manifest"]))
      |> LazyHTML.attribute("href")

    assert length(resources) >= 4

    for path <- resources do
      resource_conn = get(conn, path)

      assert resource_conn.status == 200, "Public metadata points to unavailable resource #{path}"
      assert response(resource_conn, 200) != ""
      refute get_resp_header(resource_conn, "content-type") == ["text/html; charset=utf-8"]
    end
  end

  test "manifest launches an existing page and its icons match their advertised sizes", %{conn: conn} do
    manifest_conn = get(conn, "/site.webmanifest")
    manifest = manifest_conn |> response(200) |> Jason.decode!()

    assert [content_type] = get_resp_header(manifest_conn, "content-type")
    assert content_type =~ "application/manifest+json"
    assert conn |> get(manifest["start_url"]) |> html_response(200)
    assert [_ | _] = manifest["icons"]

    for icon <- manifest["icons"] do
      icon_conn = get(conn, icon["src"])
      body = response(icon_conn, 200)

      assert get_resp_header(icon_conn, "content-type") == [icon["type"]]

      assert <<137, "PNG\r\n", 26, "\n", _length::32, "IHDR", width::32, height::32, _::binary>> =
               body

      assert icon["sizes"] == "#{width}x#{height}",
             "Manifest icon #{icon["src"]} has dimensions #{width}x#{height}"
    end
  end

  test "serves fingerprinted root resources advertised by production HTML", %{conn: conn} do
    for filename <- ~w(favicon.ico site.webmanifest) do
      body = File.read!(Application.app_dir(:storyarn, "priv/static/#{filename}"))
      extension = Path.extname(filename)
      basename = Path.rootname(filename)
      digest = :md5 |> :crypto.hash(body) |> Base.encode16(case: :lower)
      digested_filename = "#{basename}-#{digest}#{extension}"
      path = Application.app_dir(:storyarn, "priv/static/#{digested_filename}")

      case File.write(path, body, [:exclusive]) do
        :ok -> on_exit(fn -> File.rm!(path) end)
        {:error, :eexist} -> assert File.read!(path) == body
      end

      resource_conn = get(conn, "/#{digested_filename}?vsn=d")

      assert response(resource_conn, 200) == body
      assert [cache_control] = get_resp_header(resource_conn, "cache-control")
      assert cache_control =~ "max-age=31536000"
      assert get_resp_header(resource_conn, "content-type") == [MIME.from_path(filename)]
    end
  end
end

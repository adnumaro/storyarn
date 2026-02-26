defmodule StoryarnWeb.Plugs.LocaleTest do
  use StoryarnWeb.ConnCase, async: true

  alias StoryarnWeb.Plugs.Locale

  describe "init/1" do
    test "passes options through" do
      assert Locale.init([]) == []
      assert Locale.init(foo: :bar) == [foo: :bar]
    end
  end

  describe "call/2" do
    test "defaults to 'en' when no locale hints are present" do
      conn =
        build_conn(:get, "/")
        |> init_test_session(%{})
        |> fetch_query_params()
        |> Locale.call([])

      assert conn.assigns.locale == "en"
      assert get_session(conn, :locale) == "en"
    end

    test "uses locale from URL params" do
      conn =
        build_conn(:get, "/?locale=es")
        |> init_test_session(%{})
        |> fetch_query_params()
        |> Locale.call([])

      assert conn.assigns.locale == "es"
      assert get_session(conn, :locale) == "es"
    end

    test "ignores invalid locale from URL params" do
      conn =
        build_conn(:get, "/?locale=xx")
        |> init_test_session(%{})
        |> fetch_query_params()
        |> Locale.call([])

      assert conn.assigns.locale == "en"
    end

    test "uses locale from session" do
      conn =
        build_conn(:get, "/")
        |> init_test_session(%{locale: "es"})
        |> fetch_query_params()
        |> Locale.call([])

      assert conn.assigns.locale == "es"
    end

    test "URL params take precedence over session" do
      conn =
        build_conn(:get, "/?locale=en")
        |> init_test_session(%{locale: "es"})
        |> fetch_query_params()
        |> Locale.call([])

      assert conn.assigns.locale == "en"
    end

    test "uses locale from Accept-Language header" do
      conn =
        build_conn(:get, "/")
        |> init_test_session(%{})
        |> fetch_query_params()
        |> put_req_header("accept-language", "es-MX,es;q=0.9,en;q=0.8")
        |> Locale.call([])

      assert conn.assigns.locale == "es"
    end

    test "handles Accept-Language with just language code" do
      conn =
        build_conn(:get, "/")
        |> init_test_session(%{})
        |> fetch_query_params()
        |> put_req_header("accept-language", "en")
        |> Locale.call([])

      assert conn.assigns.locale == "en"
    end

    test "falls back to default with unsupported Accept-Language" do
      conn =
        build_conn(:get, "/")
        |> init_test_session(%{})
        |> fetch_query_params()
        |> put_req_header("accept-language", "fr-FR,fr;q=0.9")
        |> Locale.call([])

      assert conn.assigns.locale == "en"
    end

    test "session takes precedence over Accept-Language" do
      conn =
        build_conn(:get, "/")
        |> init_test_session(%{locale: "es"})
        |> fetch_query_params()
        |> put_req_header("accept-language", "en-US")
        |> Locale.call([])

      assert conn.assigns.locale == "es"
    end

    test "stores locale in session for subsequent requests" do
      conn =
        build_conn(:get, "/?locale=es")
        |> init_test_session(%{})
        |> fetch_query_params()
        |> Locale.call([])

      assert get_session(conn, :locale) == "es"
    end

    test "ignores invalid session locale and falls back" do
      conn =
        build_conn(:get, "/")
        |> init_test_session(%{locale: "invalid"})
        |> fetch_query_params()
        |> Locale.call([])

      assert conn.assigns.locale == "en"
    end

    test "handles Accept-Language with uppercase" do
      conn =
        build_conn(:get, "/")
        |> init_test_session(%{})
        |> fetch_query_params()
        |> put_req_header("accept-language", "ES-AR")
        |> Locale.call([])

      assert conn.assigns.locale == "es"
    end
  end
end

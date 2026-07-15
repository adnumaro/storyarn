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
        :get
        |> build_conn("/")
        |> init_test_session(%{})
        |> fetch_query_params()
        |> Locale.call([])

      assert conn.assigns.locale == "en"
    end

    test "uses locale from URL params" do
      conn =
        :get
        |> build_conn("/users/log-in?locale=es")
        |> init_test_session(%{})
        |> fetch_query_params()
        |> Locale.call([])

      assert conn.assigns.locale == "es"
      assert get_session(conn, :locale) == "es"
    end

    test "ignores invalid locale from URL params" do
      conn =
        :get
        |> build_conn("/users/log-in?locale=xx")
        |> init_test_session(%{})
        |> fetch_query_params()
        |> Locale.call([])

      assert conn.assigns.locale == "en"
    end

    test "uses locale from session" do
      conn =
        :get
        |> build_conn("/users/log-in")
        |> init_test_session(%{locale: "es"})
        |> fetch_query_params()
        |> Locale.call([])

      assert conn.assigns.locale == "es"
    end

    test "URL params take precedence over session" do
      conn =
        :get
        |> build_conn("/users/log-in?locale=en")
        |> init_test_session(%{locale: "es"})
        |> fetch_query_params()
        |> Locale.call([])

      assert conn.assigns.locale == "en"
    end

    test "uses locale from Accept-Language header" do
      conn =
        :get
        |> build_conn("/users/log-in")
        |> init_test_session(%{})
        |> fetch_query_params()
        |> put_req_header("accept-language", "es-MX,es;q=0.9,en;q=0.8")
        |> Locale.call([])

      assert conn.assigns.locale == "es"
    end

    test "uses the first supported alternative instead of only inspecting the first range" do
      conn =
        :get
        |> build_conn("/users/log-in")
        |> init_test_session(%{})
        |> fetch_query_params()
        |> put_req_header("accept-language", "fr-FR, es-ES;q=0.9, en;q=0.8")
        |> Locale.call([])

      assert conn.assigns.locale == "es"
    end

    test "orders language ranges by quality value" do
      conn =
        :get
        |> build_conn("/users/log-in")
        |> init_test_session(%{})
        |> fetch_query_params()
        |> put_req_header("accept-language", "en;q=0.2, es;q=0.9")
        |> Locale.call([])

      assert conn.assigns.locale == "es"
    end

    test "ignores language ranges with a zero quality value" do
      conn =
        :get
        |> build_conn("/users/log-in")
        |> init_test_session(%{})
        |> fetch_query_params()
        |> put_req_header("accept-language", "es;q=0, fr;q=1")
        |> Locale.call([])

      assert conn.assigns.locale == "en"
    end

    test "ignores malformed quality values and continues with valid alternatives" do
      conn =
        :get
        |> build_conn("/users/log-in")
        |> init_test_session(%{})
        |> fetch_query_params()
        |> put_req_header("accept-language", "es;q=invalid, en;q=0.8")
        |> Locale.call([])

      assert conn.assigns.locale == "en"
    end

    test "normalizes language range case and underscore separators" do
      conn =
        :get
        |> build_conn("/users/log-in")
        |> init_test_session(%{})
        |> fetch_query_params()
        |> put_req_header("accept-language", "ES_mx")
        |> Locale.call([])

      assert conn.assigns.locale == "es"
    end

    test "handles Accept-Language with just language code" do
      conn =
        :get
        |> build_conn("/users/log-in")
        |> init_test_session(%{})
        |> fetch_query_params()
        |> put_req_header("accept-language", "en")
        |> Locale.call([])

      assert conn.assigns.locale == "en"
    end

    test "falls back to default with unsupported Accept-Language" do
      conn =
        :get
        |> build_conn("/users/log-in")
        |> init_test_session(%{})
        |> fetch_query_params()
        |> put_req_header("accept-language", "fr-FR,fr;q=0.9")
        |> Locale.call([])

      assert conn.assigns.locale == "en"
    end

    test "session takes precedence over Accept-Language" do
      conn =
        :get
        |> build_conn("/users/log-in")
        |> init_test_session(%{locale: "es"})
        |> fetch_query_params()
        |> put_req_header("accept-language", "en-US")
        |> Locale.call([])

      assert conn.assigns.locale == "es"
    end

    test "stores locale in session for subsequent requests" do
      conn =
        :get
        |> build_conn("/users/log-in?locale=es")
        |> init_test_session(%{})
        |> fetch_query_params()
        |> Locale.call([])

      assert get_session(conn, :locale) == "es"
    end

    test "ignores invalid session locale and falls back" do
      conn =
        :get
        |> build_conn("/users/log-in")
        |> init_test_session(%{locale: "invalid"})
        |> fetch_query_params()
        |> Locale.call([])

      assert conn.assigns.locale == "en"
    end

    test "handles Accept-Language with uppercase" do
      conn =
        :get
        |> build_conn("/users/log-in")
        |> init_test_session(%{})
        |> fetch_query_params()
        |> put_req_header("accept-language", "ES-AR")
        |> Locale.call([])

      assert conn.assigns.locale == "es"
    end

    test "a localized blog path controls the response without replacing the site preference" do
      conn =
        :get
        |> build_conn("/es/blog")
        |> init_test_session(%{locale: "en"})
        |> fetch_query_params()
        |> Locale.call([])

      assert conn.assigns.locale == "es"
      assert get_session(conn, :locale) == "en"
    end

    test "the canonical English blog path does not replace a Spanish site preference" do
      conn =
        :get
        |> build_conn("/blog")
        |> init_test_session(%{locale: "es"})
        |> fetch_query_params()
        |> Locale.call([])

      assert conn.assigns.locale == "en"
      assert get_session(conn, :locale) == "es"
    end

    test "a fresh localized blog request still stores the detected site preference" do
      conn =
        :get
        |> build_conn("/es/blog")
        |> init_test_session(%{})
        |> fetch_query_params()
        |> put_req_header("accept-language", "en-US")
        |> Locale.call([])

      assert conn.assigns.locale == "es"
      assert get_session(conn, :locale) == "en"
    end

    test "all locale-prefixed public surfaces control the response locale" do
      for path <- [
            "/es",
            "/es/contact",
            "/es/privacy",
            "/es/terms",
            "/es/docs/welcome/start-here",
            "/es/blog/presentamos-storyarn"
          ] do
        conn =
          :get
          |> build_conn(path)
          |> init_test_session(%{locale: "en"})
          |> fetch_query_params()
          |> Locale.call([])

        assert conn.assigns.locale == "es"
        assert get_session(conn, :locale) == "en"
      end
    end

    test "unprefixed public surfaces remain English despite a Spanish preference" do
      for path <- ["/", "/contact", "/privacy", "/terms", "/docs", "/blog"] do
        conn =
          :get
          |> build_conn(path)
          |> init_test_session(%{locale: "es"})
          |> fetch_query_params()
          |> Locale.call([])

        assert conn.assigns.locale == "en"
        assert get_session(conn, :locale) == "es"
      end
    end
  end
end

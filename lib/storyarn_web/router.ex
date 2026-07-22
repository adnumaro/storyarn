defmodule StoryarnWeb.Router do
  use StoryarnWeb, :router

  alias Storyarn.Publication.Locales

  # Content Security Policy
  @csp_dev_extras if(Mix.env() == :dev,
                    do: " http://localhost:5173 'unsafe-inline' 'unsafe-eval'",
                    else: ""
                  )
  @csp_dev_asset_origin if(Mix.env() == :dev, do: " http://localhost:5173", else: "")

  @posthog_default_connect_src "https://*.posthog.com https://*.i.posthog.com " <>
                                 "https://us.i.posthog.com https://eu.i.posthog.com"

  defp csp_policy do
    "default-src 'self'; " <>
      "script-src 'self'#{@csp_dev_extras}; " <>
      "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com#{@csp_dev_extras}; " <>
      "img-src 'self' data: blob: https:#{@csp_dev_asset_origin}; " <>
      "media-src 'self' blob: https:; " <>
      "font-src 'self' data: https://fonts.gstatic.com#{@csp_dev_extras}; " <>
      "connect-src 'self' ws: wss: #{posthog_connect_src()}#{@csp_dev_extras}; " <>
      "frame-src 'self'; " <>
      "frame-ancestors 'self'; " <>
      "base-uri 'self'; " <>
      "form-action 'self'"
  end

  @user_auth_hook Module.concat(["StoryarnWeb", "UserAuth"])
  @default_public_locale Locales.default_locale()
  @default_public_segment Locales.path_segment(@default_public_locale)
  @localized_public_routes Locales.localized_routes()

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :ensure_login_handoff_nonce
    plug :fetch_live_flash
    plug :put_root_layout, html: {StoryarnWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :put_content_security_policy
    plug :fetch_current_scope_for_user
    plug :put_posthog_user_context
    plug StoryarnWeb.Plugs.Locale
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  defp put_content_security_policy(conn, _opts) do
    Plug.Conn.put_resp_header(conn, "content-security-policy", csp_policy())
  end

  defp ensure_login_handoff_nonce(conn, _opts) do
    case Plug.Conn.get_session(conn, :login_handoff_nonce) do
      nonce when is_binary(nonce) and nonce != "" ->
        conn

      _other ->
        Plug.Conn.put_session(
          conn,
          :login_handoff_nonce,
          Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
        )
    end
  end

  defp put_posthog_user_context(%{assigns: %{current_scope: %{user: %{id: user_id}}}} = conn, _opts) do
    PostHog.set_context(%{distinct_id: "user:#{user_id}"})
    conn
  end

  defp put_posthog_user_context(conn, _opts), do: conn

  defp posthog_connect_src do
    posthog_host =
      :posthog
      |> Application.get_env(:api_host)
      |> csp_origin()

    [@posthog_default_connect_src, posthog_host]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp csp_origin(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host, port: port} when scheme in ["http", "https"] and is_binary(host) ->
        port_suffix = csp_port_suffix(scheme, port)
        "#{scheme}://#{host}#{port_suffix}"

      _ ->
        nil
    end
  end

  defp csp_origin(_url), do: nil

  defp csp_port_suffix("http", 80), do: ""
  defp csp_port_suffix("https", 443), do: ""
  defp csp_port_suffix(_scheme, nil), do: ""
  defp csp_port_suffix(_scheme, port), do: ":#{port}"

  scope "/", StoryarnWeb do
    get "/llms.txt", LlmsController, :index
    get "/sitemap.xml", SitemapController, :index
  end

  # Other scopes may use custom stacks.
  # scope "/api", StoryarnWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:storyarn, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: StoryarnWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", StoryarnWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/media/assets/:id", PrivateMediaController, :asset
    get "/media/projects/:project_id/files/:encoded_key", PrivateMediaController, :project_file
    get "/media/workspaces/:workspace_slug/banner", PrivateMediaController, :workspace_banner
  end

  scope "/", StoryarnWeb do
    pipe_through [:browser, :require_authenticated_user]

    post "/workspaces/:workspace_slug/projects/:project_slug/upload",
         UploadController,
         :create

    post "/workspaces/:workspace_slug/projects/:project_slug/upload/inspect",
         UploadController,
         :inspect_upload

    post "/workspaces/:workspace_slug/projects/:project_slug/upload/materialize",
         UploadController,
         :materialize

    get "/workspaces/:workspace_slug/projects/:project_slug/localization/export/:format/:locale",
        LocalizationExportController,
        :export

    get "/workspaces/:workspace_slug/projects/:project_slug/export/:format",
        ExportController,
        :export

    get "/workspaces/:workspace_slug/projects/:project_slug/snapshots/:id/download",
        SnapshotDownloadController,
        :download

    # Authenticated app shell. Workspace dashboards, project tools, and
    # settings intentionally share one LiveView session so navigation between
    # those areas does not fall back to a full document reload.
    live_session :authenticated_app,
      on_mount:
        if(Application.compile_env(:storyarn, :sql_sandbox),
          do: [Module.concat(["StoryarnWeb", "LiveSandbox"])],
          else: []
        ) ++
          [
            {@user_auth_hook, :require_authenticated},
            {@user_auth_hook, :load_workspaces},
            {StoryarnWeb.Live.Hooks.Onboarding, :load_onboarding},
            {StoryarnWeb.Live.Hooks.Palette, :setup_palette},
            {StoryarnWeb.Live.Hooks.ProjectScope, :load_project},
            {StoryarnWeb.Live.Hooks.WorkspaceScope, :load_workspace}
          ] do
      # User Settings (Linear-style)
      live "/users/settings", SettingsLive.Profile, :edit
      live "/users/settings/security", SettingsLive.Security, :edit
      live "/users/settings/tutorials", SettingsLive.Tutorials, :edit
      live "/users/settings/integrations", SettingsLive.Integrations, :edit
      live "/users/settings/confirm-email/:token", SettingsLive.Profile, :confirm_email

      # Sudo re-authentication belongs to the authenticated app session so
      # settings can navigate to it without a document reload.
      live "/users/confirm-access", UserLive.ConfirmAccess, :new

      # Workspaces
      live "/workspaces", WorkspaceLive.Index, :index
      live "/workspaces/new", WorkspaceLive.New, :new
      live "/workspaces/:workspace_slug", WorkspaceLive.Show, :show

      # Project templates
      live "/templates", TemplateLive.Index, :index
      live "/templates/:id", TemplateLive.Show, :show

      live "/workspaces/:workspace_slug/projects/:project_slug/sheets/:id/compare/:version_number",
           CompareLive.Sheet,
           :compare

      live "/workspaces/:workspace_slug/projects/:project_slug/sheets/:id/versions/:version_number/viewer",
           VersionViewerLive,
           :sheet

      # Flows — immersive player and compare views keep their own chromeless
      # layouts, while sharing the authenticated app live_session for fast nav.
      live "/workspaces/:workspace_slug/projects/:project_slug/flows/:id/play",
           FlowLive.PlayerLive,
           :play

      live "/workspaces/:workspace_slug/projects/:project_slug/flows/:id/compare/:version_number",
           CompareLive.Flow,
           :compare

      live "/workspaces/:workspace_slug/projects/:project_slug/flows/:id/versions/:version_number/viewer",
           VersionViewerLive,
           :flow

      # Scenes — immersive exploration keeps its chromeless layout while
      # sharing the authenticated app live_session for fast nav.
      live "/workspaces/:workspace_slug/projects/:project_slug/scenes/:id/explore",
           SceneLive.ExplorationLive,
           :explore

      live "/workspaces/:workspace_slug/projects/:project_slug/scenes/:id/compare/:version_number",
           CompareLive.Scene,
           :compare

      live "/workspaces/:workspace_slug/projects/:project_slug/scenes/:id/versions/:version_number/viewer",
           VersionViewerLive,
           :scene

      live "/workspaces/:workspace_slug/projects/:project_slug/sheets",
           SheetLive.Index,
           :index

      live "/workspaces/:workspace_slug/projects/:project_slug/sheets/:id",
           SheetLive.Show,
           :show

      live "/workspaces/:workspace_slug/projects/:project_slug/sheets/:id/edit",
           SheetLive.Show,
           :edit

      # Localization — Report is the tool "dashboard" (default landing);
      # Index shows the text list filtered by locale; Edit is a single text.
      live "/workspaces/:workspace_slug/projects/:project_slug/localization",
           LocalizationLive.Report,
           :show

      live "/workspaces/:workspace_slug/projects/:project_slug/localization/texts/:locale",
           LocalizationLive.Index,
           :index

      live "/workspaces/:workspace_slug/projects/:project_slug/localization/texts/:locale/:id",
           LocalizationLive.Index,
           :edit

      live "/workspaces/:workspace_slug/projects/:project_slug/localization/glossary/:locale",
           LocalizationLive.Glossary,
           :index

      live "/workspaces/:workspace_slug/projects/:project_slug/localization/text/:id",
           LocalizationLive.Edit,
           :edit

      # Project dashboard
      live "/workspaces/:workspace_slug/projects/:project_slug", ProjectLive.Show, :show

      # Assets
      live "/workspaces/:workspace_slug/projects/:project_slug/assets",
           AssetLive.Index,
           :index

      # Project Settings (uses SettingsLayout, not project chrome — keeps the
      # full-page settings sidebar nav while sharing project scope assigns.)
      live "/workspaces/:workspace_slug/projects/:project_slug/settings",
           ProjectSettingsLive.General,
           :edit

      live "/workspaces/:workspace_slug/projects/:project_slug/settings/localization",
           ProjectSettingsLive.Localization,
           :edit

      live "/workspaces/:workspace_slug/projects/:project_slug/settings/members",
           ProjectSettingsLive.Members,
           :edit

      live "/workspaces/:workspace_slug/projects/:project_slug/settings/snapshots",
           ProjectSettingsLive.Snapshots,
           :edit

      live "/workspaces/:workspace_slug/projects/:project_slug/settings/version-control",
           ProjectSettingsLive.VersionControl,
           :edit

      live "/workspaces/:workspace_slug/projects/:project_slug/settings/usage-limits",
           ProjectSettingsLive.UsageLimits,
           :show

      live "/workspaces/:workspace_slug/projects/:project_slug/settings/export-import",
           ExportImportLive.Index,
           :index

      live "/workspaces/:workspace_slug/projects/:project_slug/settings/trash",
           ProjectSettingsLive.Trash,
           :index

      # Scenes
      live "/workspaces/:workspace_slug/projects/:project_slug/scenes", SceneLive.Index, :index
      live "/workspaces/:workspace_slug/projects/:project_slug/scenes/:id", SceneLive.Show, :show

      # Flows
      live "/workspaces/:workspace_slug/projects/:project_slug/flows", FlowLive.Index, :index
      live "/workspaces/:workspace_slug/projects/:project_slug/flows/:id", FlowLive.Show, :show

      live "/users/settings/workspaces/:slug/general", SettingsLive.WorkspaceGeneral, :edit
      live "/users/settings/workspaces/:slug/members", SettingsLive.WorkspaceMembers, :edit

      live "/users/settings/workspaces/:slug/deleted-projects",
           SettingsLive.WorkspaceDeletedProjects,
           :index
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", StoryarnWeb do
    pipe_through [:browser]

    get "/blog/test-branching-dialogue-before-export", BlogRedirectController, :legacy_post
    get "/blog/why-we-are-building-storyarn", BlogRedirectController, :legacy_post

    # The default locale is canonical without a prefix. These explicit aliases
    # preserve old or manually-entered `/en/...` links without exposing a
    # catch-all locale route that could shadow authentication or invitations.
    get "/#{@default_public_segment}", PublicLocaleRedirectController, :default_locale
    get "/#{@default_public_segment}/contact", PublicLocaleRedirectController, :default_locale
    get "/#{@default_public_segment}/privacy", PublicLocaleRedirectController, :default_locale
    get "/#{@default_public_segment}/terms", PublicLocaleRedirectController, :default_locale
    get "/#{@default_public_segment}/docs", PublicLocaleRedirectController, :default_locale

    get "/#{@default_public_segment}/docs/:category/*path",
        PublicLocaleRedirectController,
        :default_locale

    get "/#{@default_public_segment}/blog", PublicLocaleRedirectController, :default_locale

    get "/#{@default_public_segment}/blog/:slug",
        PublicLocaleRedirectController,
        :default_locale

    live_session :current_user,
      session: {StoryarnWeb.PublicLocale, :session, []},
      on_mount:
        if(Application.compile_env(:storyarn, :sql_sandbox),
          do: [Module.concat(["StoryarnWeb", "LiveSandbox"])],
          else: []
        ) ++
          [
            {@user_auth_hook, :mount_current_scope},
            {StoryarnWeb.PublicLocale, :set_locale},
            {@user_auth_hook, :load_workspaces}
          ] do
      live "/", LandingLive.Index, :index, private: %{public_locale: @default_public_locale}

      live "/contact", LandingLive.Contact, :show, private: %{public_locale: @default_public_locale}

      live "/blog", BlogLive.Index, :index, private: %{public_locale: @default_public_locale}

      live "/blog/:slug", BlogLive.Show, :show, private: %{public_locale: @default_public_locale}

      live "/privacy", LegalLive.Show, :privacy, private: %{public_locale: @default_public_locale}

      live "/terms", LegalLive.Show, :terms, private: %{public_locale: @default_public_locale}

      # Public documentation works with or without authentication and shares
      # the landing live_session so navigation does not require a full reload.
      live "/docs", DocsLive.Show, :index, private: %{public_locale: @default_public_locale}

      live "/docs/:category/*path", DocsLive.Show, :show, private: %{public_locale: @default_public_locale}

      # Locale-prefixed public pages belong to this existing session because
      # they work with or without authentication and must retain LiveView
      # navigation plus the current_scope assign. Do not create another
      # `:current_user` live_session.
      for {locale, path_segment} <- @localized_public_routes do
        live "/#{path_segment}", LandingLive.Index, :index, private: %{public_locale: locale}

        live "/#{path_segment}/contact", LandingLive.Contact, :show, private: %{public_locale: locale}

        live "/#{path_segment}/blog", BlogLive.Index, :index, private: %{public_locale: locale}

        live "/#{path_segment}/blog/:slug", BlogLive.Show, :show, private: %{public_locale: locale}

        live "/#{path_segment}/privacy", LegalLive.Show, :privacy, private: %{public_locale: locale}

        live "/#{path_segment}/terms", LegalLive.Show, :terms, private: %{public_locale: locale}

        live "/#{path_segment}/docs", DocsLive.Show, :index, private: %{public_locale: locale}

        live "/#{path_segment}/docs/:category/*path", DocsLive.Show, :show, private: %{public_locale: locale}
      end

      # Project invitations (accessible with or without auth)
      live "/projects/invitations/:token", ProjectLive.Invitation, :show

      # Workspace invitations (accessible with or without auth)
      live "/workspaces/invitations/:token", WorkspaceLive.Invitation, :show

      # Public-only authentication pages share this live_session with the
      # landing page so LiveView can navigate without a full page reload. Each
      # auth LiveView redirects signed-in users with its own on_mount hook.
      live "/users/register", UserLive.Registration, :new
      live "/users/register/:token", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/reset-password", UserLive.ForgotPassword, :new
      live "/users/reset-password/:token", UserLive.ResetPassword, :edit
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end

  defp fetch_current_scope_for_user(conn, opts) do
    StoryarnWeb.UserAuth.fetch_current_scope_for_user(conn, opts)
  end

  defp require_authenticated_user(conn, opts) do
    StoryarnWeb.UserAuth.require_authenticated_user(conn, opts)
  end
end

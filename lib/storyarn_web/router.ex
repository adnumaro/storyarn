defmodule StoryarnWeb.Router do
  use StoryarnWeb, :router

  # Content Security Policy
  @csp_dev_extras if(Mix.env() == :dev,
                    do: " http://localhost:5173 'unsafe-inline' 'unsafe-eval'",
                    else: ""
                  )

  @csp_policy "default-src 'self'; " <>
                "script-src 'self'#{@csp_dev_extras}; " <>
                "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com#{@csp_dev_extras}; " <>
                "img-src 'self' data: blob: https:; " <>
                "font-src 'self' data: https://fonts.gstatic.com#{@csp_dev_extras}; " <>
                "connect-src 'self' ws: wss: https://*.ingest.sentry.io https://*.ingest.us.sentry.io#{@csp_dev_extras}; " <>
                "frame-src 'self'; " <>
                "frame-ancestors 'self'; " <>
                "base-uri 'self'; " <>
                "form-action 'self'"

  @user_auth_hook Module.concat(["StoryarnWeb", "UserAuth"])

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {StoryarnWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers, %{"content-security-policy" => @csp_policy}
    plug :fetch_current_scope_for_user
    plug StoryarnWeb.Plugs.Locale
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :sudo_return_to do
    plug :store_sudo_return_to
  end

  scope "/", StoryarnWeb do
    pipe_through :browser

    get "/contact", PageController, :contact
    post "/waitlist", PageController, :join_waitlist
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

  ## Documentation (public, isolated context)

  scope "/docs", StoryarnWeb do
    pipe_through [:browser]

    live_session :docs,
      on_mount:
        if(Application.compile_env(:storyarn, :sql_sandbox),
          do: [Module.concat(["StoryarnWeb", "LiveSandbox"])],
          else: []
        ) ++
          [
            Sentry.LiveViewHook,
            {@user_auth_hook, :mount_current_scope}
          ] do
      live "/", DocsLive.Show, :index
      live "/:category/:slug", DocsLive.Show, :show
    end
  end

  ## OAuth routes

  scope "/auth", StoryarnWeb do
    pipe_through :browser

    get "/:provider", OAuthController, :request
    get "/:provider/callback", OAuthController, :callback
  end

  scope "/auth", StoryarnWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/:provider/link", OAuthController, :request
    get "/:provider/link/callback", OAuthController, :link
    delete "/:provider/unlink", OAuthController, :unlink
  end

  ## Authentication routes

  scope "/", StoryarnWeb do
    pipe_through [:browser, :require_authenticated_user, :sudo_return_to]

    post "/workspaces/:workspace_slug/projects/:project_slug/upload",
         UploadController,
         :create

    get "/workspaces/:workspace_slug/projects/:project_slug/localization/export/:format/:locale",
        LocalizationExportController,
        :export

    get "/workspaces/:workspace_slug/projects/:project_slug/export/:format",
        ExportController,
        :export

    get "/workspaces/:workspace_slug/projects/:project_slug/snapshots/:id/download",
        SnapshotDownloadController,
        :download

    live_session :require_authenticated_user,
      on_mount:
        if(Application.compile_env(:storyarn, :sql_sandbox),
          do: [Module.concat(["StoryarnWeb", "LiveSandbox"])],
          else: []
        ) ++
          [
            Sentry.LiveViewHook,
            {@user_auth_hook, :require_authenticated},
            {@user_auth_hook, :load_workspaces}
          ] do
      # User Settings (Linear-style)
      live "/users/settings", SettingsLive.Profile, :edit
      live "/users/settings/security", SettingsLive.Security, :edit
      live "/users/settings/connections", SettingsLive.Connections, :edit
      live "/users/settings/confirm-email/:token", SettingsLive.Profile, :confirm_email

      # Workspaces
      live "/workspaces", WorkspaceLive.Index, :index
      live "/workspaces/new", WorkspaceLive.New, :new
      live "/workspaces/:workspace_slug", WorkspaceLive.Show, :show

      live "/workspaces/:workspace_slug/projects/:project_slug/sheets/:id/compare/:version_number",
           CompareLive.Sheet,
           :compare

      # Trash
      live "/workspaces/:workspace_slug/projects/:project_slug/trash",
           ProjectLive.Trash,
           :index

      # Flows (visual narrative editor)
      live "/workspaces/:workspace_slug/projects/:project_slug/flows", FlowLive.Index, :index
      live "/workspaces/:workspace_slug/projects/:project_slug/flows/:id", FlowLive.Show, :show

      live "/workspaces/:workspace_slug/projects/:project_slug/flows/:id/play",
           FlowLive.PlayerLive,
           :play

      live "/workspaces/:workspace_slug/projects/:project_slug/flows/:id/compare/:version_number",
           CompareLive.Flow,
           :compare

      # Scenes — immersive exploration stays outside :project_scope (no chrome).
      live "/workspaces/:workspace_slug/projects/:project_slug/scenes/:id/explore",
           SceneLive.ExplorationLive,
           :explore

      live "/workspaces/:workspace_slug/projects/:project_slug/scenes/:id/compare/:version_number",
           CompareLive.Scene,
           :compare

      # TODO: version snapshot viewer needs Vue migration
    end

    # Project-scoped live_session — loads project/workspace/membership once via
    # ProjectScope on_mount. Routes inside share a live_session so sticky
    # live_renders (toolbars + sidebar in ProjectShell) persist across navigation.
    live_session :project_scope,
      on_mount:
        if(Application.compile_env(:storyarn, :sql_sandbox),
          do: [Module.concat(["StoryarnWeb", "LiveSandbox"])],
          else: []
        ) ++
          [
            Sentry.LiveViewHook,
            {@user_auth_hook, :require_authenticated},
            {@user_auth_hook, :load_workspaces},
            {StoryarnWeb.Live.Hooks.ProjectScope, :load_project}
          ] do
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

      live "/workspaces/:workspace_slug/projects/:project_slug/localization/text/:id",
           LocalizationLive.Edit,
           :edit

      # Project dashboard
      live "/workspaces/:workspace_slug/projects/:project_slug", ProjectLive.Show, :show

      # Assets
      live "/workspaces/:workspace_slug/projects/:project_slug/assets",
           AssetLive.Index,
           :index

      # Project Settings (uses Layouts.settings, not ProjectShell — keeps the
      # full-page settings sidebar nav. Inside :project_scope only to share the
      # ProjectScope on_mount hook for project/workspace/membership loading.)
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

      live "/workspaces/:workspace_slug/projects/:project_slug/settings/export-import",
           ExportImportLive.Index,
           :index

      # Scenes
      live "/workspaces/:workspace_slug/projects/:project_slug/scenes", SceneLive.Index, :index
      live "/workspaces/:workspace_slug/projects/:project_slug/scenes/:id", SceneLive.Show, :show
    end

    # Workspace-scoped live_session — loads workspace/membership once via
    # WorkspaceScope on_mount. Used by the 3 workspace settings LVs that
    # otherwise duplicated `Workspaces.get_workspace_by_slug` in mount.
    live_session :workspace_scope,
      on_mount:
        if(Application.compile_env(:storyarn, :sql_sandbox),
          do: [Module.concat(["StoryarnWeb", "LiveSandbox"])],
          else: []
        ) ++
          [
            Sentry.LiveViewHook,
            {@user_auth_hook, :require_authenticated},
            {@user_auth_hook, :load_workspaces},
            {StoryarnWeb.Live.Hooks.WorkspaceScope, :load_workspace}
          ] do
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

    live_session :current_user,
      on_mount:
        if(Application.compile_env(:storyarn, :sql_sandbox),
          do: [Module.concat(["StoryarnWeb", "LiveSandbox"])],
          else: []
        ) ++
          [
            Sentry.LiveViewHook,
            {@user_auth_hook, :mount_current_scope},
            {@user_auth_hook, :load_workspaces}
          ] do
      live "/", LandingLive.Index, :index
      live "/users/register/:token", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/confirm-access", UserLive.ConfirmAccess, :new

      # Project invitations (accessible with or without auth)
      live "/projects/invitations/:token", ProjectLive.Invitation, :show

      # Workspace invitations (accessible with or without auth)
      live "/workspaces/invitations/:token", WorkspaceLive.Invitation, :show
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end

  defp fetch_current_scope_for_user(conn, opts) do
    StoryarnWeb.UserAuth.fetch_current_scope_for_user(conn, opts)
  end

  defp store_sudo_return_to(conn, opts) do
    StoryarnWeb.UserAuth.store_sudo_return_to(conn, opts)
  end

  defp require_authenticated_user(conn, opts) do
    StoryarnWeb.UserAuth.require_authenticated_user(conn, opts)
  end
end

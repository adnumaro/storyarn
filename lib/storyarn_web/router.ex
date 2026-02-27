defmodule StoryarnWeb.Router do
  use StoryarnWeb, :router

  import StoryarnWeb.UserAuth

  # Content Security Policy
  # Uses hash for the minimal inline theme script to avoid FOUC
  # 'unsafe-inline' kept for styles (Tailwind dynamic classes)
  @csp_theme_hash "sha256-7iNU1myL14qKRh0R+cX+kTMGRQbzBP60jwUPVTiyh0U="
  @csp_policy "default-src 'self'; " <>
                "script-src 'self' '#{@csp_theme_hash}'; " <>
                "style-src 'self' 'unsafe-inline'; " <>
                "img-src 'self' data: blob: https:; " <>
                "font-src 'self' data:; " <>
                "connect-src 'self' ws: wss:; " <>
                "frame-ancestors 'self'; " <>
                "base-uri 'self'; " <>
                "form-action 'self'"

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

  scope "/", StoryarnWeb do
    pipe_through :browser

    get "/", PageController, :home
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
    pipe_through [:browser, :require_authenticated_user]

    get "/workspaces/:workspace_slug/projects/:project_slug/screenplays/:id/export/fountain",
        ScreenplayExportController,
        :fountain

    get "/workspaces/:workspace_slug/projects/:project_slug/localization/export/:format/:locale",
        LocalizationExportController,
        :export

    get "/workspaces/:workspace_slug/projects/:project_slug/export/:format",
        ExportController,
        :export

    live_session :require_authenticated_user,
      on_mount:
        if(Application.compile_env(:storyarn, :sql_sandbox),
          do: [StoryarnWeb.LiveSandbox],
          else: []
        ) ++
          [
            {StoryarnWeb.UserAuth, :require_authenticated},
            {StoryarnWeb.UserAuth, :load_workspaces}
          ] do
      # User Settings (Linear-style)
      live "/users/settings", SettingsLive.Profile, :edit
      live "/users/settings/security", SettingsLive.Security, :edit
      live "/users/settings/connections", SettingsLive.Connections, :edit
      live "/users/settings/confirm-email/:token", SettingsLive.Profile, :confirm_email

      # Workspace Settings (in unified settings)
      live "/users/settings/workspaces/:slug/general", SettingsLive.WorkspaceGeneral, :edit
      live "/users/settings/workspaces/:slug/members", SettingsLive.WorkspaceMembers, :edit

      # Workspaces
      live "/workspaces", WorkspaceLive.Index, :index
      live "/workspaces/new", WorkspaceLive.New, :new
      live "/workspaces/:workspace_slug", WorkspaceLive.Show, :show
      live "/workspaces/:workspace_slug/projects/new", WorkspaceLive.Show, :new_project

      # Projects (nested under workspaces)
      live "/workspaces/:workspace_slug/projects/:project_slug", ProjectLive.Show, :show

      live "/workspaces/:workspace_slug/projects/:project_slug/settings",
           ProjectLive.Settings,
           :edit

      # Export & Import
      live "/workspaces/:workspace_slug/projects/:project_slug/export-import",
           ExportImportLive.Index,
           :index

      # Sheets (character sheets, location sheets, etc.)
      live "/workspaces/:workspace_slug/projects/:project_slug/sheets", SheetLive.Index, :index
      live "/workspaces/:workspace_slug/projects/:project_slug/sheets/:id", SheetLive.Show, :show

      live "/workspaces/:workspace_slug/projects/:project_slug/sheets/:id/edit",
           SheetLive.Show,
           :edit

      # Localization
      live "/workspaces/:workspace_slug/projects/:project_slug/localization",
           LocalizationLive.Index,
           :index

      live "/workspaces/:workspace_slug/projects/:project_slug/localization/report",
           LocalizationLive.Report,
           :report

      live "/workspaces/:workspace_slug/projects/:project_slug/localization/:id",
           LocalizationLive.Edit,
           :edit

      # Assets
      live "/workspaces/:workspace_slug/projects/:project_slug/assets",
           AssetLive.Index,
           :index

      # Trash
      live "/workspaces/:workspace_slug/projects/:project_slug/trash",
           ProjectLive.Trash,
           :index

      # Flows (visual narrative editor)
      live "/workspaces/:workspace_slug/projects/:project_slug/flows", FlowLive.Index, :index
      live "/workspaces/:workspace_slug/projects/:project_slug/flows/new", FlowLive.Index, :new
      live "/workspaces/:workspace_slug/projects/:project_slug/flows/:id", FlowLive.Show, :show

      live "/workspaces/:workspace_slug/projects/:project_slug/flows/:id/play",
           FlowLive.PlayerLive,
           :play

      # Scenes (world builder)
      live "/workspaces/:workspace_slug/projects/:project_slug/scenes", SceneLive.Index, :index
      live "/workspaces/:workspace_slug/projects/:project_slug/scenes/new", SceneLive.Index, :new
      live "/workspaces/:workspace_slug/projects/:project_slug/scenes/:id", SceneLive.Show, :show

      live "/workspaces/:workspace_slug/projects/:project_slug/scenes/:id/explore",
           SceneLive.ExplorationLive,
           :explore

      # Screenplays (block-based screenplay editor)
      live "/workspaces/:workspace_slug/projects/:project_slug/screenplays",
           ScreenplayLive.Index,
           :index

      live "/workspaces/:workspace_slug/projects/:project_slug/screenplays/new",
           ScreenplayLive.Index,
           :new

      live "/workspaces/:workspace_slug/projects/:project_slug/screenplays/:id",
           ScreenplayLive.Show,
           :show
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", StoryarnWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount:
        if(Application.compile_env(:storyarn, :sql_sandbox),
          do: [StoryarnWeb.LiveSandbox],
          else: []
        ) ++
          [
            {StoryarnWeb.UserAuth, :mount_current_scope},
            {StoryarnWeb.UserAuth, :load_workspaces}
          ] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new

      # Project invitations (accessible with or without auth)
      live "/projects/invitations/:token", ProjectLive.Invitation, :show

      # Workspace invitations (accessible with or without auth)
      live "/workspaces/invitations/:token", WorkspaceLive.Invitation, :show
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end

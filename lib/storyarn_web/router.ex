defmodule StoryarnWeb.Router do
  use StoryarnWeb, :router

  import StoryarnWeb.UserAuth

  # Content Security Policy - adjust as needed for external resources
  @csp_policy "default-src 'self'; " <>
                "script-src 'self' 'unsafe-inline' 'unsafe-eval'; " <>
                "style-src 'self' 'unsafe-inline'; " <>
                "img-src 'self' data: blob:; " <>
                "font-src 'self' data:; " <>
                "connect-src 'self' ws: wss:; " <>
                "frame-ancestors 'self'"

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

    live_session :require_authenticated_user,
      on_mount: [{StoryarnWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email

      # Projects
      live "/projects", ProjectLive.Dashboard, :index
      live "/projects/new", ProjectLive.Dashboard, :new
      live "/projects/:id", ProjectLive.Show, :show
      live "/projects/:id/settings", ProjectLive.Settings, :edit

      # Entities
      live "/projects/:project_id/entities", EntityLive.Index, :index
      live "/projects/:project_id/entities/new", EntityLive.Index, :new
      live "/projects/:project_id/entities/:id", EntityLive.Show, :show
      live "/projects/:project_id/entities/:id/edit", EntityLive.Show, :edit

      # Templates
      live "/projects/:project_id/templates", TemplateLive.Index, :index
      live "/projects/:project_id/templates/new", TemplateLive.Index, :new
      live "/projects/:project_id/templates/:id/edit", TemplateLive.Index, :edit
      live "/projects/:project_id/templates/:id/schema", TemplateLive.Index, :schema

      # Variables
      live "/projects/:project_id/variables", VariableLive.Index, :index
      live "/projects/:project_id/variables/new", VariableLive.Index, :new
      live "/projects/:project_id/variables/:id/edit", VariableLive.Index, :edit
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", StoryarnWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{StoryarnWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new

      # Project invitations (accessible with or without auth)
      live "/projects/invitations/:token", ProjectLive.Invitation, :show
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end

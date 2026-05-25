defmodule FoyerWeb.Router do
  use FoyerWeb, :router

  import FoyerWeb.UserAuth, only: [fetch_current_user: 2]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FoyerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", FoyerWeb do
    pipe_through :browser

    # POC user picker — unauthenticated landing.
    live_session :public,
      on_mount: [{FoyerWeb.UserAuth, :mount_public}] do
      live "/", UserPickerLive, :index
    end

    # Authenticated but off-shift allowed: Today only.
    live_session :authenticated_today,
      on_mount: [{FoyerWeb.UserAuth, :ensure_authenticated}] do
      live "/today", TodayLive, :index
      live "/today/end-shift", TodayLive, :end_shift
    end

    # Authenticated AND on shift. Off-shift users are redirected to /today.
    live_session :authenticated_on_shift,
      on_mount: [{FoyerWeb.UserAuth, :ensure_on_shift}] do
      live "/house", HouseLive, :index

      live "/announcements/new", AnnouncementLive, :new
      live "/announcements/:id", AnnouncementLive, :show
      live "/announcements/:id/edit", AnnouncementLive, :edit

      live "/chat", ChatLive, :inbox
      live "/chat/new", ChatLive, :new_message
      live "/chat/:conversation_id", ChatLive, :show

      live "/recognitions", RecognitionsLive, :index
      live "/recognitions/new", RecognitionsLive, :new
      live "/recognitions/:id", RecognitionsLive, :show
      live "/recognitions/:id/edit", RecognitionsLive, :edit

      live "/me", ProfileLive, :me
      live "/people", PeopleLive, :index
      live "/people/:id", PeopleLive, :show
    end

    # POC session helpers — controllers, not LiveViews, because they mutate
    # the session and then redirect.
    post "/session/pick/:user_id", SessionController, :pick
    delete "/session", SessionController, :sign_out
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:foyer, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: FoyerWeb.Telemetry
    end
  end
end

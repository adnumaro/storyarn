defmodule StoryarnWeb.Components.UIComponents do
  @moduledoc """
  Custom UI components for the Storyarn application.

  These components extend the base Phoenix CoreComponents with
  project-specific UI elements like role badges, OAuth buttons,
  empty states, and more.
  """
  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  alias Phoenix.LiveView.JS

  import StoryarnWeb.Components.CoreComponents, only: [icon: 1]

  @doc """
  Renders a role badge.

  ## Examples

      <.role_badge role="owner" />
      <.role_badge role="editor" />
      <.role_badge role="viewer" />
      <.role_badge role="admin" />
      <.role_badge role="member" />
  """
  attr :role, :string, required: true

  def role_badge(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm",
      @role == "owner" && "badge-primary",
      @role == "admin" && "badge-secondary",
      @role == "editor" && "badge-secondary",
      @role == "member" && "badge-accent",
      @role == "viewer" && "badge-ghost"
    ]}>
      {@role}
    </span>
    """
  end

  @doc """
  Renders OAuth provider login buttons.

  ## Examples

      <.oauth_buttons />
      <.oauth_buttons action="link" />
  """
  attr :action, :string, default: "login", values: ~w(login link)
  attr :class, :string, default: nil

  def oauth_buttons(assigns) do
    ~H"""
    <div class={["flex flex-col gap-2", @class]}>
      <.link
        href={if @action == "link", do: "/auth/github/link", else: "/auth/github"}
        class="btn btn-outline gap-2"
      >
        <svg class="size-5" viewBox="0 0 24 24" fill="currentColor">
          <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z" />
        </svg>
        {gettext("Continue with GitHub")}
      </.link>
      <.link
        href={if @action == "link", do: "/auth/google/link", else: "/auth/google"}
        class="btn btn-outline gap-2"
      >
        <svg class="size-5" viewBox="0 0 24 24">
          <path
            fill="#4285F4"
            d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
          />
          <path
            fill="#34A853"
            d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
          />
          <path
            fill="#FBBC05"
            d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"
          />
          <path
            fill="#EA4335"
            d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"
          />
        </svg>
        {gettext("Continue with Google")}
      </.link>
      <.link
        href={if @action == "link", do: "/auth/discord/link", else: "/auth/discord"}
        class="btn btn-outline gap-2"
      >
        <svg class="size-5" viewBox="0 0 24 24" fill="#5865F2">
          <path d="M20.317 4.3698a19.7913 19.7913 0 00-4.8851-1.5152.0741.0741 0 00-.0785.0371c-.211.3753-.4447.8648-.6083 1.2495-1.8447-.2762-3.68-.2762-5.4868 0-.1636-.3933-.4058-.8742-.6177-1.2495a.077.077 0 00-.0785-.037 19.7363 19.7363 0 00-4.8852 1.515.0699.0699 0 00-.0321.0277C.5334 9.0458-.319 13.5799.0992 18.0578a.0824.0824 0 00.0312.0561c2.0528 1.5076 4.0413 2.4228 5.9929 3.0294a.0777.0777 0 00.0842-.0276c.4616-.6304.8731-1.2952 1.226-1.9942a.076.076 0 00-.0416-.1057c-.6528-.2476-1.2743-.5495-1.8722-.8923a.077.077 0 01-.0076-.1277c.1258-.0943.2517-.1923.3718-.2914a.0743.0743 0 01.0776-.0105c3.9278 1.7933 8.18 1.7933 12.0614 0a.0739.0739 0 01.0785.0095c.1202.099.246.1981.3728.2924a.077.077 0 01-.0066.1276 12.2986 12.2986 0 01-1.873.8914.0766.0766 0 00-.0407.1067c.3604.698.7719 1.3628 1.225 1.9932a.076.076 0 00.0842.0286c1.961-.6067 3.9495-1.5219 6.0023-3.0294a.077.077 0 00.0313-.0552c.5004-5.177-.8382-9.6739-3.5485-13.6604a.061.061 0 00-.0312-.0286zM8.02 15.3312c-1.1825 0-2.1569-1.0857-2.1569-2.419 0-1.3332.9555-2.4189 2.157-2.4189 1.2108 0 2.1757 1.0952 2.1568 2.419 0 1.3332-.9555 2.4189-2.1569 2.4189zm7.9748 0c-1.1825 0-2.1569-1.0857-2.1569-2.419 0-1.3332.9554-2.4189 2.1569-2.4189 1.2108 0 2.1757 1.0952 2.1568 2.419 0 1.3332-.946 2.4189-2.1568 2.4189Z" />
        </svg>
        {gettext("Continue with Discord")}
      </.link>
    </div>
    """
  end

  @doc """
  Renders a keyboard shortcut badge.

  ## Examples

      <.kbd>E</.kbd>
      <.kbd size="sm">Ctrl+S</.kbd>
  """
  attr :size, :string, default: "xs", values: ~w(xs sm md)
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def kbd(assigns) do
    ~H"""
    <kbd class={["kbd", "kbd-#{@size}", @class]}>
      {render_slot(@inner_block)}
    </kbd>
    """
  end

  @doc """
  Renders an empty state placeholder with icon and message.

  ## Examples

      <.empty_state icon="folder-open">
        No projects yet
      </.empty_state>

      <.empty_state icon="file-text" title="No documents">
        Create your first document to get started
      </.empty_state>
  """
  attr :icon, :string, required: true
  attr :title, :string, default: nil
  attr :class, :string, default: nil
  slot :inner_block
  slot :action

  def empty_state(assigns) do
    ~H"""
    <div class={["text-center py-12", @class]}>
      <.icon name={@icon} class="size-12 mx-auto mb-4 text-base-content/30" />
      <p :if={@title} class="font-medium text-base-content/70">{@title}</p>
      <p :if={@inner_block != []} class="text-sm text-base-content/50 mt-1">
        {render_slot(@inner_block)}
      </p>
      <div :if={@action != []} class="mt-4">
        {render_slot(@action)}
      </div>
    </div>
    """
  end

  @doc """
  Renders a search input with magnifying glass icon.

  ## Examples

      <.search_input placeholder="Search projects..." phx-change="search" />
      <.search_input value={@query} name="q" size="sm" />
  """
  attr :size, :string, default: "sm", values: ~w(xs sm md lg)
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(name value placeholder phx-change phx-debounce disabled form)

  def search_input(assigns) do
    ~H"""
    <label class={["input input-bordered input-#{@size} flex items-center gap-2", @class]}>
      <.icon name="search" class="size-4 opacity-50" />
      <input type="text" class="grow" {@rest} />
    </label>
    """
  end

  @doc """
  Renders a group of overlapping avatars.

  ## Examples

      <.avatar_group>
        <:avatar src="/images/user1.jpg" alt="User 1" />
        <:avatar src="/images/user2.jpg" alt="User 2" />
        <:avatar fallback="JD" />
      </.avatar_group>

      <.avatar_group size="sm" max={3} total={5} />
  """
  attr :size, :string, default: "sm", values: ~w(xs sm md lg)
  attr :max, :integer, default: 4, doc: "Maximum avatars to show before +N"
  attr :total, :integer, default: nil, doc: "Total count for +N indicator (if greater than slots)"
  attr :class, :string, default: nil

  slot :avatar do
    attr :src, :string
    attr :alt, :string
    attr :fallback, :string
  end

  def avatar_group(assigns) do
    size_classes = %{
      "xs" => "w-6",
      "sm" => "w-8",
      "md" => "w-10",
      "lg" => "w-12"
    }

    assigns = assign(assigns, :size_class, size_classes[assigns.size])

    visible_avatars = Enum.take(assigns.avatar, assigns.max)
    remaining = max((assigns.total || length(assigns.avatar)) - assigns.max, 0)

    assigns =
      assigns
      |> assign(:visible_avatars, visible_avatars)
      |> assign(:remaining, remaining)

    ~H"""
    <div class={["avatar-group -space-x-3 rtl:space-x-reverse", @class]}>
      <div :for={av <- @visible_avatars} class="avatar">
        <div class={["rounded-full", @size_class]}>
          <img :if={av[:src]} src={av[:src]} alt={av[:alt] || ""} />
          <div
            :if={!av[:src] && av[:fallback]}
            class="bg-neutral text-neutral-content flex items-center justify-center w-full h-full"
          >
            <span class="text-xs">{av[:fallback]}</span>
          </div>
        </div>
      </div>
      <div :if={@remaining > 0} class="avatar placeholder">
        <div class={["bg-neutral text-neutral-content rounded-full", @size_class]}>
          <span class="text-xs">+{@remaining}</span>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See `<head>` in root.html.heex which applies the theme before sheet load.

  ## Examples

      <.theme_toggle />
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="monitor" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="sun" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="moon" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end

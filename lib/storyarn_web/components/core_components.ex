defmodule StoryarnWeb.Components.CoreComponents do
  @moduledoc """
  Provides the small set of HEEx helpers still used globally by LiveViews and
  layout components.
  """
  use Phoenix.Component
  use Gettext, backend: Storyarn.Gettext
  use LiveVue

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      data-slot="toast"
      class={[
        "absolute z-30 right-5 bottom-5 w-fit group pointer-events-auto flex items-start gap-3 overflow-hidden rounded-lg border p-4 shadow-lg transition-all cursor-pointer",
        "data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0",
        @kind == :info && "border-border bg-background text-foreground",
        @kind == :error && "border-destructive/50 bg-destructive text-destructive-foreground"
      ]}
      {@rest}
    >
      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-2">
          <.icon :if={@kind == :info} name="info" class="size-4 shrink-0" />
          <.icon :if={@kind == :error} name="alert-circle" class="size-4 shrink-0" />
          <p :if={@title} data-slot="toast-title" class="text-sm font-semibold">{@title}</p>
          <p
            :if={!@title}
            data-slot="toast-description"
            class={["text-sm", @kind == :info && "text-muted-foreground"]}
          >
            {msg}
          </p>
        </div>
        <div
          :if={@title}
          data-slot="toast-description"
          class={["text-sm mt-1 ml-6", @kind == :info && "text-muted-foreground"]}
        >
          {msg}
        </div>
      </div>
      <button
        type="button"
        data-slot="toast-close"
        class="absolute top-3 right-3 rounded-md p-1 opacity-0 transition-opacity group-hover:opacity-100 focus:opacity-100 focus:outline-none focus:ring-2 focus:ring-ring"
        aria-label={gettext("close")}
      >
        <.icon name="x" class="size-3.5" />
      </button>
    </div>
    """
  end

  @doc """
  Renders a [Lucide icon](https://lucide.dev).

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  ## Examples

      <.icon name="x" />
      <.icon name="loader-circle" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :string, default: "size-4"
  attr :style, :string, default: nil
  attr :rest, :global

  def icon(assigns) do
    assigns = assign_new(assigns, :uid, fn -> System.unique_integer([:positive]) end)

    ~H"""
    <.vue
      v-component="components/LucideIcon"
      id={"icon-#{@name}-#{@uid}"}
      name={@name}
      icon-class={@class}
      class={@class}
      v-ssr={false}
      {@rest}
    />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300", "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end
end

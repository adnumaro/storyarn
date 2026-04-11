defmodule StoryarnWeb.Components.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Lucide Icons](https://lucide.dev) - see `icon/1` for usage.

    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

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
        "absolute z-30 right-5 top-5 w-fit group pointer-events-auto flex items-start gap-3 overflow-hidden rounded-lg border p-4 shadow-lg transition-all cursor-pointer",
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
          <p :if={!@title} data-slot="toast-description" class={["text-sm", @kind == :info && "text-muted-foreground"]}>{msg}</p>
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
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :string
  attr :variant, :string, values: ~w(primary error)
  attr :size, :string, default: "sm", values: ~w(xs sm md lg), doc: "button size"
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{
      "primary" => "btn-primary",
      "error" => "btn-error",
      nil => "btn-primary btn-soft"
    }

    sizes = %{"xs" => "btn-xs", "sm" => "btn-sm", "md" => nil, "lg" => "btn-lg"}

    assigns =
    assign_new(assigns, :class, fn ->
      ["btn", Map.fetch!(variants, assigns[:variant]), Map.fetch!(sizes, assigns[:size])]
    end)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
  default: &Function.identity / 1,
  doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
    with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
      assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
    end

    ~H"""
    <table class="w-full text-sm">
      <thead>
        <tr>
          <th :for={col <- @col}>{col[:label]}</th>
          <th :if={@action != []}>
            <span class="sr-only">{gettext("Actions")}</span>
          </th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={@row_click && "hover:cursor-pointer"}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="w-0 font-semibold">
            <div class="flex gap-4">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="list">
      <li :for={item <- @item} class="list-row">
        <div class="list-col-grow">
          <div class="font-bold">{item.title}</div>
          <div>{render_slot(item)}</div>
        </div>
      </li>
    </ul>
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
    {"transition-all ease-out duration-300",
      "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
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

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(Storyarn.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(Storyarn.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end

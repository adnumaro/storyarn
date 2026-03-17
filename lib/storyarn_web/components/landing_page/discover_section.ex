defmodule StoryarnWeb.Components.LandingPage.DiscoverSection do
  @moduledoc """
  Discover section for the landing page.
  """
  use StoryarnWeb, :html

  import StoryarnWeb.Components.TextComponents, only: [widont: 1]

  def discover_section(assigns) do
    features = discover_features()
    active_feature = features |> hd() |> Map.fetch!(:id)
    active_slide = features |> hd() |> Map.fetch!(:slides) |> hd() |> Map.fetch!(:id)

    assigns =
      assigns
      |> assign(:features, features)
      |> assign(:active_feature, active_feature)
      |> assign(:active_slide, active_slide)

    ~H"""
    <section class="lp-auto-section py-16 lg:py-20 scroll-mt-32" id="discover" data-section-step>
      <div class="mx-auto w-[min(calc(100%-48px),1280px)]">
        <.section_header
          title={gettext("See how it all connects")}
          description={
            gettext(
              "Four core tools. One connected workflow. Explore how each layer of Storyarn strengthens the rest."
            )
          }
        />

        <div
          class="lp-discover-shell"
          data-feature-shell
          data-active-feature={@active_feature}
          data-active-slide={@active_slide}
        >
          <div class="lp-discover-rail">
            <.discover_tabs features={@features} active_feature={@active_feature} />
          </div>

          <div class="lp-discover-body">
            <div class="lp-discover-stage-shell">
              <div class="lp-discover-display">
                <%= for feature <- @features do %>
                  <%= for slide <- feature.slides do %>
                    <.discover_preview
                      feature={feature}
                      slide={slide}
                      active_feature={@active_feature}
                      active_slide={@active_slide}
                    />
                  <% end %>
                <% end %>
              </div>

              <div class="lp-discover-trigger-groups">
                <.discover_trigger_group
                  :for={feature <- @features}
                  feature={feature}
                  active_feature={@active_feature}
                  active_slide={@active_slide}
                />
              </div>
            </div>

            <div class="lp-discover-scrollbox" data-feature-scrollbox>
              <div
                :for={feature <- @features}
                class={[
                  "lp-discover-slide-group",
                  feature.id == @active_feature && "is-active"
                ]}
                data-feature-group={feature.id}
              >
                <.discover_step
                  :for={{slide, index} <- Enum.with_index(feature.slides, 1)}
                  feature={feature}
                  slide={slide}
                  index={index}
                  active_feature={@active_feature}
                  active_slide={@active_slide}
                />
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

  attr :title, :string, required: true
  attr :description, :string, required: true

  defp section_header(assigns) do
    ~H"""
    <div class="grid gap-4 mb-8 max-w-[56rem]" data-reveal>
      <h2 class="text-[clamp(2.2rem,3vw,3.8rem)] leading-[0.97] tracking-[-0.06em] font-bold text-base-content">
        {widont(@title)}
      </h2>
      <p class="max-w-[36rem] text-base-content/60 leading-relaxed text-base">
        {widont(@description)}
      </p>
    </div>
    """
  end

  attr :features, :list, required: true
  attr :active_feature, :string, required: true

  defp discover_tabs(assigns) do
    ~H"""
    <div class="lp-discover-tabs" role="tablist" aria-label={gettext("Main features")}>
      <button
        :for={feature <- @features}
        class={["lp-discover-tab", feature.id == @active_feature && "is-active"]}
        type="button"
        role="tab"
        aria-selected={if(feature.id == @active_feature, do: "true", else: "false")}
        data-feature-tab={feature.id}
      >
        {feature.label}
      </button>
    </div>
    """
  end

  attr :feature, :map, required: true
  attr :active_feature, :string, required: true
  attr :active_slide, :string, required: true

  defp discover_trigger_group(assigns) do
    ~H"""
    <div
      class={[
        "lp-discover-trigger-group",
        @feature.id == @active_feature && "is-active"
      ]}
      data-feature-triggers={@feature.id}
      data-slide-count={length(@feature.slides)}
    >
      <button
        :for={{slide, index} <- Enum.with_index(@feature.slides, 1)}
        class={[
          "lp-discover-trigger",
          @feature.id == @active_feature && slide.id == @active_slide && "is-active"
        ]}
        type="button"
        data-slide-trigger
        data-feature={@feature.id}
        data-slide-target={slide.id}
      >
        <span class="lp-discover-trigger-index">
          {index |> Integer.to_string() |> String.pad_leading(2, "0")}
        </span>
        <span class="lp-discover-trigger-label">{slide.trigger}</span>
      </button>
    </div>
    """
  end

  attr :feature, :map, required: true
  attr :slide, :map, required: true
  attr :active_feature, :string, required: true
  attr :active_slide, :string, required: true

  defp discover_preview(assigns) do
    ~H"""
    <section
      class={[
        "lp-discover-preview",
        @feature.id == @active_feature && @slide.id == @active_slide && "is-active"
      ]}
      data-feature-preview={@feature.id}
      data-slide-preview={@slide.id}
    >
      <.discover_preview_head
        title={@slide.title}
        subtitle={@slide.description}
        badge={@feature.label}
      />
      <div class="lp-preview-card">
        <.discover_preview_visual slide_id={@slide.id} />
      </div>
    </section>
    """
  end

  attr :feature, :map, required: true
  attr :slide, :map, required: true
  attr :index, :integer, required: true
  attr :active_feature, :string, required: true
  attr :active_slide, :string, required: true

  defp discover_step(assigns) do
    ~H"""
    <article
      class={[
        "lp-discover-step",
        @feature.id == @active_feature && @slide.id == @active_slide && "is-active"
      ]}
      data-feature-step={@feature.id}
      data-slide={@slide.id}
    >
      <div class="lp-discover-step-top">
        <strong class="lp-discover-step-kicker">
          {@feature.label}
          <span class="opacity-40">/</span>
          {widont(@slide.trigger)}
        </strong>
        <span class="badge badge-ghost badge-sm">
          {@index |> Integer.to_string() |> String.pad_leading(2, "0")}
        </span>
      </div>

      <div class="lp-discover-step-copy">
        <h3 class="text-[clamp(1.85rem,2.4vw,2.7rem)] leading-[0.98] tracking-[-0.04em] font-bold text-base-content">
          {widont(@slide.title)}
        </h3>
        <p class="max-w-[34rem] text-base-content/60 leading-relaxed text-base">
          {widont(@slide.description)}
        </p>
      </div>

      <ul class="lp-discover-step-points">
        <li :for={item <- @slide.items} class="lp-step-item">{widont(item)}</li>
      </ul>
    </article>
    """
  end

  attr :title, :string, required: true
  attr :subtitle, :string, required: true
  attr :badge, :string, required: true

  defp discover_preview_head(assigns) do
    ~H"""
    <div class="flex flex-col sm:flex-row items-start justify-between gap-4">
      <div class="max-w-[32rem]">
        <strong class="block text-xl tracking-tight text-base-content">{widont(@title)}</strong>
        <span class="block mt-2 text-base-content/50 text-sm leading-relaxed">
          {widont(@subtitle)}
        </span>
      </div>
      <span class="badge badge-ghost badge-sm whitespace-nowrap">{@badge}</span>
    </div>
    """
  end

  attr :slide_id, :string, required: true

  defp discover_preview_visual(%{slide_id: "sheets-inheritance"} = assigns) do
    ~H"""
    <div class="lp-screenshot-placeholder">
      <.icon name="image" class="size-8 opacity-40" />
      <strong>{gettext("Sheet inheritance")}</strong>
      <span>
        {gettext(
          "Screenshot: Sheet tree sidebar showing parent/child hierarchy, with a child sheet open displaying inherited blocks and overrides highlighted. Dark mode, ~720×400px."
        )}
      </span>
    </div>
    """
  end

  defp discover_preview_visual(%{slide_id: "flows-node-graph"} = assigns) do
    ~H"""
    <div class="lp-screenshot-placeholder">
      <.icon name="image" class="size-8 opacity-40" />
      <strong>{gettext("Flow node graph")}</strong>
      <span>
        {gettext(
          "Screenshot: Flow editor canvas with dialogue, condition, choice, and subflow nodes connected. Show a branching conversation with multiple paths. Dark mode, ~720×400px."
        )}
      </span>
    </div>
    """
  end

  defp discover_preview_visual(%{slide_id: "scenes-layers"} = assigns) do
    ~H"""
    <div class="lp-screenshot-placeholder">
      <.icon name="image" class="size-8 opacity-40" />
      <strong>{gettext("Scene layers")}</strong>
      <span>
        {gettext(
          "Screenshot: Scene editor with layers panel visible, showing base map layer, fog of war layer toggled on, and a signals layer. Canvas with background image. Dark mode, ~720×400px."
        )}
      </span>
    </div>
    """
  end

  defp discover_features do
    [
      %{
        id: "sheets",
        label: gettext("Sheets"),
        slides: [
          %{
            id: "sheets-inheritance",
            trigger: gettext("Inheritance"),
            title: gettext("Inheritance keeps your world consistent"),
            description:
              gettext(
                "Parent and child sheets let you evolve characters, factions, and locations without duplicating structures."
              ),
            items: [
              gettext("Shared variables and blocks flow down the hierarchy."),
              gettext("Override only what changes — per variant, episode, or region."),
              gettext("Scale the world model without copy-paste.")
            ]
          }
        ]
      },
      %{
        id: "flows",
        label: gettext("Flows"),
        slides: [
          %{
            id: "flows-node-graph",
            trigger: gettext("Node graph"),
            title: gettext("Visual graphs that stay readable as scope grows"),
            description:
              gettext(
                "Dialogue, conditions, instructions, and branches in one graph — designed to stay clear even at production scale."
              ),
            items: [
              gettext("Conversations, state changes, and exits — modeled in one surface."),
              gettext("Logic stays connected to project data instead of living in fragments."),
              gettext("From quick sketches to production-scale dialogue graphs.")
            ]
          }
        ]
      },
      %{
        id: "scenes",
        label: gettext("Scenes"),
        slides: [
          %{
            id: "scenes-layers",
            trigger: gettext("Layers"),
            title: gettext("Layers and fog keep complex maps readable"),
            description:
              gettext(
                "Layers let you stage progression, visibility, and structure without flattening everything into one image."
              ),
            items: [
              gettext("Layered visibility instead of one overloaded canvas."),
              gettext("Fog of war to communicate progression and discoverability."),
              gettext("Large spaces stay understandable during review and iteration.")
            ]
          }
        ]
      }
    ]
  end
end

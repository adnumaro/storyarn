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
    <section class="py-16 lg:py-20 scroll-mt-32" id="discover">
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

  defp discover_preview_visual(%{slide_id: "dashboard-overview"} = assigns) do
    ~H"""
    <div class="lp-screenshot-placeholder">
      <.icon name="image" class="size-8 opacity-40" />
      <strong>{gettext("Project dashboard")}</strong>
      <span>
        {gettext(
          "Screenshot: Project dashboard with metric cards (variables, flows, coverage, exports), localization progress bars, and recent activity. Dark mode, ~720×400px."
        )}
      </span>
    </div>
    """
  end

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

  defp discover_preview_visual(%{slide_id: "sheets-formulas"} = assigns) do
    ~H"""
    <div class="lp-screenshot-placeholder">
      <.icon name="image" class="size-8 opacity-40" />
      <strong>{gettext("Cell formulas")}</strong>
      <span>
        {gettext(
          "Screenshot: Sheet table block with formula cells visible (e.g. =REP+2, =BASE*1.4), showing computed values alongside raw data. Dark mode, ~720×400px."
        )}
      </span>
    </div>
    """
  end

  defp discover_preview_visual(%{slide_id: "sheets-backlinks"} = assigns) do
    ~H"""
    <div class="lp-screenshot-placeholder">
      <.icon name="image" class="size-8 opacity-40" />
      <strong>{gettext("Entity backlinks")}</strong>
      <span>
        {gettext(
          "Screenshot: Sheet detail view with backlinks panel open, showing all flows, scenes, and screenplays that reference this entity. Dark mode, ~720×400px."
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

  defp discover_preview_visual(%{slide_id: "flows-story-player"} = assigns) do
    ~H"""
    <div class="lp-screenshot-placeholder">
      <.icon name="image" class="size-8 opacity-40" />
      <strong>{gettext("Story Player")}</strong>
      <span>
        {gettext(
          "Screenshot: Story Player running a flow with dialogue bubbles, speaker name, and choice buttons visible. Fullscreen player mode. Dark mode, ~720×400px."
        )}
      </span>
    </div>
    """
  end

  defp discover_preview_visual(%{slide_id: "flows-debug-mode"} = assigns) do
    ~H"""
    <div class="lp-screenshot-placeholder">
      <.icon name="image" class="size-8 opacity-40" />
      <strong>{gettext("Debug mode")}</strong>
      <span>
        {gettext(
          "Screenshot: Flow editor in debug mode with the debug panel open showing variable values, condition results (pass/fail), and execution history. Dark mode, ~720×400px."
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

  defp discover_preview_visual(%{slide_id: "scenes-connected"} = assigns) do
    ~H"""
    <div class="lp-screenshot-placeholder">
      <.icon name="image" class="size-8 opacity-40" />
      <strong>{gettext("Connected scene data")}</strong>
      <span>
        {gettext(
          "Screenshot: Scene canvas with pins that show connected sheet references, flow triggers, and quest state links in tooltips or side panel. Dark mode, ~720×400px."
        )}
      </span>
    </div>
    """
  end

  defp discover_preview_visual(%{slide_id: "scenes-pins-zones"} = assigns) do
    ~H"""
    <div class="lp-screenshot-placeholder">
      <.icon name="image" class="size-8 opacity-40" />
      <strong>{gettext("Pins and zones")}</strong>
      <span>
        {gettext(
          "Screenshot: Scene canvas with drawn zones, placed pins, and an open pin/zone config panel showing actions, conditions, and flow triggers. Dark mode, ~720×400px."
        )}
      </span>
    </div>
    """
  end

  defp discover_features do
    [
      %{
        id: "dashboard",
        label: gettext("Dashboard"),
        slides: [
          %{
            id: "dashboard-overview",
            trigger: gettext("Project view"),
            title: gettext("See the full picture from one dashboard"),
            description:
              gettext(
                "Track narrative scale, localization coverage, and production readiness without opening each tool individually."
              ),
            items: [
              gettext("Narrative scale, health, and progress — visible at a glance."),
              gettext("A shared picture for leads before reviews and planning."),
              gettext("Production conversations grounded in live data, not memory.")
            ]
          }
        ]
      },
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
          },
          %{
            id: "sheets-formulas",
            trigger: gettext("Cell formulas"),
            title: gettext("Tables mix manual data and live formulas"),
            description:
              gettext(
                "Per-cell formulas turn sheet tables into live systems for balancing, tracking, and narrative state."
              ),
            items: [
              gettext("Mix raw values, computed fields, and references in one grid."),
              gettext(
                "Balance the game where the narrative lives — not in a separate spreadsheet."
              ),
              gettext("Systemic tuning stays inside the narrative model.")
            ]
          },
          %{
            id: "sheets-backlinks",
            trigger: gettext("Backlinks"),
            title: gettext("See where every entity is referenced"),
            description:
              gettext(
                "Reference tracking makes dependencies visible — changing a character or quest is never a blind edit."
              ),
            items: [
              gettext("Jump from any sheet to every flow, scene, or screenplay that uses it."),
              gettext("Review impact before renaming, restructuring, or deleting."),
              gettext("Sheets become live production assets, not static database entries.")
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
          },
          %{
            id: "flows-story-player",
            trigger: gettext("Story Player"),
            title: gettext("Play the story without leaving the editor"),
            description:
              gettext(
                "Run any flow as a player. Feel the rhythm, inspect outcomes, and catch issues before handoff."
              ),
            items: [
              gettext("Walk through choices and branches in the same workspace."),
              gettext("Validate pacing and tone before anything reaches the engine."),
              gettext("Turn authored flows into something the whole team can experience.")
            ]
          },
          %{
            id: "flows-debug-mode",
            trigger: gettext("Debug mode"),
            title: gettext("See exactly why a branch was taken"),
            description:
              gettext(
                "Variable values, condition results, and transitions — all visible so teams can diagnose logic at a glance."
              ),
            items: [
              gettext("What passed, what failed, and what changed — all on screen."),
              gettext("Branching bugs become reviewable by designers, not just engineers."),
              gettext("Hidden logic becomes an inspectable, shareable system.")
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
          },
          %{
            id: "scenes-connected",
            trigger: gettext("Connected systems"),
            title: gettext("Maps wired to your narrative data"),
            description:
              gettext(
                "Characters, state, and interactables stay connected to the project model instead of living in separate documents."
              ),
            items: [
              gettext("Story logic, references, and world data — on the map surface."),
              gettext("No hand-maintained links between spatial design and narrative logic."),
              gettext("Scenes become connected production assets, not isolated boards.")
            ]
          },
          %{
            id: "scenes-pins-zones",
            trigger: gettext("Pins and zones"),
            title: gettext("Pins and zones make scenes interactive"),
            description:
              gettext(
                "Actions and triggers react to narrative state — spatial storytelling becomes playable, not just descriptive."
              ),
            items: [
              gettext("Hotspots, routes, and interactions placed directly on the scene."),
              gettext("Actions gated by narrative variables and conditions."),
              gettext("Prototype exploration logic before the engine build.")
            ]
          }
        ]
      }
    ]
  end
end

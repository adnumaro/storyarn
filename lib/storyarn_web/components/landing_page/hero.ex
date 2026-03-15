defmodule StoryarnWeb.Components.LandingPage.Hero do
  @moduledoc """
  Hero section for the landing page.
  """
  use StoryarnWeb, :html

  def hero(assigns) do
    ~H"""
    <section class="relative min-w-screen min-h-screen overflow-hidden">
      <div class="relative">
        <div class="relative mx-auto mt-[80px] w-[min(calc(100%-48px),1280px)] lg:mt-[150px]">
          <div class="relative z-3 w-full max-w-[1100px] pt-12 lg:pt-20">
            <%!-- Eyebrow badge --%>
            <div class="inline-flex items-center gap-2.5 px-4 py-2.5 rounded-full border border-primary/20 bg-primary/10 text-primary text-xs tracking-widest uppercase">
              <span class="w-2.5 h-2.5 rounded-full bg-primary shadow-[0_0_20px_var(--color-primary)]">
              </span>
              {gettext("Private beta")}
            </div>

            <%!-- Masthead: mascot + title --%>
            <div class="flex items-start gap-7 mt-7">
              <img
                src={~p"/images/logo-light-200.png"}
                alt="Storyarn"
                class="w-52 flex-none drop-shadow-2xl dark:hidden sm:block"
              />
              <img
                src={~p"/images/logo-dark-200.png"}
                alt="Storyarn"
                class="w-52 flex-none drop-shadow-2xl hidden dark:sm:block"
              />
              <div>
                <h1 class="text-[clamp(4rem,7.2vw,7.2rem)] leading-[0.88] tracking-[-0.07em] font-bold text-base-content">
                  {gettext("Craft worlds.")}
                  <span class="block mt-1.5 brand-logotype text-[1em]">
                    {gettext("Weave stories.")}
                  </span>
                </h1>
              </div>
            </div>

            <p class="mt-6 max-w-[46rem] text-base-content/60 text-lg leading-relaxed">
              {gettext(
                "The narrative design platform where characters, dialogue, worlds, and localization live in one connected project — from first draft to engine-ready export."
              )}
            </p>

            <div class="flex flex-wrap gap-3.5 mt-8">
              <a href="#product" class="btn btn-primary btn-lg rounded-full">
                {gettext("Explore Storyarn")}
              </a>
              <a
                href="#workflow"
                class="btn btn-ghost btn-lg rounded-full border border-base-content/10"
              >
                {gettext("See workflow")}
              </a>
            </div>
          </div>

          <.product_window />
        </div>
      </div>
    </section>
    """
  end

  # ──────────────────────────────────────────────
  # Product Window (decorative app simulation)
  # ──────────────────────────────────────────────

  defp product_window(assigns) do
    ~H"""
    <section class="lp-hero-product" id="product">
      <div class="rounded-[2rem] border border-base-content/8 bg-base-200/90 shadow-2xl overflow-hidden">
        <div class="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4 p-5 border-b border-base-content/7">
          <div>
            <strong class="block text-base tracking-tight text-base-content">
              {gettext("Project: Harbor of Broken Oaths")}
            </strong>
            <span class="block mt-1 text-base-content/50 text-xs">
              {gettext("Narrative RPG - 4 languages - 12 active scenes - 91 flows")}
            </span>
          </div>
          <div class="flex gap-2.5 flex-wrap">
            <span class="badge badge-ghost badge-sm">{gettext("Realtime collaboration")}</span>
            <span class="badge badge-ghost badge-sm">{gettext("Version snapshots")}</span>
            <span class="badge badge-ghost badge-sm">{gettext("Debug mode")}</span>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-[210px_1fr] min-h-[760px]">
          <.product_sidebar />
          <.product_workspace />
        </div>
      </div>
    </section>
    """
  end

  defp product_sidebar(assigns) do
    ~H"""
    <aside class="p-4 border-b lg:border-b-0 lg:border-r border-base-content/6 bg-base-content/3">
      <div class="flex items-center gap-3 px-2.5 pb-4">
        <img src={~p"/images/logo-dark-64.png"} alt="" class="w-10 h-10" />
        <div>
          <strong class="block text-sm text-base-content">Storyarn</strong>
          <span class="block mt-1 text-base-content/50 text-xs">
            {gettext("Narrative design platform")}
          </span>
        </div>
      </div>

      <nav class="grid gap-2">
        <.sidebar_item label={gettext("Dashboard")} />
        <.sidebar_item label={gettext("Sheets")} active />
        <.sidebar_item label={gettext("Flows")} active />
        <.sidebar_item label={gettext("Scenes")} />
        <.sidebar_item label={gettext("Screenplays")} />
        <.sidebar_item label={gettext("Localization")} />
        <.sidebar_item label={gettext("Exports")} />
      </nav>

      <div class="mt-4 p-3.5 rounded-2xl border border-base-content/8 bg-base-content/3">
        <strong class="block text-sm text-base-content">{gettext("Story Player ready")}</strong>
        <span class="block mt-1.5 text-base-content/50 text-xs leading-relaxed">
          {gettext(
            "Play through Act II with live variables, condition checks, and scene overlays."
          )}
        </span>
      </div>
    </aside>
    """
  end

  attr :label, :string, required: true
  attr :active, :boolean, default: false

  defp sidebar_item(assigns) do
    ~H"""
    <div class={[
      "flex items-center gap-3 px-3.5 py-3 rounded-2xl border",
      if(@active,
        do: "text-base-content bg-primary/10 border-primary/15",
        else: "text-base-content/70 border-transparent"
      )
    ]}>
      <em class="w-2.5 h-2.5 rounded bg-current opacity-80 not-italic"></em>
      {@label}
    </div>
    """
  end

  defp product_workspace(assigns) do
    ~H"""
    <div class="p-4 grid gap-4">
      <.product_metrics />
      <div class="grid grid-cols-1 lg:grid-cols-[1.08fr_0.92fr] gap-4">
        <.product_flow_panel />
        <.product_sheet_panel />
      </div>
      <div class="grid grid-cols-1 lg:grid-cols-[1fr_0.86fr] gap-4">
        <.product_scene_panel />
        <.product_localization_panel />
      </div>
      <.product_screenplay_panel />
    </div>
    """
  end

  defp product_metrics(assigns) do
    ~H"""
    <div class="grid grid-cols-2 lg:grid-cols-4 gap-3.5">
      <.metric_card
        value="126"
        label={gettext("variables connected across sheets, flows, and scenes")}
      />
      <.metric_card value="91" label={gettext("branching flows in the project")} />
      <.metric_card value="81%" label={gettext("localization coverage ready for review")} />
      <.metric_card value="4" label={gettext("export targets: Yarn, Ink, Unity, and Godot")} />
    </div>
    """
  end

  attr :value, :string, required: true
  attr :label, :string, required: true

  defp metric_card(assigns) do
    ~H"""
    <div class="p-4 rounded-2xl border border-base-content/7 bg-base-content/3">
      <strong class="block text-2xl tracking-tight text-base-content">{@value}</strong>
      <span class="block mt-1.5 text-base-content/50 text-xs leading-relaxed">{@label}</span>
    </div>
    """
  end

  defp product_flow_panel(assigns) do
    ~H"""
    <section class="rounded-3xl border border-base-content/8 bg-base-200/80 overflow-hidden">
      <.panel_header
        title={gettext("Flow editor")}
        subtitle={gettext("Dialogue, conditions, instructions, and branching — all in one graph")}
        badge={gettext("Node graph - live")}
      />
      <div class="lp-flow-canvas relative min-h-[294px]">
        <div
          class="lp-connection c1"
          style="left: 140px; top: 108px; width: 112px; transform: rotate(18deg);"
        >
        </div>
        <div
          class="lp-connection c2"
          style="left: 325px; top: 118px; width: 108px; transform: rotate(-20deg);"
        >
        </div>
        <div
          class="lp-connection c3"
          style="left: 322px; top: 174px; width: 116px; transform: rotate(24deg);"
        >
        </div>
        <.flow_node
          class="n1"
          type={gettext("Dialogue")}
          title={gettext("Captain Ilya")}
          desc={gettext("\"The harbor is still closed. I need a reason to open it.\"")}
        />
        <.flow_node
          class="n2"
          type={gettext("Condition")}
          title="rep_guardia >= 4"
          desc={gettext("Unlocks the diplomatic route if reputation is high enough.")}
        />
        <.flow_node
          class="n3"
          type={gettext("Choice")}
          title={gettext("Show travel permit")}
          desc={gettext("Uses the travel permit, earns trust, and enters the night harbor.")}
        />
        <.flow_node
          class="n4"
          type={gettext("Subflow")}
          title={gettext("Night Harbor")}
          desc={gettext("Triggers the overlay, scene pin, and global act state.")}
        />
      </div>
    </section>
    """
  end

  attr :class, :string, required: true
  attr :type, :string, required: true
  attr :title, :string, required: true
  attr :desc, :string, required: true

  defp flow_node(assigns) do
    ~H"""
    <div class={"lp-node #{@class}"}>
      <em>{@type}</em>
      <strong>{@title}</strong>
      <small>{@desc}</small>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :subtitle, :string, required: true
  attr :badge, :string, required: true

  defp panel_header(assigns) do
    ~H"""
    <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 p-4 border-b border-base-content/7">
      <div>
        <strong class="block text-base tracking-tight text-base-content">{@title}</strong>
        <span class="text-base-content/50 text-xs">{@subtitle}</span>
      </div>
      <span class="text-base-content/50 text-xs">{@badge}</span>
    </div>
    """
  end

  defp product_sheet_panel(assigns) do
    ~H"""
    <section class="rounded-3xl border border-base-content/8 bg-base-200/80 overflow-hidden">
      <.panel_header
        title={gettext("World sheet")}
        subtitle={gettext("Characters, factions, and world data connected to every tool")}
        badge={gettext("Character profile")}
      />
      <div class="p-4 grid gap-3">
        <.sheet_row
          label={gettext("Character")}
          desc={gettext("Captain Ilya - rank, trust, inventory, scene tags")}
          status={gettext("Live")}
        />
        <.sheet_row
          label={gettext("Faction")}
          desc={gettext("Harbor Guild - resources, favors, reputation and routes")}
          status={gettext("Linked")}
        />
        <.sheet_row
          label={gettext("Quest State")}
          desc={gettext("Act II - quarantine, forged seal, inner harbor access")}
          status={gettext("Tracked")}
        />
        <.sheet_row
          label={gettext("Inherited Blocks")}
          desc={gettext("Stats, progress flags and consequence table")}
          status={gettext("Shared")}
        />
      </div>
    </section>
    """
  end

  attr :label, :string, required: true
  attr :desc, :string, required: true
  attr :status, :string, required: true

  defp sheet_row(assigns) do
    ~H"""
    <div class="grid grid-cols-1 sm:grid-cols-[140px_1fr_auto] gap-3 items-center p-3.5 rounded-2xl border border-base-content/8 bg-base-content/3">
      <strong class="text-sm text-base-content">{@label}</strong>
      <span class="text-base-content/50 text-xs leading-relaxed">{@desc}</span>
      <span class="badge badge-sm bg-primary/10 text-primary border-primary/20">{@status}</span>
    </div>
    """
  end

  defp product_scene_panel(assigns) do
    ~H"""
    <section class="rounded-3xl border border-base-content/8 bg-base-200/80 overflow-hidden">
      <.panel_header
        title={gettext("Scene editor")}
        subtitle={gettext("Zones, pins, overlays and spatial links")}
        badge={gettext("Exploration mode")}
      />
      <div class="lp-scene-map relative min-h-[292px]">
        <div class="lp-zone z1"></div>
        <div class="lp-zone z2"></div>
        <div class="lp-zone z3"></div>
        <div class="lp-zone z4"></div>
        <div class="lp-pin p1"></div>
        <div class="lp-pin p2"></div>
        <div class="lp-pin p3"></div>
      </div>
    </section>
    """
  end

  defp product_localization_panel(assigns) do
    ~H"""
    <section class="rounded-3xl border border-base-content/8 bg-base-200/80 overflow-hidden">
      <.panel_header
        title={gettext("Localization")}
        subtitle={gettext("Coverage per language, glossary, and pending lines")}
        badge={gettext("DeepL ready")}
      />
      <div class="p-4 grid gap-3">
        <.locale_row lang="ES" width="100%" status={gettext("Ready")} />
        <.locale_row lang="EN" width="88%" status={gettext("Review")} />
        <.locale_row lang="FR" width="64%" status={gettext("In progress")} />
        <.locale_row lang="JA" width="32%" status={gettext("Blocked")} />
      </div>
    </section>
    """
  end

  attr :lang, :string, required: true
  attr :width, :string, required: true
  attr :status, :string, required: true

  defp locale_row(assigns) do
    ~H"""
    <div class="grid grid-cols-[64px_1fr_auto] gap-3 items-center p-3.5 rounded-2xl border border-base-content/8 bg-base-content/3">
      <strong class="text-sm text-base-content">{@lang}</strong>
      <div class="relative h-2.5 rounded-full bg-base-content/8 overflow-hidden">
        <span
          class="absolute inset-y-0 left-0 rounded-full bg-gradient-to-r from-primary to-primary/70"
          style={"width: #{@width};"}
        >
        </span>
      </div>
      <em class="not-italic text-xs text-base-content/50">{@status}</em>
    </div>
    """
  end

  @screenplay_sample """
  INT. HARBOR WATCH - NIGHT

  CAPTAIN ILYA
  The harbor is still closed.

  PROTAGONIST
  I'm not here to break the quarantine. I'm here to avoid it.

  IF rep_guardia >= 4
    ILYA lowers her spear.
  ELSE
    The watch tightens around the gate.\
  """

  defp product_screenplay_panel(assigns) do
    assigns = assign(assigns, :screenplay, String.trim(@screenplay_sample))

    ~H"""
    <section class="rounded-3xl border border-base-content/8 bg-base-200/80 overflow-hidden p-4">
      <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 mb-4">
        <div>
          <strong class="block text-base tracking-tight text-base-content">
            {gettext("Screenplay sync")}
          </strong>
          <span class="text-base-content/50 text-xs">
            {gettext("Professional script reading with flow synchronization")}
          </span>
        </div>
        <span class="text-base-content/50 text-xs">Courier Prime</span>
      </div>
      <div class="rounded-2xl border border-base-content/8 bg-base-content/3 p-5">
        <pre class="m-0 text-base-content/70 text-sm leading-relaxed whitespace-pre-wrap font-mono">{@screenplay}</pre>
      </div>
    </section>
    """
  end
end

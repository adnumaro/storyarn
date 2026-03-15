defmodule StoryarnWeb.Components.LandingPage.FeatureGrid do
  @moduledoc """
  Feature grid section for the landing page.
  """
  use StoryarnWeb, :html

  import StoryarnWeb.Components.TextComponents, only: [widont: 1]

  @feature_colors ~w(primary accent secondary primary accent secondary)

  def feature_grid(assigns) do
    features = [
      %{
        num: "01",
        icon: "table",
        title: gettext("Sheets as source of truth"),
        desc:
          gettext(
            "Characters, factions, quests, and items live in structured sheets with variables, formulas, and inheritance — your single source of truth."
          )
      },
      %{
        num: "02",
        icon: "git-branch",
        title: gettext("Flows you can actually play"),
        desc:
          gettext(
            "Build branching dialogue, then play it, debug it, and verify it — without ever leaving the editor."
          )
      },
      %{
        num: "03",
        icon: "map",
        title: gettext("Scenes with real exploration"),
        desc:
          gettext(
            "Place zones, pins, and triggers on a canvas. Walk through the world before it reaches the engine."
          )
      },
      %{
        num: "04",
        icon: "bug",
        title: gettext("Play it. Debug it. Ship it."),
        desc:
          gettext(
            "Experience the story as a player, or step through it with every variable and condition visible."
          )
      },
      %{
        num: "05",
        icon: "languages",
        title: gettext("Integrated localization"),
        desc:
          gettext(
            "Extract lines, translate with DeepL, manage glossaries, and track coverage per language — all from the same project."
          )
      },
      %{
        num: "06",
        icon: "package",
        title: gettext("Export for multiple engines"),
        desc:
          gettext(
            "Export to Yarn Spinner, Ink, Godot Dialogic, Unity, or Unreal — your narrative data, ready for production."
          )
      }
    ]

    assigns =
      assign(
        assigns,
        :features,
        features
        |> Enum.zip(@feature_colors)
        |> Enum.with_index()
      )

    ~H"""
    <section class="py-16 lg:py-20 scroll-mt-32" id="features">
      <div class="mx-auto w-[min(calc(100%-48px),1280px)]">
        <.section_header
          title={gettext("One platform, everything connected")}
          description={
            gettext(
              "Every tool designed to feed the others — so characters, logic, worlds, and translations stay connected instead of scattered across files."
            )
          }
        />

        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          <article
            :for={{{feature, color}, idx} <- @features}
            class="p-6 rounded-3xl border border-base-content/8 bg-base-200/60"
            data-reveal
            data-reveal-delay={"#{idx * 80}"}
          >
            <em class={"inline-flex items-center justify-center min-w-[46px] min-h-[46px] rounded-xl mb-4 not-italic text-#{color} bg-#{color}/10"}>
              <.icon name={feature.icon} class="size-5" />
            </em>
            <h3 class="mb-3 text-xl tracking-tight font-bold text-base-content">{feature.title}</h3>
            <p class="text-base-content/60 leading-relaxed">{feature.desc}</p>
          </article>
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
end

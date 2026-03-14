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
        title: gettext("Sheets as source of truth"),
        desc:
          gettext(
            "Characters, factions, quests, locations and items live in reusable structures with variables, formulas and inheritance."
          )
      },
      %{
        num: "02",
        title: gettext("Flows you can test"),
        desc:
          gettext(
            "The value is not just the visual tree: it's being able to debug, simulate and verify it without exporting to another tool."
          )
      },
      %{
        num: "03",
        title: gettext("Scenes with real exploration"),
        desc:
          gettext(
            "The spatial layer helps you think about the world as an interactive experience, not just as narrative documentation."
          )
      },
      %{
        num: "04",
        title: gettext("Story Player and Debug Mode"),
        desc:
          gettext(
            "Test the story as a player or inspect it step by step with variables and conditions visible."
          )
      },
      %{
        num: "05",
        title: gettext("Integrated localization"),
        desc:
          gettext(
            "Extract lines, translate, use glossaries and track coverage per language from the same narrative base."
          )
      },
      %{
        num: "06",
        title: gettext("Export for multiple engines"),
        desc:
          gettext(
            "From Storyarn to Yarn Spinner, Ink, Unity, Godot Dialogic, Unreal or writing tools without redoing the work."
          )
      }
    ]

    assigns = assign(assigns, :features, Enum.zip(features, @feature_colors))

    ~H"""
    <section class="py-16 lg:py-20 scroll-mt-32" id="features">
      <div class="mx-auto w-[min(calc(100%-48px),1280px)]">
        <.section_header
          title={gettext("One platform for interactive narrative")}
          description={
            gettext(
              "Storyarn is a real working ecosystem: data, branches, scenes, screenplays and localization all living inside the same project."
            )
          }
        />

        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          <article
            :for={{feature, color} <- @features}
            class="p-6 rounded-3xl border border-base-content/8 bg-base-200/60"
          >
            <em class={"inline-flex items-center justify-center min-w-[46px] min-h-[46px] rounded-xl mb-4 not-italic font-extrabold tracking-tight text-#{color} bg-#{color}/10"}>
              {feature.num}
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
    <div class="grid gap-4 mb-8 max-w-[56rem]">
      <h2 class="text-[clamp(2.2rem,3vw,3.8rem)] leading-[0.97] tracking-[-0.06em] font-bold max-w-[16ch] text-base-content">
        {widont(@title)}
      </h2>
      <p class="max-w-[36rem] text-base-content/60 leading-relaxed text-base">
        {widont(@description)}
      </p>
    </div>
    """
  end
end

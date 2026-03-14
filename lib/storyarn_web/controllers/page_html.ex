defmodule StoryarnWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use StoryarnWeb, :html

  import StoryarnWeb.Components.LandingPage.Hero
  import StoryarnWeb.Components.LandingPage.FeatureGrid
  import StoryarnWeb.Components.LandingPage.DiscoverSection
  import StoryarnWeb.Components.LandingPage.Spotlights
  import StoryarnWeb.Components.LandingPage.WorkflowGrid
  import StoryarnWeb.Components.LandingPage.CtaWaitlist
  import StoryarnWeb.Components.LandingPage.LandingFooter

  embed_templates "page_html/*"
end

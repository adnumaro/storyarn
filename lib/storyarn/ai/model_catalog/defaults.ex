defmodule Storyarn.AI.ModelCatalog.Defaults do
  @moduledoc """
  Versioned model contracts supported by Storyarn.

  This catalog is reviewed and shipped with the application. Provider model
  discovery can narrow availability for a particular account, but it never
  expands this allowlist.
  """

  @catalog_version 1
  @processing_locations ["provider-controlled"]

  @spec models() :: [map()]
  def models do
    [
      text_model("openai", "gpt-5.6-sol", :json_schema, 1_050_000, 128_000),
      text_model("openai", "gpt-5.6-terra", :json_schema, 1_050_000, 128_000),
      text_model("openai", "gpt-5.6-luna", :json_schema, 1_050_000, 128_000),
      media_model("openai", "gpt-image-2", [:images], [:text, :image], [:image], :openai_images),
      media_model("openai", "tts-1", [:speech], [:text], [:audio], :openai_speech),
      media_model("openai", "tts-1-hd", [:speech], [:text], [:audio], :openai_speech),
      text_model("anthropic", "claude-fable-5", :json_schema, 1_000_000, 128_000),
      text_model("anthropic", "claude-opus-4-8", :json_schema, 1_000_000, 128_000),
      text_model("anthropic", "claude-sonnet-5", :json_schema, 1_000_000, 128_000),
      text_model("anthropic", "claude-haiku-4-5-20251001", :json_schema, 200_000, 64_000),
      text_model("google", "gemini-3.6-flash", :json_schema, 1_048_576, 65_536),
      text_model("google", "gemini-3.5-flash-lite", :json_schema, 1_048_576, 65_536),
      text_model(
        "fireworks",
        "accounts/fireworks/models/qwen3p7-plus",
        :json_schema,
        262_144,
        65_536
      ),
      text_model("together", "Qwen/Qwen3.7-Plus", :json_schema, 1_000_000, 65_536),
      media_model(
        "google",
        "gemini-3.1-flash-lite-image",
        [:images],
        [:text, :image],
        [:text, :image],
        :google_interactions_image
      ),
      media_model(
        "google",
        "gemini-3.1-flash-image",
        [:images],
        [:text, :image],
        [:text, :image],
        :google_interactions_image
      ),
      media_model(
        "google",
        "gemini-3-pro-image",
        [:images],
        [:text, :image],
        [:text, :image],
        :google_interactions_image
      ),
      media_model(
        "google",
        "gemini-3.1-flash-tts-preview",
        [:speech],
        [:text],
        [:audio],
        :google_interactions_tts,
        :preview
      ),
      text_model("moonshot", "kimi-k3", :json_object, 1_048_576, 131_072),
      text_model("moonshot", "kimi-k2.6", :json_object, 262_144, 32_768),
      text_model("mistral", "mistral-large-2512", :json_schema, 262_144, 32_768),
      text_model("mistral", "mistral-small-2603", :json_schema, 262_144, 32_768),
      text_model("deepseek", "deepseek-v4-pro", :json_object, 1_000_000, 384_000),
      text_model("deepseek", "deepseek-v4-flash", :json_object, 1_000_000, 384_000)
    ]
  end

  defp text_model(provider, model, structured_output, context_window, max_output_tokens) do
    %{
      provider: provider,
      model: model,
      catalog_version: @catalog_version,
      capabilities: [:translation, :suggestions, :tasks],
      input_modalities: [:text],
      output_modalities: [:text],
      structured_output: structured_output,
      api_family: :structured_text,
      implementation_status: :executable,
      release_stage: :stable,
      context_window: context_window,
      max_output_tokens: max_output_tokens,
      processing_locations: @processing_locations,
      pricing_version: nil,
      deprecated: false
    }
  end

  defp media_model(
         provider,
         model,
         capabilities,
         input_modalities,
         output_modalities,
         api_family,
         release_stage \\ :stable
       ) do
    %{
      provider: provider,
      model: model,
      catalog_version: @catalog_version,
      capabilities: capabilities,
      input_modalities: input_modalities,
      output_modalities: output_modalities,
      structured_output: :none,
      api_family: api_family,
      implementation_status: :configuration_only,
      release_stage: release_stage,
      context_window: nil,
      max_output_tokens: nil,
      processing_locations: @processing_locations,
      pricing_version: nil,
      deprecated: false
    }
  end
end

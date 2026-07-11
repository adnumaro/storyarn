defmodule Storyarn.TestSupport.FakeTranslationProvider do
  @moduledoc false

  def translate(texts, _source_lang, target_lang, _config) do
    if test_pid = Process.get(:fake_translation_provider_test_pid) do
      send(test_pid, {:fake_translation_provider_call, texts})
    end

    case Process.get(:fake_translation_provider_responses) do
      [response | responses] ->
        Process.put(:fake_translation_provider_responses, responses)
        respond(response, texts, target_lang)

      _responses ->
        respond(:ok, texts, target_lang)
    end
  end

  def translate(texts, source_lang, target_lang, config, _opts) do
    translate(texts, source_lang, target_lang, config)
  end

  defp respond(:ok, texts, target_lang) do
    translations =
      Enum.map(texts, fn text ->
        %{text: "#{target_lang}: #{text}", detected_source_lang: nil}
      end)

    {:ok, translations}
  end

  defp respond({:error, _reason} = error, _texts, _target_lang), do: error
end

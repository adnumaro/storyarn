defmodule Storyarn.Platform.EventTracker do
  @moduledoc """
  Applies Platform-owned, best-effort reactions to context events.

  Registered reactions declare which event types they understand; this module
  builds and owns the routing table. Event producers remain free of analytics,
  notification, and delivery policy. Durable reactions are intentionally
  excluded until an outbox contract can provide atomic persistence,
  idempotency, and retries.
  """

  alias Storyarn.Platform.ProductMetrics

  require Logger

  @reaction_handlers [ProductMetrics]

  @spec react(term(), atom(), atom(), map()) :: :ok
  def react(scope_or_user, source, event_type, payload)
      when is_atom(source) and is_atom(event_type) and is_map(payload) do
    react_with_handlers(scope_or_user, source, event_type, payload, @reaction_handlers)
  end

  def react(_scope_or_user, _source, _event_type, _payload), do: :ok

  @doc false
  @spec react_with_handlers(term(), atom(), atom(), map(), [module()]) :: :ok
  def react_with_handlers(scope_or_user, source, event_type, payload, handlers)
      when is_atom(source) and is_atom(event_type) and is_map(payload) and is_list(handlers) do
    handlers
    |> routes()
    |> Map.get({source, event_type}, [])
    |> Enum.each(fn handler ->
      safely_handle(handler, scope_or_user, source, event_type, payload)
    end)

    :ok
  rescue
    error ->
      log_failure("routing", {source, event_type}, nil, Exception.message(error))
      :ok
  catch
    kind, reason ->
      log_failure("routing", {source, event_type}, nil, inspect({kind, reason}))
      :ok
  end

  def react_with_handlers(_scope_or_user, _source, _event_type, _payload, _handlers), do: :ok

  @doc false
  @spec routes() :: %{{atom(), atom()} => [module()]}
  def routes, do: routes(@reaction_handlers)

  @doc false
  @spec routes([module()]) :: %{{atom(), atom()} => [module()]}
  def routes(handlers) when is_list(handlers) do
    Enum.reduce(handlers, %{}, fn handler, acc ->
      Enum.reduce(safely_discover_events(handler), acc, fn event, routes ->
        Map.update(routes, event, [handler], &(&1 ++ [handler]))
      end)
    end)
  rescue
    error ->
      log_failure("routing", nil, nil, Exception.message(error))
      %{}
  catch
    kind, reason ->
      log_failure("routing", nil, nil, inspect({kind, reason}))
      %{}
  end

  def routes(_handlers), do: %{}

  defp safely_discover_events(handler) when is_atom(handler) do
    case handler.events() do
      events when is_list(events) ->
        events
        |> Enum.reduce([], fn
          {source, event_type} = event, acc when is_atom(source) and is_atom(event_type) ->
            [event | acc]

          invalid_event, acc ->
            log_failure("routing", invalid_event, handler, "invalid event declaration")
            acc
        end)
        |> Enum.reverse()
        |> Enum.uniq()

      invalid_events ->
        log_failure("discovery", nil, handler, "expected a list, got: #{inspect(invalid_events)}")
        []
    end
  rescue
    error ->
      log_failure("discovery", nil, handler, Exception.message(error))
      []
  catch
    kind, reason ->
      log_failure("discovery", nil, handler, inspect({kind, reason}))
      []
  end

  defp safely_discover_events(handler) do
    log_failure("discovery", nil, handler, "expected a module")
    []
  end

  defp safely_handle(handler, scope_or_user, source, event_type, payload) do
    handler.handle(scope_or_user, source, event_type, payload)
  rescue
    error ->
      log_failure("execution", {source, event_type}, handler, Exception.message(error))
      :ok
  catch
    kind, reason ->
      log_failure("execution", {source, event_type}, handler, inspect({kind, reason}))
      :ok
  end

  defp log_failure(stage, event, handler, reason) do
    Logger.warning(
      "Platform best-effort reaction #{stage} failed" <>
        failure_context(event, handler) <> ": " <> reason
    )
  end

  defp failure_context(nil, nil), do: ""
  defp failure_context(event, nil), do: " for #{inspect(event)}"
  defp failure_context(nil, handler), do: " in #{inspect(handler)}"
  defp failure_context(event, handler), do: " for #{inspect(event)} in #{inspect(handler)}"
end

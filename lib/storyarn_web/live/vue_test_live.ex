defmodule StoryarnWeb.VueTestLive do
  use StoryarnWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, count: 0)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-8 max-w-lg mx-auto space-y-6">
      <h1 class="text-2xl font-bold">LiveVue Test</h1>

      <div class="space-y-2">
        <p class="text-sm text-base-content/60">Server count: {@count}</p>
        <button phx-click="inc" class="btn btn-primary btn-sm">Increment from server</button>
      </div>

      <div class="divider">Vue Component Below</div>

      <.vue v-component="HelloVue" message={"Count is #{@count}"} v-socket={@socket} id="hello-vue" />
    </div>
    """
  end

  @impl true
  def handle_event("inc", _params, socket) do
    {:noreply, assign(socket, :count, socket.assigns.count + 1)}
  end
end

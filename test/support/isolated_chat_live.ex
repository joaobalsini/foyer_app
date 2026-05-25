defmodule FoyerWeb.IsolatedChatLive do
  @moduledoc """
  Test-only LiveView wrapper around `FoyerWeb.ChatLive`. Mounts with a
  pre-built `current_scope` taken from the isolated session (provided by
  `FoyerWeb.IsolatedHelpers.mount_isolated_chat/3`), then delegates
  `mount/3`, `handle_params/3`, `handle_event/3`, `handle_info/2`, and
  `render/1` to the real `ChatLive`.

  This wrapper is required because `Phoenix.LiveViewTest.live_isolated/3`
  skips on-mount hooks, so the production `:ensure_on_shift`/`:mount_public`
  hooks never run and `socket.assigns.current_scope` would otherwise be
  missing.

  Keep this module test-only; it must never be referenced from production
  routes (it lives under `test/support`, compiled only in `Mix.env() ==
  :test`).
  """
  use Phoenix.LiveView

  alias FoyerWeb.ChatLive
  alias FoyerWeb.IsolatedHelpers

  @impl true
  def mount(_params, session, socket) do
    user = Map.fetch!(session, "foyer_isolated_user")
    on_shift? = Map.get(session, "foyer_isolated_on_shift?", true)
    live_action = Map.fetch!(session, "foyer_isolated_live_action")

    scope = IsolatedHelpers.build_scope(user, on_shift?)

    socket =
      socket
      |> assign(:current_scope, scope)
      |> assign(:live_action, live_action)
      |> assign(:current_user, user)

    {:ok, socket} = ChatLive.mount(%{}, %{}, socket)

    # ChatLive.mount/3 sets up streams and assigns; immediately also run
    # handle_params/3 to populate the rest, matching the production flow
    # where Phoenix calls handle_params after mount during the connected
    # render. Without this, isolated tests would see only the post-mount,
    # pre-handle_params skeleton.
    params = %{
      "conversation_id" => session["foyer_isolated_conversation_id"]
    }

    {:noreply, socket} = ChatLive.handle_params(params, "/chat", socket)
    {:ok, socket}
  end

  # NOTE: `handle_params/3` is intentionally NOT defined on this wrapper.
  # `live_isolated/3` mounts the LV without a router, so Phoenix's
  # post-mount call into `handle_params/3` would fail at
  # `Route.live_link_info!/3`. We bridge handle_params manually from mount
  # above. ChatLive's :show/:new_message/:inbox branches all work off
  # `socket.assigns.live_action`, which we set in mount/3.

  @impl true
  def handle_event(event, params, socket), do: ChatLive.handle_event(event, params, socket)

  @impl true
  def handle_info(msg, socket), do: ChatLive.handle_info(msg, socket)

  @impl true
  def render(assigns), do: ChatLive.render(assigns)
end

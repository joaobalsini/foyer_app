defmodule FoyerWeb.IsolatedProfileLive do
  @moduledoc """
  Test-only LiveView wrapper around `FoyerWeb.ProfileLive`. Mounts with a
  pre-built `current_scope` taken from the isolated session, then delegates
  `mount/3`, `handle_params/3`, `handle_event/3`, and `render/1` to the real
  `ProfileLive`.

  This wrapper is required because `Phoenix.LiveViewTest.live_isolated/3`
  skips on-mount hooks, so `socket.assigns.current_scope` would otherwise be
  missing.

  Keep this module test-only; it must never be referenced from production
  routes (it lives under `test/support`, compiled only in `MIX_ENV == test`).
  """
  use Phoenix.LiveView

  alias FoyerWeb.ProfileLive

  @impl true
  def mount(_params, session, socket) do
    user = Map.fetch!(session, "foyer_isolated_user")
    on_shift? = Map.get(session, "foyer_isolated_on_shift?", true)
    scope = FoyerWeb.IsolatedHelpers.build_scope(user, on_shift?)

    socket =
      socket
      |> assign(:current_scope, scope)
      |> assign(:live_action, :me)
      |> assign(:chat_unread_count, 0)

    {:ok, socket} = ProfileLive.mount(%{}, %{}, socket)

    # Manually call handle_params since live_isolated skips the router's
    # post-mount callback. Without this the card assign stays nil.
    {:noreply, socket} = ProfileLive.handle_params(%{}, "/me", socket)

    {:ok, socket}
  end

  # NOTE: handle_params intentionally NOT defined — we bridge it from mount.
  # handle_event and handle_info are omitted since ProfileLive does not define
  # them (read-only surface). If ProfileLive grows events, add them here.

  @impl true
  def render(assigns), do: ProfileLive.render(assigns)
end

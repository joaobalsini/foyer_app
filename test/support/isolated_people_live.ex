defmodule FoyerWeb.IsolatedPeopleLive do
  @moduledoc """
  Test-only LiveView wrapper around `FoyerWeb.PeopleLive` for `:show` action.
  Mounts with a pre-built `current_scope` taken from the isolated session, then
  delegates to the real `PeopleLive`.

  This wrapper is required because `Phoenix.LiveViewTest.live_isolated/3`
  skips on-mount hooks, so `socket.assigns.current_scope` would otherwise be
  missing.

  Keep this module test-only.
  """
  use Phoenix.LiveView

  alias FoyerWeb.PeopleLive

  @impl true
  def mount(_params, session, socket) do
    user = Map.fetch!(session, "foyer_isolated_user")
    on_shift? = Map.get(session, "foyer_isolated_on_shift?", true)
    live_action = Map.get(session, "foyer_isolated_live_action", :show)

    scope = FoyerWeb.IsolatedHelpers.build_scope(user, on_shift?)

    socket =
      socket
      |> assign(:current_scope, scope)
      |> assign(:live_action, live_action)
      |> assign(:chat_unread_count, 0)

    {:ok, socket} = PeopleLive.mount(%{}, %{}, socket)

    # Manually call handle_params since live_isolated skips the router
    subject_id = Map.fetch!(session, "foyer_isolated_subject_id")

    {:noreply, socket} =
      PeopleLive.handle_params(%{"id" => to_string(subject_id)}, "/people/#{subject_id}", socket)

    {:ok, socket}
  end

  # NOTE: handle_params intentionally NOT defined — we bridge it from mount.
  # handle_event and handle_info are omitted since PeopleLive does not define
  # them (read-only surface). If PeopleLive grows events, add them here.

  @impl true
  def render(assigns), do: PeopleLive.render(assigns)
end

defmodule FoyerWeb.IsolatedPeopleLive do
  @moduledoc """
  Test-only LiveView wrapper around `FoyerWeb.PeopleLive` for `:index` and
  `:show` actions. Mounts with a pre-built `current_scope` taken from the
  isolated session, then delegates to the real `PeopleLive`.

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

    # Manually call handle_params since live_isolated skips the router.
    {params, path} =
      case live_action do
        :show ->
          subject_id = Map.fetch!(session, "foyer_isolated_subject_id")
          {%{"id" => to_string(subject_id)}, "/people/#{subject_id}"}

        :index ->
          {%{}, "/people"}
      end

    {:noreply, socket} = PeopleLive.handle_params(params, path, socket)

    {:ok, socket}
  end

  # NOTE: handle_params intentionally NOT defined — we bridge it from mount.

  @impl true
  def handle_event(event, params, socket), do: PeopleLive.handle_event(event, params, socket)

  @impl true
  def render(assigns), do: PeopleLive.render(assigns)
end

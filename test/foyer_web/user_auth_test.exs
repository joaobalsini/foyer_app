defmodule FoyerWeb.UserAuthTest do
  @moduledoc """
  Plug- and on_mount-level tests for `FoyerWeb.UserAuth`.

  These tests exercise the security-sensitive plumbing that route smoke tests
  only touch by accident:

  - `fetch_current_user/2` for sessions with no `:current_user_id`, with a
    stale id that no longer maps to a row, and with a real user that has no
    open shift (covers the "current_shift assigned as nil" branches in the
    plug).
  - `on_mount(:ensure_on_shift, ...)` for the missing-scope and off-shift
    halts (covers the gates referenced by F.Today.2 / F.Profile.18 /
    F.Channels.18).
  - `on_mount(:mount_public, ...)` with a session containing a pre-built
    `%Scope{}` to exercise the isolated-test fallback clause of
    `load_scope/1`.

  Covers (plumbing-level coverage for security-sensitive branches):
    fetch_current_user/2     — nil session, stale user id, no-open-shift user
    on_mount/4               — :ensure_on_shift halt branches (nil scope and
                               off-shift), incl. the F.Today.2 / F.Profile.18
                               / F.Channels.18 redirect targets
    load_scope/1             — Accounts.get_user/1 -> nil branch and synthetic
                               `current_scope` session fallback
  """
  use Foyer.DataCase, async: true

  alias Foyer.Accounts.User
  alias FoyerWeb.Scope
  alias FoyerWeb.UserAuth
  alias Phoenix.LiveView.Socket

  import FoyerWeb.ScaffoldFixtures, only: [seed_scaffold!: 0]

  describe "fetch_current_user/2" do
    test "no current_user_id in session assigns nil current_user and current_shift" do
      conn =
        :get
        |> Plug.Test.conn("/")
        |> Plug.Test.init_test_session(%{})
        |> UserAuth.fetch_current_user([])

      assert conn.assigns.current_user == nil
      assert conn.assigns.current_shift == nil
    end

    test "stale current_user_id with no matching row assigns nil current_user and current_shift" do
      # Seed real data so the surrounding sandbox is exercised but pick an id
      # we know cannot match.
      _ = seed_scaffold!()

      conn =
        :get
        |> Plug.Test.conn("/")
        |> Plug.Test.init_test_session(%{current_user_id: -1})
        |> UserAuth.fetch_current_user([])

      assert conn.assigns.current_user == nil
      assert conn.assigns.current_shift == nil
    end

    test "valid user with no open shift assigns the user and a nil current_shift" do
      ctx = seed_scaffold!()
      # Jamal is the off-shift user in the scaffold seeds.
      jamal = ctx.jamal

      conn =
        :get
        |> Plug.Test.conn("/")
        |> Plug.Test.init_test_session(%{current_user_id: jamal.id})
        |> UserAuth.fetch_current_user([])

      assert %User{id: id} = conn.assigns.current_user
      assert id == jamal.id
      assert conn.assigns.current_shift == nil
    end
  end

  describe "on_mount(:ensure_on_shift, ...)" do
    test "with an empty session halts and redirects to / with a flash" do
      socket = build_socket()

      assert {:halt, socket} =
               UserAuth.on_mount(:ensure_on_shift, %{}, %{}, socket)

      assert {:redirect, %{to: "/"}} = socket.redirected
      assert socket.assigns.flash["error"] == "Please pick a user."
    end

    test "with a stale current_user_id (no row) halts and redirects to /" do
      # Routes load_scope through the :current_user_id clause and hits the
      # `Accounts.get_user/1 -> nil` arm, returning nil to the hook.
      _ = seed_scaffold!()
      session = %{"current_user_id" => -1}
      socket = build_socket()

      assert {:halt, socket} =
               UserAuth.on_mount(:ensure_on_shift, %{}, session, socket)

      assert {:redirect, %{to: "/"}} = socket.redirected
      assert socket.assigns.flash["error"] == "Please pick a user."
    end

    test "with an off-shift scope halts and redirects to /today with a flash" do
      scope = build_scope(on_shift?: false)
      session = %{"current_scope" => scope}
      socket = build_socket()

      assert {:halt, socket} =
               UserAuth.on_mount(:ensure_on_shift, %{}, session, socket)

      assert {:redirect, %{to: "/today"}} = socket.redirected
      assert socket.assigns.flash["info"] == "Start your shift to enter the rest of Foyer."
    end
  end

  describe "on_mount(:mount_public, ...) via the synthetic-test load_scope fallback" do
    test "a session with a pre-built %Scope{} is forwarded verbatim into current_scope" do
      scope = build_scope(on_shift?: true)
      session = %{"current_scope" => scope}
      socket = build_socket()

      assert {:cont, socket} =
               UserAuth.on_mount(:mount_public, %{}, session, socket)

      assert socket.assigns.current_scope == scope
    end
  end

  defp build_socket do
    %Socket{
      assigns: %{__changed__: %{}, flash: %{}},
      private: %{live_temp: %{}}
    }
  end

  defp build_scope(opts) do
    on_shift? = Keyword.fetch!(opts, :on_shift?)

    user = %User{
      id: 1,
      name: "Test User",
      initials: "TU",
      role: :staff,
      department: "Housekeeping",
      title: "Tester",
      languages: ["EN"],
      points_balance: 0
    }

    shift = if on_shift?, do: %Foyer.Shifts.Shift{user_id: user.id}, else: nil
    Scope.for_user(user, shift)
  end
end

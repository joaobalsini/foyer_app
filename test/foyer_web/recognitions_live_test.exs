defmodule FoyerWeb.RecognitionsLiveTest do
  @moduledoc """
  Isolated LiveView tests for `FoyerWeb.RecognitionsLive`. Each test pins an
  `F.Recognitions.<N>` clause it asserts. Route gates, on_mount hooks, and the
  database are out of scope here — see `smoke_test.exs` for the route wiring
  layer.

  Pattern: `live_isolated/3` + scenario modules via `Mox.stub_with/2`; inline
  `Mox.expect/3` when the test asserts on an exact call. Scope is injected
  through the isolated harness session and resolved by
  `FoyerWeb.UserAuth.load_scope/1` (which has a `"current_scope"` clause used
  only by `FoyerWeb.IsolatedHelpers`).

  The harness pre-populates `conn.private[:phoenix_live_view]` so the LV
  channel's session-route check (line 1645 of `Phoenix.LiveView.Channel`)
  finds the expected live_session and the connect succeeds. See
  `FoyerWeb.IsolatedHelpers` for the rationale.
  """
  use FoyerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Mox
  import FoyerWeb.IsolatedHelpers, only: [mount_isolated_recognitions: 2]

  alias Foyer.AccountsScenarios.WithPeople
  alias Foyer.Recognitions.Recognition
  alias Foyer.RecognitionsScenarios

  alias FoyerWeb.IsolatedHelpers

  setup :verify_on_exit!
  # The LiveView runs in its own pid; without `set_mox_from_context` Mox in
  # private mode would not let the LV see test-process stubs. This mirrors
  # `smoke_test.exs`.
  setup :set_mox_from_context

  setup %{conn: conn} do
    # Default Accounts stub — most tests need `list_people/1` for the `:new`/
    # `:edit` form. Tests that need a different shape override per-call.
    stub_with(Foyer.AccountsMock, WithPeople)
    {:ok, conn: conn}
  end

  # ---------------------------------------------------------------------------
  # F.Recognitions.1 — form renders for on-shift user
  # ---------------------------------------------------------------------------
  describe "F.Recognitions.1 — give form visibility" do
    test "on-shift staff sees the give-form on :new", %{conn: conn} do
      stub_with(Foyer.RecognitionsMock, RecognitionsScenarios.Empty)

      scope = IsolatedHelpers.build_scope(role: :staff, on_shift?: true)

      {:ok, view, _html} = mount_isolated_recognitions(conn, action: :new, scope: scope)

      assert has_element?(view, "form#recognize-form")
      assert has_element?(view, "button#recognize-submit", "Send recognition")
    end

    # Off-shift visibility is enforced by the router's `:ensure_on_shift`
    # on_mount hook — see the e2e `F.Recognitions.1` test in
    # `smoke_test.exs` for the matching wiring proof.
  end

  # ---------------------------------------------------------------------------
  # F.Recognitions.2 — self-recognition blocked at the form level
  # ---------------------------------------------------------------------------
  describe "F.Recognitions.2 — self-recognition rejected" do
    test "submitting with recipient = sender surfaces the self-recognition flash", %{conn: conn} do
      stub_with(Foyer.RecognitionsMock, RecognitionsScenarios.Empty)

      # `id: 2` is Hugo in `WithPeople` — so the select option for
      # `recipient_id` includes "2" and form validation passes through to
      # `give/2`, which is what we want to assert on.
      scope = IsolatedHelpers.build_scope(id: 2, role: :staff, on_shift?: true)

      expect(Foyer.RecognitionsMock, :give, fn _sender, attrs ->
        assert attrs["recipient_id"] == to_string(scope.user.id)
        {:error, :self_recognition}
      end)

      {:ok, view, _html} = mount_isolated_recognitions(conn, action: :new, scope: scope)

      view
      |> form("#recognize-form",
        recognition: %{
          "recipient_id" => to_string(scope.user.id),
          "body" => "Praise myself.",
          "values" => ["care"],
          "public" => "true"
        }
      )
      |> render_submit()

      assert render(view) =~ "Choose someone else to recognize."
    end
  end

  # ---------------------------------------------------------------------------
  # F.Recognitions.3 — the six house values appear as options
  # ---------------------------------------------------------------------------
  describe "F.Recognitions.3 — house values" do
    test "exactly the six required values render as checkboxes on :new", %{conn: conn} do
      stub_with(Foyer.RecognitionsMock, RecognitionsScenarios.Empty)

      scope = IsolatedHelpers.build_scope(role: :staff, on_shift?: true)

      {:ok, view, _html} = mount_isolated_recognitions(conn, action: :new, scope: scope)

      html = render(view)

      for v <- ~w(care craft warmth discretion initiative excellence) do
        assert has_element?(view, "input#value-#{v}"),
               "expected checkbox for house value #{v} on :new"

        assert html =~ String.capitalize(v)
      end

      refute has_element?(view, "input#value-team")
      refute html =~ ">Team<"
    end
  end

  describe "F.Recognitions form state" do
    test "selected recipient remains selected after choosing house values", %{conn: conn} do
      stub_with(Foyer.RecognitionsMock, RecognitionsScenarios.Empty)

      scope = IsolatedHelpers.build_scope(role: :staff, on_shift?: true)

      {:ok, view, _html} = mount_isolated_recognitions(conn, action: :new, scope: scope)

      view
      |> form("#recognize-form",
        recognition: %{
          "recipient_id" => "3",
          "values" => ["care"],
          "body" => "",
          "public" => "true"
        }
      )
      |> render_change()

      assert has_element?(
               view,
               "select#recognition-recipient option[value='3'][selected]",
               "Aisha Bello"
             )

      assert has_element?(view, "input#value-care[checked]")
      refute render(view) =~ ~s(data-value="")
    end
  end

  # ---------------------------------------------------------------------------
  # F.Recognitions.4 — at-least-one-value validation surfaces an error
  # ---------------------------------------------------------------------------
  describe "F.Recognitions.4 — values required" do
    test "submitting with empty values flashes a generic validation error", %{conn: conn} do
      stub_with(Foyer.RecognitionsMock, RecognitionsScenarios.Empty)

      scope = IsolatedHelpers.build_scope(role: :staff, on_shift?: true)

      expect(Foyer.RecognitionsMock, :give, fn _sender, attrs ->
        # The hidden empty value lets Phoenix submit an empty checkbox group;
        # the context normalizes it to [] before validation.
        assert attrs["values"] == [""]

        # The context returns a changeset error. The LV's catch-all
        # `{:error, _changeset}` clause flashes a generic copy.
        {:error,
         Recognition.changeset(%Recognition{}, attrs)
         |> Ecto.Changeset.add_error(:values, "choose at least one value")}
      end)

      {:ok, view, _html} = mount_isolated_recognitions(conn, action: :new, scope: scope)

      view
      |> form("#recognize-form",
        recognition: %{
          "recipient_id" => "1",
          "body" => "Thanks.",
          "public" => "true"
        }
      )
      |> render_submit()

      assert render(view) =~ "Couldn&#39;t send recognition."
    end
  end

  # ---------------------------------------------------------------------------
  # F.Recognitions.5 — bonus-points UI shows only to managers
  # ---------------------------------------------------------------------------
  describe "F.Recognitions.5 — bonus points visibility" do
    test "staff does NOT see the bonus-points fieldset", %{conn: conn} do
      stub_with(Foyer.RecognitionsMock, RecognitionsScenarios.Empty)

      scope = IsolatedHelpers.build_scope(role: :staff, on_shift?: true)

      {:ok, view, _html} = mount_isolated_recognitions(conn, action: :new, scope: scope)

      refute has_element?(view, "#bonus-points-fieldset")
      refute has_element?(view, "#bonus-tiers")
    end

    test "manager sees the bonus-points fieldset", %{conn: conn} do
      stub_with(Foyer.RecognitionsMock, RecognitionsScenarios.Empty)

      scope = IsolatedHelpers.build_scope(role: :manager, on_shift?: true)

      {:ok, view, _html} = mount_isolated_recognitions(conn, action: :new, scope: scope)

      assert has_element?(view, "#bonus-points-fieldset")
      assert has_element?(view, "#bonus-tiers")
    end
  end

  # ---------------------------------------------------------------------------
  # F.Recognitions.6 — tier dropdown lists exactly 0/10/25/50/100
  # ---------------------------------------------------------------------------
  describe "F.Recognitions.6 — bonus point tiers" do
    test "manager sees exactly the 0/10/25/50/100 tiers and no others", %{conn: conn} do
      stub_with(Foyer.RecognitionsMock, RecognitionsScenarios.Empty)

      scope = IsolatedHelpers.build_scope(role: :manager, on_shift?: true)

      {:ok, view, _html} = mount_isolated_recognitions(conn, action: :new, scope: scope)

      for pts <- [0, 10, 25, 50, 100] do
        assert has_element?(view, "input#bonus-#{pts}"),
               "expected bonus-tier radio for #{pts}"
      end

      for pts <- [5, 15, 20, 75, 200] do
        refute has_element?(view, "input#bonus-#{pts}"),
               "did not expect bonus-tier radio for #{pts}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # F.Recognitions.9 — Edit / Remove affordance within and outside grace
  # ---------------------------------------------------------------------------
  describe "F.Recognitions.9 — author affordances within grace window" do
    test "author sees Edit link and Remove button within grace window", %{conn: conn} do
      scope = IsolatedHelpers.build_scope(id: 42, role: :staff, on_shift?: true)
      recognition = build_recognition(id: 8001, sender_id: 42, recipient_id: 7)

      # `get_recognition!/2` is called twice — once in the dead render (test
      # process) and once in the connected mount (LV process). `stub/3` is
      # the right shape for "any number of calls, fixed return."
      Foyer.RecognitionsMock
      |> stub(:get_recognition!, fn _id, _viewer -> recognition end)
      |> stub(:within_grace_window?, fn _ -> true end)

      {:ok, view, _html} =
        mount_isolated_recognitions(conn,
          action: :show,
          scope: scope,
          path: "/recognitions/#{recognition.id}",
          params: %{"id" => to_string(recognition.id)}
        )

      assert has_element?(view, "a#recognition-edit-link", "Edit")
      assert has_element?(view, "button#recognition-remove-btn", "Remove")
    end

    test "author sees Edit link but NO Remove button outside grace window", %{conn: conn} do
      scope = IsolatedHelpers.build_scope(id: 42, role: :staff, on_shift?: true)
      recognition = build_recognition(id: 8002, sender_id: 42, recipient_id: 7)

      Foyer.RecognitionsMock
      |> stub(:get_recognition!, fn _id, _viewer -> recognition end)
      |> stub(:within_grace_window?, fn _ -> false end)

      {:ok, view, _html} =
        mount_isolated_recognitions(conn,
          action: :show,
          scope: scope,
          path: "/recognitions/#{recognition.id}",
          params: %{"id" => to_string(recognition.id)}
        )

      assert has_element?(view, "a#recognition-edit-link", "Edit")
      refute has_element?(view, "button#recognition-remove-btn")
    end
  end

  # ---------------------------------------------------------------------------
  # F.Recognitions.10 — private rendering masks third-party viewers
  # ---------------------------------------------------------------------------
  describe "F.Recognitions.10 — privacy on :show" do
    test "third-party viewer is redirected when get_recognition! raises NoResultsError",
         %{conn: conn} do
      scope = IsolatedHelpers.build_scope(id: 999, role: :staff, on_shift?: true)

      # Same dead-render+connected-mount double call as F.Recognitions.9 —
      # both call sites must raise so the LV redirects in both contexts.
      stub(Foyer.RecognitionsMock, :get_recognition!, fn _id, _viewer ->
        raise Ecto.NoResultsError, queryable: Recognition
      end)

      # apply_show/2 rescues the NoResultsError and push_navigates to
      # /recognitions. live_isolated returns the redirect tuple at mount-time.
      assert {:error, {:live_redirect, %{to: "/recognitions"}}} =
               mount_isolated_recognitions(conn,
                 action: :show,
                 scope: scope,
                 path: "/recognitions/12345",
                 params: %{"id" => "12345"}
               )
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp build_recognition(opts) do
    sender_id = Keyword.fetch!(opts, :sender_id)
    recipient_id = Keyword.fetch!(opts, :recipient_id)

    %Recognition{
      id: Keyword.get(opts, :id, 8001),
      sender_id: sender_id,
      recipient_id: recipient_id,
      body: "Held the floor together.",
      values: ["care"],
      bonus_points: 0,
      public: true,
      inserted_at: ~U[2026-05-25 06:00:00Z],
      sender: %Foyer.Accounts.User{
        id: sender_id,
        name: "Author #{sender_id}",
        initials: "AU",
        role: :staff
      },
      recipient: %Foyer.Accounts.User{
        id: recipient_id,
        name: "Recipient #{recipient_id}",
        initials: "RE",
        role: :staff
      }
    }
  end
end

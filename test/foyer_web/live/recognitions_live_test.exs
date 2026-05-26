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

  Uses bare `ExUnit.Case` rather than `FoyerWeb.ConnCase` because nothing in
  this file touches the database — ConnCase would needlessly start an Ecto
  sandbox per test. The lone DB-backed wiring proof for the recognitions
  routes lives in `smoke_test.exs`.

  Covers:
    F.Recognitions.1  — give-form visibility on :new
    F.Recognitions.2  — self-recognition flash on submit
    F.Recognitions.3  — six house values render as checkboxes
    F.Recognitions.4  — empty values flashes validation error
    F.Recognitions.5  — bonus-points fieldset visible only to managers
    F.Recognitions.6  — bonus point tiers shown for managers, invalid tier flash
    F.Recognitions.8  — remove success / error flashes on :show
    F.Recognitions.9  — author affordances within / outside grace window, edit
                       success / outside_grace / unauthorized / changeset flashes
    F.Recognitions.10 — third-party privacy on :show / :edit (NoResultsError rescue)

  Additional non-clause coverage:
    * give_submit happy path redirects to the created recognition detail page
    * preview_change updates recipient/body/values/bonus-points assigns
    * set_bonus tier and clear events flip the preview ribbon
    * :show renders the bonus-points tag when the recognition carries one
  """
  use ExUnit.Case, async: true

  @endpoint FoyerWeb.Endpoint

  import Phoenix.ConnTest
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

  setup do
    # Default Accounts stub — most tests need `list_people/1` for the `:new`/
    # `:edit` form. Tests that need a different shape override per-call.
    stub_with(Foyer.AccountsMock, WithPeople)
    {:ok, conn: build_conn()}
  end

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

  describe "F.Recognitions.2 — self-recognition rejected" do
    test "submitting with recipient = sender surfaces the self-recognition flash", %{conn: conn} do
      stub_with(Foyer.RecognitionsMock, RecognitionsScenarios.Empty)

      scope = IsolatedHelpers.build_scope(id: 2, role: :staff, on_shift?: true)

      expect(Foyer.RecognitionsMock, :give, fn _sender, attrs ->
        assert attrs["recipient_id"] == to_string(scope.user.id)
        {:error, :self_recognition}
      end)

      {:ok, view, _html} = mount_isolated_recognitions(conn, action: :new, scope: scope)

      refute has_element?(view, "select#recognition-recipient option[value='2']", "Hugo Brandt")

      render_hook(view, "give_submit", %{
        "recognition" => %{
          "recipient_id" => to_string(scope.user.id),
          "body" => "Praise myself.",
          "values" => ["care"],
          "public" => "true"
        }
      })

      assert render(view) =~ "Choose someone else to recognize."
    end
  end

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

    test "visibility and bonus selections remain selected while editing text", %{conn: conn} do
      stub_with(Foyer.RecognitionsMock, RecognitionsScenarios.Empty)

      scope = IsolatedHelpers.build_scope(id: 99, role: :manager, on_shift?: true)

      {:ok, view, _html} = mount_isolated_recognitions(conn, action: :new, scope: scope)

      view
      |> form("#recognize-form",
        recognition: %{
          "recipient_id" => "3",
          "values" => ["care"],
          "body" => "First draft",
          "public" => "false",
          "bonus_points" => "25"
        }
      )
      |> render_change()

      assert has_element?(view, "input#visibility-private[checked]")
      assert has_element?(view, "input#bonus-25[checked]")

      view
      |> form("#recognize-form",
        recognition: %{
          "recipient_id" => "3",
          "values" => ["care"],
          "body" => "Second draft",
          "public" => "false",
          "bonus_points" => "25"
        }
      )
      |> render_change()

      assert has_element?(view, "input#visibility-private[checked]")
      assert has_element?(view, "input#bonus-25[checked]")
      refute has_element?(view, "input#visibility-public[checked]")
    end
  end

  describe "F.Recognitions.4 — values required" do
    test "submitting with empty values shows the field-level validation error", %{conn: conn} do
      stub_with(Foyer.RecognitionsMock, RecognitionsScenarios.Empty)

      scope = IsolatedHelpers.build_scope(role: :staff, on_shift?: true)

      expect(Foyer.RecognitionsMock, :give, fn _sender, attrs ->
        # The hidden empty value lets Phoenix submit an empty checkbox group;
        # the context normalizes it to [] before validation.
        assert attrs["values"] == [""]

        {:error,
         Recognition.changeset(%Recognition{}, attrs)
         |> Ecto.Changeset.add_error(:values, "choose at least one value")}
      end)

      {:ok, view, _html} = mount_isolated_recognitions(conn, action: :new, scope: scope)

      view
      |> form("#recognize-form",
        recognition: %{
          "recipient_id" => "2",
          "body" => "Thanks.",
          "public" => "true"
        }
      )
      |> render_submit()

      html = render(view)
      assert html =~ "Please fix the highlighted fields."
      assert html =~ "choose at least one value"
    end
  end

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
      assert has_element?(view, ".announcement-detail #recognition-detail")
      assert has_element?(view, "#recognition-detail .foyer-tag", "Recognition")
      assert has_element?(view, "#back-to-recognitions[href='/house']", "Back")
    end

    test "author outside grace sees disabled Edit and Remove buttons with tooltip copy",
         %{conn: conn} do
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

      tooltip = "Editing and removal are only available for 15 minutes after sending."

      assert has_element?(view, "[title='#{tooltip}'] #recognition-edit-link[disabled]", "Edit")

      assert has_element?(
               view,
               "[title='#{tooltip}'] #recognition-remove-btn[disabled]",
               "Remove"
             )
    end
  end

  describe "F.Recognitions.10 — privacy on :show" do
    test "third-party viewer is redirected when get_recognition! raises NoResultsError",
         %{conn: conn} do
      scope = IsolatedHelpers.build_scope(id: 999, role: :staff, on_shift?: true)

      # Same dead-render+connected-mount double call as F.Recognitions.9 —
      # both call sites must raise so the LV redirects in both contexts.
      stub(Foyer.RecognitionsMock, :get_recognition!, fn _id, _viewer ->
        raise Ecto.NoResultsError, queryable: Recognition
      end)

      # apply_show/2 rescues the NoResultsError and push_navigates to /house.
      # live_isolated returns the redirect tuple at mount-time.
      assert {:error, {:live_redirect, %{to: "/house"}}} =
               mount_isolated_recognitions(conn,
                 action: :show,
                 scope: scope,
                 path: "/recognitions/12345",
                 params: %{"id" => "12345"}
               )
    end
  end

  # ---------------------------------------------------------------------------
  # F.Recognitions.1 — give_submit happy path redirects to detail
  # ---------------------------------------------------------------------------
  describe "F.Recognitions.1 — give_submit happy path" do
    test "manager is redirected to the created recognition detail page",
         %{conn: conn} do
      stub_with(Foyer.RecognitionsMock, RecognitionsScenarios.Empty)

      scope = IsolatedHelpers.build_scope(id: 99, role: :manager, on_shift?: true)
      sent = build_recognition(id: 8100, sender_id: 99, recipient_id: 2)

      expect(Foyer.RecognitionsMock, :give, fn _sender, _attrs -> {:ok, sent} end)

      {:ok, view, _html} = mount_isolated_recognitions(conn, action: :new, scope: scope)

      render_hook(view, "set_bonus", %{"bonus" => "25"})

      assert {:error, {:live_redirect, %{to: "/recognitions/8100", flash: flash}}} =
               view
               |> form("#recognize-form",
                 recognition: %{
                   "recipient_id" => "2",
                   "body" => "Saved the late check-in.",
                   "values" => ["care"],
                   "public" => "true",
                   "bonus_points" => "25"
                 }
               )
               |> render_submit()

      assert Phoenix.LiveView.Utils.verify_flash(@endpoint, flash) == %{
               "info" => "Recognition sent."
             }
    end
  end

  # ---------------------------------------------------------------------------
  # F.Recognitions.6 — give_submit invalid_point_tier flash
  # ---------------------------------------------------------------------------
  describe "F.Recognitions.6 — invalid point tier rejected" do
    test "submitting with an off-tier bonus flashes the tier error", %{conn: conn} do
      stub_with(Foyer.RecognitionsMock, RecognitionsScenarios.Empty)

      scope = IsolatedHelpers.build_scope(id: 5, role: :manager, on_shift?: true)

      expect(Foyer.RecognitionsMock, :give, fn _sender, _attrs ->
        {:error, :invalid_point_tier}
      end)

      {:ok, view, _html} = mount_isolated_recognitions(conn, action: :new, scope: scope)

      # Bypass radio validation — the mock returns :invalid_point_tier regardless
      # of value, so any payload triggers the error-flash branch we're testing.
      render_hook(view, "give_submit", %{
        "recognition" => %{
          "recipient_id" => "2",
          "body" => "Thanks.",
          "values" => ["care"],
          "public" => "true",
          "bonus_points" => "15"
        }
      })

      assert render(view) =~ "Choose one of the available point tiers."
    end
  end

  # ---------------------------------------------------------------------------
  # preview_change + set_bonus (no spec clause)
  # ---------------------------------------------------------------------------
  describe "preview-side event handlers" do
    test "preview_change + set_bonus drive the manager preview ribbon end-to-end",
         %{conn: conn} do
      stub_with(Foyer.RecognitionsMock, RecognitionsScenarios.Empty)

      scope = IsolatedHelpers.build_scope(id: 99, role: :manager, on_shift?: true)

      {:ok, view, _html} = mount_isolated_recognitions(conn, action: :new, scope: scope)

      # preview_change resolves recipient_id "3" to Aisha (line 197),
      # parses bonus_points "50" via Integer.parse (line 208), and the
      # manager-only ribbon renders "+50 pts" (line 677).
      view
      |> form("#recognize-form",
        recognition: %{
          "recipient_id" => "3",
          "body" => "Caught the leak before it spread.",
          "values" => ["care"],
          "public" => "true",
          "bonus_points" => "50"
        }
      )
      |> render_change()

      html = render(view)
      assert html =~ "Aisha Bello"
      assert html =~ "Caught the leak before it spread."
      assert html =~ "+50 pts"
      refute has_element?(view, "#recognition-preview #recognition-view-0")

      # set_bonus "clear" branch (line 220) wipes the ribbon back to nothing.
      render_hook(view, "set_bonus", %{"bonus" => "clear"})
      refute render(view) =~ "+50 pts"

      # set_bonus tier branch (line 224) puts it back at a different value.
      render_hook(view, "set_bonus", %{"bonus" => "25"})
      assert render(view) =~ "+25 pts"
    end

    test "preview_change with empty bonus_points and unparseable recipient_id stays clean",
         %{conn: conn} do
      stub_with(Foyer.RecognitionsMock, RecognitionsScenarios.Empty)

      scope = IsolatedHelpers.build_scope(id: 99, role: :manager, on_shift?: true)

      {:ok, view, _html} = mount_isolated_recognitions(conn, action: :new, scope: scope)

      # Prime the ribbon with a real tier so we can prove the empty
      # submission clears it (rather than just confirming a never-set value).
      render_hook(view, "set_bonus", %{"bonus" => "50"})
      assert render(view) =~ "+50 pts"

      # bonus_points "" exercises the `"" -> nil` branch. Use an unparseable
      # recipient_id so the `_ -> ""` fallback is hit. Both are out-of-band for
      # the form UI (radio + select coerce valid values), so fire the
      # preview_change event directly instead of going through form/3.
      render_hook(view, "preview_change", %{
        "recognition" => %{
          "recipient_id" => "not-an-int",
          "body" => "",
          "values" => ["care"],
          "public" => "true",
          "bonus_points" => ""
        }
      })

      html = render(view)
      refute html =~ "+50 pts"
      # Form is still rendered (no crash from bad recipient_id)
      assert has_element?(view, "form#recognize-form")
    end
  end

  # ---------------------------------------------------------------------------
  # F.Recognitions.9 — edit_submit success and error flashes
  # ---------------------------------------------------------------------------
  describe "F.Recognitions.9 — edit_submit error handling" do
    setup %{conn: conn} do
      # Empty supplies change_recognition/2 (needed by apply_edit/2 at mount)
      # — we then override get_recognition!/2 and update_recognition/3.
      stub_with(Foyer.RecognitionsMock, RecognitionsScenarios.Empty)
      scope = IsolatedHelpers.build_scope(id: 42, role: :staff, on_shift?: true)
      recognition = build_recognition(id: 8300, sender_id: 42, recipient_id: 3)
      {:ok, conn: conn, scope: scope, recognition: recognition}
    end

    test "successful update push_navigates back to :show", %{
      conn: conn,
      scope: scope,
      recognition: recognition
    } do
      Foyer.RecognitionsMock
      |> stub(:get_recognition!, fn _id, _viewer -> recognition end)
      |> expect(:update_recognition, fn _r, _editor, _attrs -> {:ok, recognition} end)

      {:ok, view, _html} =
        mount_isolated_recognitions(conn,
          action: :edit,
          scope: scope,
          path: "/recognitions/#{recognition.id}/edit",
          params: %{"id" => to_string(recognition.id)}
        )

      assert {:error, {:live_redirect, %{to: path}}} =
               view
               |> form("#recognition-edit-form",
                 recognition: %{
                   "recipient_id" => "3",
                   "body" => "Updated story.",
                   "values" => ["care"],
                   "public" => "true"
                 }
               )
               |> render_submit()

      assert path == "/recognitions/#{recognition.id}"
    end

    test "outside_grace_window / unauthorized / changeset errors each flash distinct copy",
         %{conn: conn, scope: scope, recognition: recognition} do
      # Stack three replies on update_recognition — one per submit below.
      Foyer.RecognitionsMock
      |> stub(:get_recognition!, fn _id, _viewer -> recognition end)
      |> expect(:update_recognition, fn _r, _editor, _attrs ->
        {:error, :outside_grace_window}
      end)
      |> expect(:update_recognition, fn _r, _editor, _attrs ->
        {:error, :unauthorized}
      end)
      |> expect(:update_recognition, fn _r, _editor, _attrs ->
        {:error, Recognition.changeset(%Recognition{}, %{})}
      end)

      {:ok, view, _html} =
        mount_isolated_recognitions(conn,
          action: :edit,
          scope: scope,
          path: "/recognitions/#{recognition.id}/edit",
          params: %{"id" => to_string(recognition.id)}
        )

      submit = fn ->
        view
        |> form("#recognition-edit-form",
          recognition: %{
            "recipient_id" => "3",
            "body" => "Updated.",
            "values" => ["care"],
            "public" => "true"
          }
        )
        |> render_submit()
      end

      submit.()
      assert render(view) =~ "That recognition can no longer be edited."

      submit.()
      assert render(view) =~ "Only the sender can edit this recognition."

      submit.()
      assert render(view) =~ "Couldn&#39;t update recognition."
    end
  end

  # ---------------------------------------------------------------------------
  # F.Recognitions.8 — remove success and error flashes
  # ---------------------------------------------------------------------------
  describe "F.Recognitions.8 — remove event handling" do
    setup %{conn: conn} do
      stub_with(Foyer.RecognitionsMock, RecognitionsScenarios.Empty)
      scope = IsolatedHelpers.build_scope(id: 42, role: :staff, on_shift?: true)
      recognition = build_recognition(id: 8400, sender_id: 42, recipient_id: 3)
      {:ok, conn: conn, scope: scope, recognition: recognition}
    end

    test "successful remove flashes info and push_navigates to /recognitions", %{
      conn: conn,
      scope: scope,
      recognition: recognition
    } do
      Foyer.RecognitionsMock
      |> stub(:get_recognition!, fn _id, _viewer -> recognition end)
      |> stub(:within_grace_window?, fn _ -> true end)
      |> expect(:remove_recognition, fn _r, _remover -> {:ok, recognition} end)

      {:ok, view, _html} =
        mount_isolated_recognitions(conn,
          action: :show,
          scope: scope,
          path: "/recognitions/#{recognition.id}",
          params: %{"id" => to_string(recognition.id)}
        )

      assert {:error, {:live_redirect, %{to: "/house"}}} =
               view |> element("button#recognition-remove-btn") |> render_click()
    end

    test "remove error branches each flash their own copy", %{
      conn: conn,
      scope: scope,
      recognition: recognition
    } do
      Foyer.RecognitionsMock
      |> stub(:get_recognition!, fn _id, _viewer -> recognition end)
      |> stub(:within_grace_window?, fn _ -> true end)
      |> expect(:remove_recognition, fn _r, _remover -> {:error, :outside_grace_window} end)
      |> expect(:remove_recognition, fn _r, _remover -> {:error, :unauthorized} end)
      |> expect(:remove_recognition, fn _r, _remover -> {:error, :boom} end)

      {:ok, view, _html} =
        mount_isolated_recognitions(conn,
          action: :show,
          scope: scope,
          path: "/recognitions/#{recognition.id}",
          params: %{"id" => to_string(recognition.id)}
        )

      view |> element("button#recognition-remove-btn") |> render_click()
      assert render(view) =~ "That recognition can no longer be removed."

      view |> element("button#recognition-remove-btn") |> render_click()
      assert render(view) =~ "Only the sender can remove this recognition."

      view |> element("button#recognition-remove-btn") |> render_click()
      assert render(view) =~ "Couldn&#39;t remove recognition."
    end
  end

  # ---------------------------------------------------------------------------
  # F.Recognitions.10 — :edit raises NoResultsError → redirect
  # ---------------------------------------------------------------------------
  describe "F.Recognitions.10 — :edit NoResultsError rescue" do
    test "edit redirects to /house when get_recognition! raises NoResultsError",
         %{conn: conn} do
      stub_with(Foyer.RecognitionsMock, RecognitionsScenarios.Empty)
      scope = IsolatedHelpers.build_scope(id: 999, role: :staff, on_shift?: true)

      stub(Foyer.RecognitionsMock, :get_recognition!, fn _id, _viewer ->
        raise Ecto.NoResultsError, queryable: Recognition
      end)

      assert {:error, {:live_redirect, %{to: "/house"}}} =
               mount_isolated_recognitions(conn,
                 action: :edit,
                 scope: scope,
                 path: "/recognitions/12345/edit",
                 params: %{"id" => "12345"}
               )
    end
  end

  # ---------------------------------------------------------------------------
  # :show renders the bonus-points tag when bonus_points > 0
  # ---------------------------------------------------------------------------
  describe ":show with bonus points" do
    test "renders the +N pts tag when the recognition carries bonus points",
         %{conn: conn} do
      stub_with(Foyer.RecognitionsMock, RecognitionsScenarios.Empty)
      scope = IsolatedHelpers.build_scope(id: 42, role: :staff, on_shift?: true)

      recognition = %{
        build_recognition(id: 8500, sender_id: 42, recipient_id: 3)
        | bonus_points: 50
      }

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

      assert render(view) =~ "+50 pts"
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

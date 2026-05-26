defmodule Foyer.Profile do
  @moduledoc """
  Read-only profile orchestrator. Wraps Accounts + Recognitions + Shifts and
  returns a typed `Foyer.Profile.Card`. Keeps `FoyerWeb.ProfileLive` slim per
  "fat contexts, slim LiveViews".

  Privacy boundary (F.Profile.6): `profile_for/2` enforces visibility at the
  context level. When the viewer is not the subject, private recognitions are
  stripped from `received` and `given` is cleared. Callers must not implement
  their own post-hoc filter — the rule lives here.

  NOTE: `received_this_month` counts against UTC month boundaries in v1. A future
  iteration may pass the property timezone via runtime config.
  """
  @behaviour Foyer.ProfilePort

  alias Foyer.Accounts.User
  alias Foyer.Profile.Card
  alias Foyer.Profile.RewardItem
  alias Foyer.Recognitions
  alias Foyer.Shifts

  # Rewards catalog — hard-coded module constant (non-redeemable in v1).
  # See docs/feature-groups/profile/plans/01-profile.md §7 for the rationale.
  # Heroicon names are used per project icon guidance (no Unicode glyphs).
  @rewards_catalog [
    %RewardItem{
      icon: "hero-sparkles",
      title: "Staff meal at the Cellar Chef's tasting",
      description: "Any Tuesday",
      cost: 75
    },
    %RewardItem{
      icon: "hero-clock",
      title: "1 hour early dismissal",
      description: "Banked, redeemable any shift",
      cost: 100
    },
    %RewardItem{
      icon: "hero-heart",
      title: "Spa treatment",
      description: "60-min massage or facial",
      cost: 200
    },
    %RewardItem{
      icon: "hero-gift",
      title: "Donate to the staff fund",
      description: "Supports colleagues in need",
      cost: 100
    },
    %RewardItem{
      icon: "hero-sun",
      title: "One extra paid day off",
      description: "Use within six months",
      cost: 400
    },
    %RewardItem{
      icon: "hero-building-office",
      title: "A night at a sister property",
      description: "Linden Group · Europe",
      cost: 900
    }
  ]

  @doc """
  Viewer-aware profile builder. Enforces F.Profile.6 at the context boundary.

  When `subject` and `viewer` are the same user, all recognitions (including
  private) are returned and `given` is populated — own-profile view.

  When `viewer` is a different user, private recognitions are stripped from
  `received` and `given` is cleared. The LiveView must NOT apply additional
  post-hoc filters; the privacy rule lives here.

  # TODO: consider a single joined query for received + given when the
  # recognition list grows (currently two separate DB queries — fine for POC).
  """
  @impl true
  @spec profile_for(User.t(), User.t(), keyword()) :: Card.t()
  def profile_for(subject, viewer, opts \\ [])

  def profile_for(%User{id: id} = subject, %User{id: id} = viewer, opts) do
    # Same user — own-profile view. All recognitions visible.
    build_card(subject, viewer, opts)
  end

  def profile_for(%User{} = subject, %User{} = viewer, opts) do
    # Colleague view. Privacy boundary (F.Profile.6, F.Profile.23):
    # Strip private recognitions at the context boundary — the recipient is the
    # only one who sees private recognitions (own-profile path above handles
    # that case). received_by/2 may include private ones where viewer is the
    # sender, so we enforce the rule here. The given list is cleared (F.Profile.8).
    card = build_card(subject, viewer, opts)
    %{card | received: Enum.filter(card.received, & &1.public), given: []}
  end

  @doc """
  Convenience wrapper for `ProfileLive` (`/me` path).
  Equivalent to `profile_for(user, user)` — returns all recognitions.
  """
  @impl true
  @spec own_profile_for(User.t(), keyword()) :: Card.t()
  def own_profile_for(%User{} = user, opts \\ []), do: build_card(user, user, opts)

  @doc """
  Returns the static rewards catalog. Module constant — no DB query.
  Exposed via the port so LiveView tests can swap in a controlled list.
  """
  @impl true
  @spec rewards_catalog() :: [RewardItem.t()]
  def rewards_catalog, do: @rewards_catalog

  @spec build_card(User.t(), User.t(), keyword()) :: Card.t()
  defp build_card(%User{} = subject, %User{} = viewer, opts) do
    # Pass viewer so Recognitions returns the correct visibility-filtered set.
    # For own-profile, subject == viewer so all records (incl. private) come through.
    received_by = Keyword.get(opts, :received_by, &Recognitions.received_by/2)
    given_by = Keyword.get(opts, :given_by, &Recognitions.given_by/2)
    current_shift_for = Keyword.get(opts, :current_shift_for, &Shifts.current_shift_for/1)

    received = received_by.(subject, viewer)
    given = given_by.(subject, viewer)
    today = Date.utc_today()

    %Card{
      user: subject,
      received: received,
      given: given,
      points: subject.points_balance || 0,
      on_shift?: not is_nil(current_shift_for.(subject)),
      received_this_month: count_this_month(received, today),
      points_earned: Enum.filter(received, &(is_integer(&1.bonus_points) and &1.bonus_points > 0))
    }
  end

  # Accepts an explicit Date so tests are deterministic and not sensitive to
  # month boundaries or UTC timezone. v1 uses UTC; a future iteration may pass
  # the property timezone from runtime config.
  @spec count_this_month([Foyer.Recognitions.Recognition.t()], Date.t()) :: integer()
  defp count_this_month(recognitions, %Date{year: year, month: month}) do
    Enum.count(recognitions, fn r ->
      date = DateTime.to_date(r.inserted_at)
      date.year == year and date.month == month
    end)
  end
end

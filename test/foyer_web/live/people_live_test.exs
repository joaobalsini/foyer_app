defmodule FoyerWeb.PeopleLiveTest do
  @moduledoc """
  Structural tests for `FoyerWeb.PeopleLive`. Covers spec clauses that can be
  verified without mounting the LiveView or hitting the database:

  - F.Channels.22 (partial) — Profile.Card must NOT have a :memberships field.

  Behavioral tests (F.Channels.15–18, F.Channels.21, F.Channels.22 e2e) are in
  `people_live_route_test.exs` which uses the real router and database, since
  `PeopleLive` implements `handle_params/3` and Phoenix LiveView 1.1.30 requires
  it to be mounted via router for handle_params to run (live_isolated/3 without
  `router:` raises ArgumentError; with `router:` the :ensure_on_shift on_mount
  hook redirects unauthenticated sessions).
  """
  use ExUnit.Case, async: true

  # ---------------------------------------------------------------------------
  # F.Channels.22 — Profile.Card does NOT expose channel memberships
  # ---------------------------------------------------------------------------

  describe "F.Channels.22 — channel memberships are NOT sourced from Profile.Card" do
    test "Foyer.Profile.Card struct has no :memberships field" do
      card_fields =
        Map.keys(%Foyer.Profile.Card{
          user: %Foyer.Accounts.User{
            name: "x",
            initials: "X",
            role: :staff,
            department: "X",
            title: "X"
          },
          received: [],
          given: [],
          points: 0,
          on_shift?: false
        })

      refute :memberships in card_fields,
             "Profile.Card must NOT have a :memberships field — channel memberships " <>
               "belong to PeopleLive :target_channels (F.Channels.22)"
    end
  end
end

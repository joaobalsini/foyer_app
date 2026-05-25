defmodule Foyer.Profile.Card do
  @moduledoc """
  Read-model returned by `Foyer.Profile.profile_for/2` or
  `Foyer.Profile.own_profile_for/1`. The shape consumed by `FoyerWeb.ProfileLive`
  and `FoyerWeb.PeopleLive :show`. Typed DTO (per ARCHITECTURE.md "no bare maps").

  Fields:
  - `received_this_month` — count of received recognitions in the current calendar
    month, computed in `Foyer.Profile.build_card/2` from `received`. Uses UTC
    day boundaries in v1; a future iteration may use the property timezone.
  - `points_earned` — subset of `received` where `bonus_points > 0`. Illustrative
    bonus-point breakdown only — does NOT reconcile with `points_balance`.
  """
  use TypedStruct

  alias Foyer.Accounts.User
  alias Foyer.Recognitions.Recognition

  typedstruct enforce: true do
    field :user, User.t()
    field :received, [Recognition.t()]
    field :given, [Recognition.t()]
    field :points, integer()
    field :on_shift?, boolean()
    field :received_this_month, integer()
    field :points_earned, [Recognition.t()]
  end
end

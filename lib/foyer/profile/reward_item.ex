defmodule Foyer.Profile.RewardItem do
  @moduledoc """
  A single item in the Foyer rewards catalog. Non-redeemable in v1 — the
  catalog is illustrative only. See `Foyer.Profile.rewards_catalog/0` for
  the full list. `icon` is a Heroicon name rendered with `<.icon name={item.icon} />`.
  """
  use TypedStruct

  typedstruct enforce: true do
    field :title, String.t()
    field :description, String.t()
    field :cost, non_neg_integer()
    field :icon, String.t()
  end
end

defmodule Foyer.Profile.Card do
  @moduledoc """
  Read-model returned by `Foyer.Profile.profile_for/2`. The shape consumed by
  `FoyerWeb.ProfileLive`. Typed DTO (per ARCHITECTURE.md "no bare maps").
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
  end
end

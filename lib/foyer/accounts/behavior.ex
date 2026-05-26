defmodule Foyer.Accounts.Behavior do
  @moduledoc """
  Behaviour for `Foyer.Accounts`. LiveViews call accounts through
  `FoyerWeb.LiveDeps.accounts/0`, which resolves to either the real context or
  a Mox mock per environment. See `docs/TESTING_GUIDE.md`.
  """

  alias Foyer.Accounts.User

  @callback list_pickable_users() :: [User.t()]
  @callback get_user!(integer() | String.t()) :: User.t()
  @callback get_user(integer() | String.t()) :: User.t() | nil
  @callback list_people(opts :: keyword()) :: [User.t()]
end

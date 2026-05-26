defmodule Foyer.Accounts.Behavior do
  @moduledoc """
  Behaviour for `Foyer.Accounts`. LiveViews call accounts through
  `FoyerWeb.LiveDeps.accounts/0`, which resolves to either the real context or
  a Mox mock per environment. See `docs/TESTING_GUIDE.md`.
  """

  alias Foyer.Accounts.User

  @doc """
  Returns users that can be selected from the development/session picker.
  """
  @callback list_pickable_users() :: [User.t()]

  @doc """
  Looks up a user by id.

  Accepts integer ids or string ids. Returns `nil` when a string id is
  malformed or when no user exists.
  """
  @callback get_user(integer() | String.t()) :: User.t() | nil

  @doc """
  Returns people for the directory, optionally filtered by supported options
  such as `:channel_id`.

  Supported options:

    * `:channel_id` - channel id as an integer or string; when present, only
      users with a membership in that channel are returned.
  """
  @callback list_people(opts :: keyword()) :: [User.t()]
end

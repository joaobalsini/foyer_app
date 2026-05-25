defmodule Foyer.ChannelsPort do
  @moduledoc """
  Behaviour for `Foyer.Channels`.
  """

  alias Foyer.Accounts.User
  alias Foyer.Channels.Channel

  @callback list_for_user(User.t()) :: [Channel.t()]
  @callback list_all_with_member_counts() :: [{Channel.t(), non_neg_integer()}]
  @callback get!(integer() | String.t()) :: Channel.t()
  @callback member?(User.t(), Channel.t()) :: boolean()
  @callback member_count(Channel.t()) :: non_neg_integer()
end

defmodule Foyer.Channels.Behavior do
  @moduledoc """
  Behaviour for `Foyer.Channels`.
  """

  alias Foyer.Accounts.User
  alias Foyer.Channels.Channel

  @doc """
  Returns channels visible to the given user through membership.
  """
  @callback list_for_user(User.t()) :: [Channel.t()]

  @doc """
  Returns all channels paired with their member counts for directory filters and
  pickers.
  """
  @callback list_all_with_member_counts() :: [{Channel.t(), non_neg_integer()}]

  @doc """
  Fetches a channel by id.

  Raises when the channel does not exist.
  """
  @callback get!(integer() | String.t()) :: Channel.t()

  @doc """
  Returns whether the user belongs to the given channel.
  """
  @callback member?(User.t(), Channel.t()) :: boolean()

  @doc """
  Returns the number of users who belong to the given channel.
  """
  @callback member_count(Channel.t()) :: non_neg_integer()
end

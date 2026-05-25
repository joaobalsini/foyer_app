defmodule Foyer.Channels do
  @moduledoc """
  Channels (audience units). Reads only in the scaffold — channel mutation is
  deferred to the Channels feature group.
  """
  @behaviour Foyer.ChannelsPort

  import Ecto.Query, warn: false

  alias Foyer.Accounts.User
  alias Foyer.Channels.Channel
  alias Foyer.Channels.Membership
  alias Foyer.Repo

  @impl true
  @spec list_for_user(User.t()) :: [Channel.t()]
  def list_for_user(%User{id: user_id}) do
    from(c in Channel,
      join: m in Membership,
      on: m.channel_id == c.id and m.user_id == ^user_id,
      order_by: [asc: c.name]
    )
    |> Repo.all()
  end

  @impl true
  @spec list_all_with_member_counts() :: [{Channel.t(), non_neg_integer()}]
  def list_all_with_member_counts do
    counts_query =
      from(m in Membership,
        group_by: m.channel_id,
        select: {m.channel_id, count(m.id)}
      )

    counts = counts_query |> Repo.all() |> Map.new()

    Channel
    |> order_by([c], asc: c.name)
    |> Repo.all()
    |> Enum.map(fn channel -> {channel, Map.get(counts, channel.id, 0)} end)
  end

  @impl true
  @spec get!(integer() | String.t()) :: Channel.t()
  def get!(id), do: Repo.get!(Channel, id)

  @impl true
  @spec member?(User.t(), Channel.t()) :: boolean()
  def member?(%User{id: user_id}, %Channel{id: channel_id}) do
    from(m in Membership,
      where: m.user_id == ^user_id and m.channel_id == ^channel_id
    )
    |> Repo.exists?()
  end

  @impl true
  @spec member_count(Channel.t()) :: non_neg_integer()
  def member_count(%Channel{id: channel_id}) do
    from(m in Membership,
      where: m.channel_id == ^channel_id,
      select: count(m.id)
    )
    |> Repo.one()
  end
end

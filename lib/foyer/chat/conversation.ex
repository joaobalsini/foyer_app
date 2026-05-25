defmodule Foyer.Chat.Conversation do
  @moduledoc """
  Either a `:direct` two-party DM (identified by canonical `direct_key`
  formed as `min_uid-max_uid`) or a `:channel` conversation (one per
  `Channel`). `last_message_at` is denormalised for inbox-ordering — kept up to
  date by `send_message/3` (feature group) and the seeds. See plan §5.9.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          kind: :direct | :channel | nil,
          channel_id: integer() | nil,
          direct_key: String.t() | nil,
          last_message_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "conversations" do
    field :kind, Ecto.Enum, values: [:direct, :channel]
    belongs_to :channel, Foyer.Channels.Channel
    field :direct_key, :string
    field :last_message_at, :utc_datetime
    field :unread?, :boolean, virtual: true, default: false
    field :unread_count, :integer, virtual: true, default: 0

    has_many :participants, Foyer.Chat.Participant
    has_many :messages, Foyer.Chat.Message

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:kind, :channel_id, :direct_key, :last_message_at])
    |> validate_required([:kind])
    |> validate_kind_channel_pair()
    |> maybe_put_direct_key(attrs)
    |> unique_constraint(:direct_key, name: :conversations_direct_key_unique)
    |> unique_constraint(:channel_id, name: :conversations_channel_id_unique)
    |> check_constraint(:kind, name: :conversation_kind_channel_pair)
  end

  defp validate_kind_channel_pair(changeset) do
    case {get_field(changeset, :kind), get_field(changeset, :channel_id)} do
      {:channel, nil} ->
        add_error(changeset, :channel_id, "required for channel conversations")

      {:direct, id} when not is_nil(id) ->
        add_error(changeset, :channel_id, "must be nil for direct conversations")

      _ ->
        changeset
    end
  end

  defp maybe_put_direct_key(changeset, %{participant_user_ids: [a, b]})
       when is_integer(a) and is_integer(b) do
    put_change(changeset, :direct_key, direct_key([a, b]))
  end

  defp maybe_put_direct_key(changeset, %{"participant_user_ids" => [a, b]})
       when is_integer(a) and is_integer(b) do
    put_change(changeset, :direct_key, direct_key([a, b]))
  end

  defp maybe_put_direct_key(changeset, _attrs), do: changeset

  @spec direct_key([integer()]) :: String.t()
  def direct_key([a, b]) when is_integer(a) and is_integer(b) do
    [low, high] = Enum.sort([a, b])
    "#{low}-#{high}"
  end
end

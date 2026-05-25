defmodule Foyer.House.Announcement do
  @moduledoc """
  House announcement. Targeted at a single channel (audience). Optional
  `pinned_at` raises it to the top of the feed; optional `requires_ack` shows
  the "I've read & understood" CTA on the detail page.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          author_id: integer() | nil,
          channel_id: integer() | nil,
          title: String.t() | nil,
          body: String.t() | nil,
          pinned_at: DateTime.t() | nil,
          requires_ack: boolean() | nil,
          published_at: DateTime.t() | nil,
          removed_at: DateTime.t() | nil,
          removed_by_id: integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "announcements" do
    belongs_to :author, Foyer.Accounts.User
    belongs_to :channel, Foyer.Channels.Channel
    field :title, :string
    field :body, :string
    field :pinned_at, :utc_datetime
    field :requires_ack, :boolean, default: false
    field :published_at, :utc_datetime
    field :removed_at, :utc_datetime
    belongs_to :removed_by, Foyer.Accounts.User

    has_many :reads, Foyer.House.AnnouncementRead
    has_many :acks, Foyer.House.AnnouncementAck

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(announcement, attrs) do
    announcement
    |> cast(attrs, [
      :author_id,
      :channel_id,
      :title,
      :body,
      :pinned_at,
      :requires_ack,
      :published_at,
      :removed_at,
      :removed_by_id
    ])
    |> validate_required([:author_id, :channel_id, :title, :body, :published_at])
  end
end

defmodule Foyer.Repo.Migrations.CreateConversations do
  use Ecto.Migration

  def change do
    create table(:conversations) do
      add :kind, :string, null: false
      add :channel_id, references(:channels, on_delete: :delete_all)
      add :direct_key, :string
      add :last_message_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:conversations, [:last_message_at])

    create unique_index(:conversations, [:channel_id],
             where: "kind = 'channel'",
             name: :conversations_channel_id_unique
           )

    create unique_index(:conversations, [:direct_key],
             where: "kind = 'direct'",
             name: :conversations_direct_key_unique
           )

    create constraint(:conversations, :conversation_kind_channel_pair,
             check:
               "(kind = 'channel' AND channel_id IS NOT NULL) OR (kind = 'direct' AND channel_id IS NULL)"
           )

    create constraint(:conversations, :conversation_kind_enum,
             check: "kind IN ('direct', 'channel')"
           )
  end
end

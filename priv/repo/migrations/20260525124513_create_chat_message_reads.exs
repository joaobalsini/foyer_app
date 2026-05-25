defmodule Foyer.Repo.Migrations.CreateChatMessageReads do
  use Ecto.Migration

  def change do
    create table(:chat_message_reads) do
      add :message_id, references(:chat_messages, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :read_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:chat_message_reads, [:message_id, :user_id])
    create index(:chat_message_reads, [:user_id])
  end
end

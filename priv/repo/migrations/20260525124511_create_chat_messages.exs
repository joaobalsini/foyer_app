defmodule Foyer.Repo.Migrations.CreateChatMessages do
  use Ecto.Migration

  def change do
    create table(:chat_messages) do
      add :conversation_id, references(:conversations, on_delete: :delete_all), null: false
      add :author_id, references(:users, on_delete: :nilify_all)
      add :body, :text, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:chat_messages, [:conversation_id, :inserted_at])
    create index(:chat_messages, [:author_id])
  end
end

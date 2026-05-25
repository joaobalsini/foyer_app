defmodule Foyer.Repo.Migrations.CreateAnnouncements do
  use Ecto.Migration

  def change do
    create table(:announcements) do
      add :author_id, references(:users, on_delete: :nilify_all)
      add :channel_id, references(:channels, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :body, :text, null: false
      add :pinned_at, :utc_datetime
      add :requires_ack, :boolean, default: false, null: false
      add :published_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:announcements, [:channel_id, :pinned_at, :published_at])
    create index(:announcements, [:author_id])

    create index(:announcements, [:pinned_at, :published_at],
             where: "pinned_at IS NOT NULL",
             name: :announcements_pinned_feed_index
           )
  end
end

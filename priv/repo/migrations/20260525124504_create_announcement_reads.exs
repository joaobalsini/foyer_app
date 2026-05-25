defmodule Foyer.Repo.Migrations.CreateAnnouncementReads do
  use Ecto.Migration

  def change do
    create table(:announcement_reads) do
      add :announcement_id, references(:announcements, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :read_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:announcement_reads, [:announcement_id, :user_id],
             name: :announcement_reads_announcement_id_user_id_index
           )

    create index(:announcement_reads, [:user_id])
  end
end

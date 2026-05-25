defmodule Foyer.Repo.Migrations.CreateAnnouncementAcks do
  use Ecto.Migration

  def change do
    create table(:announcement_acks) do
      add :announcement_id, references(:announcements, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :ack_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:announcement_acks, [:announcement_id, :user_id],
             name: :announcement_acks_announcement_id_user_id_index
           )

    create index(:announcement_acks, [:user_id])
  end
end

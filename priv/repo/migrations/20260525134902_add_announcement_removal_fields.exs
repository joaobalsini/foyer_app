defmodule Foyer.Repo.Migrations.AddAnnouncementRemovalFields do
  use Ecto.Migration

  def change do
    alter table(:announcements) do
      add :removed_at, :utc_datetime
      add :removed_by_id, references(:users, on_delete: :nilify_all)
    end

    create index(:announcements, [:removed_at])
    create index(:announcements, [:removed_by_id])
  end
end

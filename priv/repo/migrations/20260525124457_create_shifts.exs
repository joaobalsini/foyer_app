defmodule Foyer.Repo.Migrations.CreateShifts do
  use Ecto.Migration

  def change do
    create table(:shifts) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :started_at, :utc_datetime, null: false
      add :ended_at, :utc_datetime
      add :handoff_note, :text
      add :handoff_channel_id, references(:channels, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:shifts, [:user_id, :ended_at])
    create index(:shifts, [:handoff_channel_id, :ended_at])

    create unique_index(:shifts, [:user_id],
             where: "ended_at IS NULL",
             name: :shifts_one_open_shift_per_user
           )
  end
end

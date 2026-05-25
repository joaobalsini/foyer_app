defmodule Foyer.Repo.Migrations.AddRecognitionRemovalAndPointsLedger do
  use Ecto.Migration

  def change do
    alter table(:recognitions) do
      add :removed_at, :utc_datetime
      add :removed_by_id, references(:users, on_delete: :nilify_all)
    end

    create index(:recognitions, [:removed_at])
    create index(:recognitions, [:removed_by_id])

    create table(:recognition_point_entries) do
      add :recognition_id, references(:recognitions, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :delta, :integer, null: false
      add :reason, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:recognition_point_entries, [:recognition_id])
    create index(:recognition_point_entries, [:user_id, :inserted_at])
  end
end

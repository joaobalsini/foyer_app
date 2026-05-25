defmodule Foyer.Repo.Migrations.CreateRecognitions do
  use Ecto.Migration

  def change do
    create table(:recognitions) do
      add :sender_id, references(:users, on_delete: :nilify_all)
      add :recipient_id, references(:users, on_delete: :delete_all), null: false
      add :body, :text, null: false
      add :values, {:array, :string}, default: [], null: false
      add :bonus_points, :integer, default: 0, null: false
      add :public, :boolean, default: true, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:recognitions, [:recipient_id, :inserted_at])
    create index(:recognitions, [:sender_id])
    create index(:recognitions, [:public, :inserted_at])

    create constraint(:recognitions, :bonus_points_non_negative, check: "bonus_points >= 0")
  end
end

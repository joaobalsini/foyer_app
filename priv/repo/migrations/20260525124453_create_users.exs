defmodule Foyer.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :name, :string, null: false
      add :initials, :string, null: false
      add :role, :string, null: false
      add :department, :string, null: false
      add :title, :string
      add :languages, {:array, :string}, default: [], null: false
      add :points_balance, :integer, default: 0, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:users, [:role])
  end
end

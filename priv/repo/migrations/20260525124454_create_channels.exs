defmodule Foyer.Repo.Migrations.CreateChannels do
  use Ecto.Migration

  def change do
    create table(:channels) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :kind, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:channels, [:slug])
  end
end

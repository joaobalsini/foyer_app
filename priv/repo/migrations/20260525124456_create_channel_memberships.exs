defmodule Foyer.Repo.Migrations.CreateChannelMemberships do
  use Ecto.Migration

  def change do
    create table(:channel_memberships) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :channel_id, references(:channels, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:channel_memberships, [:user_id, :channel_id],
             name: :channel_memberships_user_id_channel_id_index
           )

    create index(:channel_memberships, [:channel_id])
  end
end

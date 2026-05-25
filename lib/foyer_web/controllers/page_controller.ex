defmodule FoyerWeb.PageController do
  use FoyerWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end

defmodule JidoPhxStarterWeb.PageController do
  use JidoPhxStarterWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end

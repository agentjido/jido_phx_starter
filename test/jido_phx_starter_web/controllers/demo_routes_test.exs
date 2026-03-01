defmodule JidoPhxStarterWeb.DemoRoutesTest do
  use JidoPhxStarterWeb.ConnCase

  alias JidoPhxStarterWeb.DemoMetadata

  @removed_demo_routes [
    "/demos/jido/counter",
    "/demos/jido/chat",
    "/demos/jido/weekend-sale",
    "/demos/jido/1-counter"
  ]

  test "canonical demo routes render", %{conn: conn} do
    Enum.each(DemoMetadata.canonical_paths(), fn path ->
      assert html_response(get(conn, path), 200)
    end)
  end

  test "old /demos routes are not exposed", %{conn: conn} do
    Enum.each(@removed_demo_routes, fn path ->
      assert html_response(get(conn, path), 404)
    end)
  end
end

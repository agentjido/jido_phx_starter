defmodule JidoPhxStarter.Demos.ListingsDomain do
  @moduledoc """
  Ash Domain for the Demo 4: Listing Manager.

  This domain contains the Listing resource used to demonstrate
  AshJido integration - where Ash actions become Jido tools.
  """
  use Ash.Domain

  resources do
    resource JidoPhxStarter.Demos.ListingsDomain.Listing
  end
end

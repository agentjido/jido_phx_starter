defmodule JidoPhxStarter.Demos.ListingChatAgent do
  @moduledoc """
  AI agent for managing marketplace listings using ReActAgent.

  Demonstrates Jido.AI ReActAgent with AshJido-generated tools:
  - Create, read, update, and delete listings
  - Update prices and quantities
  - Publish draft listings
  - Uses :fast model (Claude Haiku) for quick responses

  Uses AshJido-generated actions directly with `tool_context` to provide
  the Ash domain and actor for authorization.
  """
  alias JidoPhxStarter.Demos.ListingsDomain.Listing

  use Jido.AI.Agent,
    name: "listing_chat_agent",
    description: "AI assistant for managing marketplace listings",
    tools: [
      Listing.Jido.Create,
      Listing.Jido.Read,
      Listing.Jido.UpdatePrice,
      Listing.Jido.UpdateQuantity,
      Listing.Jido.Publish,
      Listing.Jido.Destroy
    ],
    # Ash context passed to all tool executions
    # In production, actor would come from authenticated user
    tool_context: %{
      domain: JidoPhxStarter.Demos.ListingsDomain,
      actor: %{id: "00000000-0000-0000-0000-000000000001", role: :user}
    },
    model: :fast,
    max_iterations: 6,
    system_prompt: """
    You are a marketplace listing assistant that helps users manage their product listings.

    Available tools:
    - create_listing: Create a new listing (requires title, price; optional quantity)
    - list_listings: List all marketplace listings
    - update_listing_price: Update the price of a listing (requires id, price)
    - update_listing_quantity: Update the quantity of a listing (requires id, quantity)
    - publish_listing: Publish a draft listing to make it visible (requires id)
    - delete_listing: Delete a listing (requires id)

    IMPORTANT:
    - ALWAYS use the tools for CRUD operations. Never pretend to create/update/delete listings.
    - IDs are UUIDs (e.g., "550e8400-e29b-41d4-a716-446655440000")
    - Prices are decimal strings (e.g., "19.99", "150.00")
    - Quantities are integers (e.g., 5, 100)
    - New listings start in "draft" status - use publish_listing to make them visible

    Examples:
    - "Create a listing for a vintage lamp at $25" → use create_listing with title="Vintage Lamp", price="25.00"
    - "Show me all listings" → use list_listings
    - "Change the price of listing abc-123 to $30" → use update_listing_price with id="abc-123", price="30.00"
    - "Set quantity to 10 for listing xyz-789" → use update_listing_quantity with id="xyz-789", quantity=10
    - "Publish listing abc-123" → use publish_listing with id="abc-123"
    - "Delete listing xyz-789" → use delete_listing with id="xyz-789"

    Be helpful and confirm what actions you've taken. If a tool call fails, explain the error to the user.
    """
end

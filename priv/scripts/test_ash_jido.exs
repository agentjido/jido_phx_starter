# Test script for AshJido integration
# Run with: mix run priv/scripts/test_ash_jido.exs
#
# Or paste into iex -S mix after compiling

alias JidoPhxStarter.Demos.ListingsDomain
alias JidoPhxStarter.Demos.ListingsDomain.Listing

IO.puts("\n=== AshJido Integration Test ===\n")

# Setup actors
guest = %{id: nil, role: :guest}
user_a = %{id: Ash.UUID.generate(), role: :user}
user_b = %{id: Ash.UUID.generate(), role: :user}
admin = %{id: Ash.UUID.generate(), role: :admin}

ctx_guest = %{domain: ListingsDomain, actor: guest}
ctx_a = %{domain: ListingsDomain, actor: user_a}
ctx_b = %{domain: ListingsDomain, actor: user_b}
ctx_admin = %{domain: ListingsDomain, actor: admin}

IO.puts("Actors created:")
IO.puts("  guest: #{inspect(guest)}")
IO.puts("  user_a: #{inspect(user_a)}")
IO.puts("  user_b: #{inspect(user_b)}")
IO.puts("  admin: #{inspect(admin)}")

# Test 1: Guest cannot create (should be forbidden)
IO.puts("\n--- Test 1: Guest create (should fail) ---")

case Listing.Jido.Create.run(%{title: "Blue Widget", price: "19.99", quantity: 2}, ctx_guest) do
  {:error, err} ->
    IO.puts("✓ Guest create correctly rejected")
    IO.puts("  Error type: #{inspect(err.__struct__)}")
    IO.inspect(err, label: "  Error details", limit: 5)

  {:ok, result} ->
    IO.puts("✗ Guest create unexpectedly succeeded!")
    IO.inspect(result, label: "  Result")
end

# Test 2: User A creates a listing
IO.puts("\n--- Test 2: User A create ---")

case Listing.Jido.Create.run(%{title: "Blue Widget", price: "19.99", quantity: 2}, ctx_a) do
  {:ok, listing_a} ->
    IO.puts("✓ User A create succeeded")
    IO.inspect(listing_a, label: "  Listing")

    listing_id =
      case listing_a do
        %{id: id} -> id
        %{"id" => id} -> id
      end

    # Test 3: List listings (anyone can read)
    IO.puts("\n--- Test 3: List listings (guest can read) ---")

    case Listing.Jido.Read.run(%{}, ctx_guest) do
      {:ok, %{results: listings}} ->
        IO.puts("✓ Read succeeded, found #{length(listings)} listing(s)")
        IO.inspect(listings, label: "  Listings", limit: 3)

      {:ok, listings} when is_list(listings) ->
        IO.puts("✓ Read succeeded (raw list), found #{length(listings)} listing(s)")
        IO.inspect(listings, label: "  Listings", limit: 3)

      {:error, err} ->
        IO.puts("✗ Read failed!")
        IO.inspect(err, label: "  Error")
    end

    # Test 4: User B tries to update User A's listing (should fail)
    IO.puts("\n--- Test 4: User B update price (should fail - not owner) ---")

    case Listing.Jido.UpdatePrice.run(%{id: listing_id, price: "25.00"}, ctx_b) do
      {:error, err} ->
        IO.puts("✓ User B update correctly rejected")
        IO.puts("  Error type: #{inspect(err.__struct__)}")

      {:ok, _} ->
        IO.puts("✗ User B update unexpectedly succeeded!")
    end

    # Test 5: Owner updates price
    IO.puts("\n--- Test 5: Owner (User A) update price ---")

    case Listing.Jido.UpdatePrice.run(%{id: listing_id, price: "25.00"}, ctx_a) do
      {:ok, updated} ->
        IO.puts("✓ Owner update succeeded")
        IO.inspect(updated, label: "  Updated listing")

      {:error, err} ->
        IO.puts("✗ Owner update failed!")
        IO.inspect(err, label: "  Error")
    end

    # Test 6: Admin can publish
    IO.puts("\n--- Test 6: Admin publish ---")

    case Listing.Jido.Publish.run(%{id: listing_id}, ctx_admin) do
      {:ok, published} ->
        IO.puts("✓ Admin publish succeeded")
        status =
          case published do
            %{status: s} -> s
            %{"status" => s} -> s
          end

        IO.puts("  Status: #{status}")

      {:error, err} ->
        IO.puts("✗ Admin publish failed!")
        IO.inspect(err, label: "  Error")
    end

    # Test 7: Admin can delete
    IO.puts("\n--- Test 7: Admin delete ---")

    case Listing.Jido.Destroy.run(%{id: listing_id}, ctx_admin) do
      {:ok, _} ->
        IO.puts("✓ Admin delete succeeded")

      {:error, err} ->
        IO.puts("✗ Admin delete failed!")
        IO.inspect(err, label: "  Error")
    end

    # Test 8: Confirm empty
    IO.puts("\n--- Test 8: Confirm listings empty ---")

    case Listing.Jido.Read.run(%{}, ctx_guest) do
      {:ok, %{results: listings}} ->
        IO.puts("✓ Listings count: #{length(listings)}")

      {:ok, listings} when is_list(listings) ->
        IO.puts("✓ Listings count: #{length(listings)}")

      {:error, err} ->
        IO.puts("✗ Read failed!")
        IO.inspect(err, label: "  Error")
    end

  {:error, err} ->
    IO.puts("✗ User A create failed - cannot continue tests")
    IO.inspect(err, label: "  Error")
end

IO.puts("\n=== Test Complete ===\n")

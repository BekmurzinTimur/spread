class_name DistributorBehavior
extends BlockBehavior

## Takes one line in and splits it across several outputs, one orb at a time.
##
## Structurally the compressor with the size taken out: bank in `on_orb_deliver`,
## emit in `on_produce` one tick later, same order-independence argument. What is
## different is *where* the orb goes — round-robin over `Block.ports` rather than
## at a single `target_id`.
##
## **What it buys the player is fan-out without re-aiming.** One generator can
## only point at one cell, so opening four cells at once has always meant four
## generators or four visits back to the same one. A distributor is the block that
## turns a single supply line into a frontier.
##
## Anchored, for the upgrader's reason, and it takes no `target_id` at all — the
## ports *are* its aim. That is what keeps `needs_target`, `movable` and
## `has_ports()` pairwise disjoint, so a right-click still has exactly one reading.


## Absorb an arriving orb of the input tier, up to one output orb's worth.
##
## The cap is `effective_orb_value()` — what an orb leaving here would be worth —
## so a distributor banks exactly enough for the orb it is about to send and no
## more. A Surge raises both halves together, which is the right answer for free:
## the block is a relay, and a relay should pass on whatever the board's orbs are
## currently worth.
##
## Banks while it has no ports at all, for the upgrader's reason: mining a cell
## drops the port that fed it, and a block that refused orbs in that window would
## throw away whatever was already in flight toward it.
func on_orb_deliver(world, cell: GraphCell, orb: Orb) -> int:
	var block := cell.block
	if not block.def.accepts_delivery(orb.tier):
		return 0
	var room: int = world.effective_orb_value(block.def.output_tier) - block.charge
	if room <= 0:
		return 0
	var taken: int = mini(orb.value, room)
	block.charge += taken
	world.absorb_value(taken)
	return taken


## Send one orb to the next port in the rotation.
##
## **The cursor advances past whichever port actually fired, not blindly.** A port
## whose destination has gone unroutable is skipped and the next one tried, so one
## dead output cannot stall the rotation behind it — which would otherwise be a
## silent halt with no indicator, since the block still has ports and so does not
## read as idle.
##
## Order-independent: the cursor is written and read only inside this block's own
## call, so no other block in the produce phase can observe it. That is the same
## position `timer` and `charge` are already in.
##
## **No new ledger bucket.** Intake books `converted` through `absorb_value`, and
## the orb out books `produced` through `emit_orb` — the compressor's accounting
## with the size change taken out.
func on_produce(world, cell: GraphCell, block: Block) -> void:
	if block.ports.is_empty():
		return
	# Its own tier: a distributor relays the colour it eats, so the bank it fills
	# and the orb it ships are priced on the same colour's orb value.
	var cost: int = world.effective_orb_value(block.def.output_tier)
	if block.charge < cost:
		return

	var count: int = block.ports.size()
	for attempt in count:
		var index: int = (block.port_cursor + attempt) % count
		var port: BlockPort = block.ports[index]
		if world.emit_orb(cell.id, port.target_id, block.def.output_tier,
				port.route_via):
			block.charge -= cost
			block.port_cursor = (index + 1) % count
			block.mark_active(world.tick_count)
			return

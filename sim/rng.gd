class_name Rng

## Stateless randomness. The only source of variance in `sim/`.
##
## Every roll is a hash of its keys, never a stream, so a roll cannot depend on
## how many came before it — which is what keeps the tick order-independent.

const _MASK := 0x7FFFFFFFFFFFFFFF

## Denominator for a percentage roll. `roll(...) < 500` is a 5% chance.
const SCALE := 10000


## A 64-bit avalanche (splitmix64's finaliser). Every input bit reaches every
## output bit, so keys that differ by one still land far apart.
static func _mix(value: int) -> int:
	var x := value
	x = (x ^ (x >> 30)) * -4658895280553007687
	x = (x ^ (x >> 27)) * -7723592293110705685
	x = x ^ (x >> 31)
	return x & _MASK


## A roll in 0..SCALE-1, from a seed and up to three keys.
## `_mix` is inlined here: this runs several times per orb and calls are slow.
static func roll(seed_value: int, a: int, b: int = 0, c: int = 0) -> int:
	var h := seed_value
	h = (h ^ (h >> 30)) * -4658895280553007687
	h = (h ^ (h >> 27)) * -7723592293110705685
	h = (h ^ (h >> 31)) & _MASK

	var x := a
	x = (x ^ (x >> 30)) * -4658895280553007687
	x = (x ^ (x >> 27)) * -7723592293110705685
	h ^= (x ^ (x >> 31)) & _MASK
	h = (h ^ (h >> 30)) * -4658895280553007687
	h = (h ^ (h >> 27)) * -7723592293110705685
	h = (h ^ (h >> 31)) & _MASK

	x = b
	x = (x ^ (x >> 30)) * -4658895280553007687
	x = (x ^ (x >> 27)) * -7723592293110705685
	h ^= (x ^ (x >> 31)) & _MASK
	h = (h ^ (h >> 30)) * -4658895280553007687
	h = (h ^ (h >> 27)) * -7723592293110705685
	h = (h ^ (h >> 31)) & _MASK

	x = c
	x = (x ^ (x >> 30)) * -4658895280553007687
	x = (x ^ (x >> 27)) * -7723592293110705685
	h ^= (x ^ (x >> 31)) & _MASK
	h = (h ^ (h >> 30)) * -4658895280553007687
	h = (h ^ (h >> 27)) * -7723592293110705685
	h = (h ^ (h >> 31)) & _MASK
	return h % SCALE

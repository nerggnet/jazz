//// A small deterministic pseudo random number generator.
////
//// Generated lines have to be reproducible: the seed is part of the request,
//// so a player can come back to a lick they liked. Platform randomness would
//// give different answers on the Erlang and JavaScript targets, so this is a
//// Lehmer generator whose arithmetic stays inside the range JavaScript can
//// represent exactly.

import gleam/list
import jazz/internal/num

pub opaque type Random {
  Random(state: Int)
}

const modulus = 2_147_483_647

const multiplier = 48_271

pub fn new(seed: Int) -> Random {
  case num.modulo(seed, modulus) {
    0 -> Random(1)
    state -> Random(state)
  }
}

/// The next raw value, and the generator to carry on with.
pub fn step(random: Random) -> #(Int, Random) {
  let next = num.modulo(random.state * multiplier, modulus)
  #(next, Random(next))
}

/// A number from zero up to but not including the limit.
pub fn below(random: Random, limit: Int) -> #(Int, Random) {
  case limit <= 1 {
    True -> #(0, random)
    False -> {
      let #(value, next) = step(random)
      // Take the high bits. A Lehmer generator's low bits fall into short
      // cycles, which shows up immediately when picking from a list of three.
      #(value * limit / modulus, next)
    }
  }
}

/// One item from a list, falling back when the list is empty.
pub fn pick(random: Random, items: List(a), fallback: a) -> #(a, Random) {
  let #(index, next) = below(random, list.length(items))
  case list.drop(items, index) {
    [chosen, ..] -> #(chosen, next)
    [] -> #(fallback, next)
  }
}

/// True roughly `percent` times in a hundred.
pub fn chance(random: Random, percent: Int) -> #(Bool, Random) {
  let #(value, next) = below(random, 100)
  #(value < percent, next)
}

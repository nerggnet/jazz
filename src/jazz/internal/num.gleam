//// Integer helpers that floor towards negative infinity.
////
//// Gleam's `/` and `%` truncate towards zero, which is wrong for pitch
//// arithmetic: transposing down from `C4` has to land in octave 3, not
//// octave 0, and a letter index of -1 has to wrap round to `B`.

/// Division that rounds towards negative infinity.
pub fn floor_div(a: Int, b: Int) -> Int {
  let quotient = a / b
  case a % b != 0 && { a < 0 } != { b < 0 } {
    True -> quotient - 1
    False -> quotient
  }
}

/// Remainder that always takes the sign of the divisor.
pub fn modulo(a: Int, b: Int) -> Int {
  let remainder = a % b
  case remainder != 0 && { remainder < 0 } != { b < 0 } {
    True -> remainder + b
    False -> remainder
  }
}

/// The numbers from zero up to but not including `total`.
pub fn counting(total: Int) -> List(Int) {
  case total <= 0 {
    True -> []
    False -> append_last(counting(total - 1), total - 1)
  }
}

fn append_last(items: List(Int), last: Int) -> List(Int) {
  case items {
    [] -> [last]
    [first, ..rest] -> [first, ..append_last(rest, last)]
  }
}

import gleam/list
import gleam/string
import birdie
import gleeunit
import whinge

pub fn main() {
  gleeunit.main()
}

// This is gonna be our initial testing setup for quick development
// while there are lots of moving pieces.
// 
pub fn smoke_test() {
  let assert Ok(rules) = whinge.run(on: "./snap_dummy")
  use rule <- list.each(rules)

  rule
  |> whinge.display_rule_error
  |> birdie.snap(title: rule.path)
}

pub fn everything_test() {
  let assert Ok(rules) = whinge.run(on: "./snap_dummy")
  list.map(rules, whinge.display_rule_error)
  |> string.join("\n\n\n")
  |> birdie.snap(title: "everything")
}

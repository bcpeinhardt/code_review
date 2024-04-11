import gleam/list
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

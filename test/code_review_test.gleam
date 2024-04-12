import birdie
import gleam/list
import gleeunit
import code_review

pub fn main() {
  gleeunit.main()
}

// This is gonna be our initial testing setup for quick development
// while there are lots of moving pieces.
// 
pub fn smoke_test() {
  let assert Ok(rules) = code_review.run(on: "./snap_dummy")
  use rule <- list.each(rules)

  rule
  |> code_review.display_rule_error
  |> birdie.snap(title: rule.path)
}

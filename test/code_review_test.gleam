import birdie
import code_review
import gleam/list
import gleeunit
import rule

pub fn main() {
  gleeunit.main()
}

// This is gonna be our initial testing setup for quick development
// while there are lots of moving pieces.
// 
pub fn smoke_test() {
  let assert Ok(rule_errors) = code_review.run(on: "./snap_dummy")
  use rule: rule.RuleError <- list.each(rule_errors)

  rule
  |> code_review.display_rule_error
  |> birdie.snap(title: rule.path)
}

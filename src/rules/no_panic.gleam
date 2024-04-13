//// This rule checks the code for any panic statements. 

import glance
import rule.{type Rule, type RuleViolation, Rule}

pub const rule = Rule(
  name: "NoPanic",
  expression_visitors: [check_expressions_for_panics],
)

pub fn check_expressions_for_panics(
  expr: glance.Expression,
) -> List(RuleViolation) {
  case expr {
    glance.Panic(_) -> {
      [
        rule.error(message: "Found `panic`", details: [
          "This keyword should almost never be used! It may be useful in initial prototypes and scripts, but its use in a library or production application is a sign that the design could be improved.",
          "With well designed types the type system can typically be used to make these invalid states unrepresentable.",
        ]),
      ]
    }
    _ -> []
  }
}

import glance
import rule.{type Rule, type RuleError}

pub fn rule() -> Rule {
  rule.new("NoPanic")
  |> rule.with_expression_visitor(expression_visitor)
}

pub fn expression_visitor(expr: glance.Expression) -> List(RuleError) {
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

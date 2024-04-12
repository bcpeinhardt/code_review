import glance
import gleam/option
import rule.{type Rule, type RuleError, Rule}

pub const rule: Rule = Rule(
  name: "NoPanic",
  expression_visitor: option.Some(contains_panic_in_function_expression_visitor),
)

pub fn contains_panic_in_function_expression_visitor(
  expr: glance.Expression,
) -> List(RuleError) {
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

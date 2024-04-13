import glance
import gleam/string
import rule.{type Rule, type RuleError}

pub fn rule() -> Rule {
  rule.new("NoTrailingUnderscore")
  |> rule.with_function_visitor(function_visitor)
}

pub fn function_visitor(function: glance.Function) -> List(RuleError) {
  case string.ends_with(function.name, "_") {
    True -> [
      rule.error(message: "Trailing underscore in function name", details: [
        "We don't like no trailing underscores.",
      ]),
    ]
    False -> []
  }
}

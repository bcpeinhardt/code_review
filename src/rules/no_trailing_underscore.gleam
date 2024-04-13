import glance
import gleam/string
import rule.{type Rule, type RuleError}

pub fn rule() -> Rule {
  rule.new("no_trailing_underscore", Nil)
  |> rule.with_simple_function_visitor(function_visitor)
  |> rule.to_rule
}

pub fn function_visitor(
  function: glance.Definition(glance.Function),
) -> List(RuleError) {
  let glance.Definition(_, func) = function
  case string.ends_with(func.name, "_") {
    True -> [
      rule.error(
        message: "Trailing underscore in function name",
        details: ["We don't like no trailing underscores."],
        location: func.name,
      ),
    ]
    False -> []
  }
}

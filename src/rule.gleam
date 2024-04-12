import glance
import gleam/list

pub type Rule {
  Rule(
    name: String,
    function_visitors: List(fn(glance.Function) -> List(RuleError)),
    expression_visitors: List(fn(glance.Expression) -> List(RuleError)),
  )
}

pub fn new(name: String) {
  Rule(name: name, function_visitors: [], expression_visitors: [])
}

pub fn with_function_visitor(
  rule: Rule,
  visitor: fn(glance.Function) -> List(RuleError),
) {
  Rule(
    ..rule,
    function_visitors: [
      set_rule_name_on_errors(rule.name, visitor),
      ..rule.function_visitors
    ],
  )
}

pub fn with_expression_visitor(
  rule: Rule,
  visitor: fn(glance.Expression) -> List(RuleError),
) {
  Rule(
    ..rule,
    expression_visitors: [
      set_rule_name_on_errors(rule.name, visitor),
      ..rule.expression_visitors
    ],
  )
}

fn combine_visitors(new_visitor: fn(glance.Expression) -> List(RuleError), maybe_previous_visitor: option.Option(fn(glance.Expression) -> List(RuleError))) {
  case maybe_previous_visitor {
    option.None-> new_visitor
    option.Some(previous_visitor)-> fn(a, context) {
       let #( errors_after_first_visit, context_after_first_visit ) = previous_visitor(a, context)
       let #( errors_after_second_visit, context_after_second_visit ) = new_visitor(a, context_after_first_visit)
       ( List.append errors_after_first_visit errors_after_second_visit, context_after_second_visit )
    }
  }
}

fn set_rule_name_on_errors(name: String, visitor: fn(a) -> List(RuleError)) {
  fn(a: a) {
    visitor(a)
    |> list.map(fn(error) { RuleError(..error, rule: name) })
  }
}

// Represents an error reported by a rule.
pub type RuleError {
  RuleError(
    path: String,
    location_identifier: String,
    rule: String,
    message: String,
    details: List(String),
  )
}

pub fn error(
  message message: String,
  details details: List(String),
) -> RuleError {
  RuleError(
    path: "",
    location_identifier: "",
    rule: "",
    message: message,
    details: details,
  )
}

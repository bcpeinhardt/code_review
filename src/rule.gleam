import glance
import gleam/list
import gleam/option

pub type Rule {
  Rule(
    name: String,
    function_visitor: option.Option(fn(glance.Function) -> List(RuleError)),
    expression_visitor: option.Option(fn(glance.Expression) -> List(RuleError)),
  )
}

pub fn new(name: String) {
  Rule(
    name: name,
    function_visitor: option.None,
    expression_visitor: option.None,
  )
}

pub fn with_function_visitor(
  rule: Rule,
  visitor: fn(glance.Function) -> List(RuleError),
) {
  Rule(
    ..rule,
    function_visitor: option.Some(combine_visitors(
      rule.name,
      visitor,
      rule.function_visitor,
    )),
  )
}

pub fn with_expression_visitor(
  rule: Rule,
  visitor: fn(glance.Expression) -> List(RuleError),
) {
  Rule(
    ..rule,
    expression_visitor: option.Some(combine_visitors(
      rule.name,
      visitor,
      rule.expression_visitor,
    )),
  )
}

fn combine_visitors(
  rule_name: String,
  new_visitor: fn(a) -> List(RuleError),
  maybe_previous_visitor: option.Option(fn(a) -> List(RuleError)),
) {
  case maybe_previous_visitor {
    option.None -> set_rule_name_on_errors(rule_name, new_visitor)
    option.Some(previous_visitor) -> fn(a) {
      let errors_after_first_visit = previous_visitor(a)
      let errors_after_second_visit =
        set_rule_name_on_errors(rule_name, new_visitor)(a)

      list.append(errors_after_first_visit, errors_after_second_visit)
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

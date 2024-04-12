import glance

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
  Rule(..rule, function_visitors: [visitor, ..rule.function_visitors])
}

pub fn with_expression_visitor(
  rule: Rule,
  visitor: fn(glance.Expression) -> List(RuleError),
) {
  Rule(..rule, expression_visitors: [visitor, ..rule.expression_visitors])
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

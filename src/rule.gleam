import glance

pub type Rule {
  Rule(
    name: String,
    expression_visitors: List(fn(glance.Expression) -> List(RuleViolation)),
  )
}

// Represents an error reported by a rule.
pub type RuleViolation {
  RuleViolation(
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
) -> RuleViolation {
  RuleViolation(
    path: "",
    location_identifier: "",
    rule: "",
    message: message,
    details: details,
  )
}

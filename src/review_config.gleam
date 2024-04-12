import rule.{type Rule, Rule}
import rules/no_panic
import rules/no_unnecessary_string_concatenation

pub fn config() -> List(Rule) {
  [no_panic.rule(), no_unnecessary_string_concatenation.rule()]
}

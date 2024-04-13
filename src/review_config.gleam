import rule.{type Rule}
import rules/no_deprecated
import rules/no_panic
import rules/no_trailing_underscore
import rules/no_unnecessary_string_concatenation

pub fn config() -> List(Rule) {
  [
    no_panic.rule(),
    no_unnecessary_string_concatenation.rule(),
    no_trailing_underscore.rule(),
    no_deprecated.rule(),
  ]
}

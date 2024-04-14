import code_review/rule.{type Rule}
import code_review/rules/no_deprecated
import code_review/rules/no_panic
import code_review/rules/no_trailing_underscore
import code_review/rules/no_unnecessary_string_concatenation

pub fn config() -> List(Rule) {
  [
    no_panic.rule(),
    no_unnecessary_string_concatenation.rule(),
    no_trailing_underscore.rule(),
    no_deprecated.rule(),
  ]
}

import glance
import gleam/option
import rule.{type Rule, type RuleError, Rule}

pub const rule: Rule = Rule(
  name: "NoUnnecessaryStringConcatenation",
  expression_visitor: option.Some(unnecessary_concatenation_expression_visitor),
)

pub fn unnecessary_concatenation_expression_visitor(
  expr: glance.Expression,
) -> List(RuleError) {
  case expr {
    glance.BinaryOperator(glance.Concatenate, glance.String(""), _)
    | glance.BinaryOperator(glance.Concatenate, _, glance.String("")) -> {
      [
        rule.error(
          message: "Unnecessary concatenation with an empty string",
          details: [
            "The result of adding an empty string to an expression is the expression itself.",
            "You can remove the concatenation with \"\".",
          ],
        ),
      ]
    }
    glance.BinaryOperator(
        glance.Concatenate,
        glance.String(_),
        glance.String(_),
      ) -> {
      [
        rule.error(
          message: "Unnecessary concatenation of string literals",
          details: [
            "Instead of concatenating these two string literals, they can be written as a single one.",
            "For instance, instead of \"a\" <> \"b\", you could write that as \"ab\".",
          ],
        ),
      ]
    }
    _ -> []
  }
}

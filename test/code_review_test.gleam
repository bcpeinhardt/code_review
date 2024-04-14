import birdie
import code_review
import code_review/internal/project
import code_review/rule
import glance
import gleam/dict
import gleam/list
import gleam/string
import gleeunit
import review_config

pub fn main() {
  gleeunit.main()
}

fn test_example_source_no_gleam_toml(example_code src: String) -> String {
  let assert Ok(module) = glance.module(src)
  let project =
    project.Project(config: dict.new(), src_modules: [
      project.Module(name: "mocked", src: module),
    ])
  let rule_visitors =
    list.map(review_config.config(), fn(rule) { rule.module_visitor() })
  let errors = code_review.visit(project, rule_visitors)

  errors
  |> list.map(rule.pretty_print_error)
  |> string.join(with: "\n\n\n")
}

pub fn no_deprecated_test() {
  "
  pub fn main() {
    old_function()
    new_function()
  }

  @deprecated(\"Use new_function instead\")
  fn old_function() {
    Nil
  }

  fn new_function() {
    Nil
  }"
  |> test_example_source_no_gleam_toml
  |> birdie.snap("No Deprecated Functions Used")
}

pub fn basic_panic_test() {
  "
  pub fn this_code_panics() {
    panic as \"I freakin panic bro\"
  }"
  |> test_example_source_no_gleam_toml
  |> birdie.snap("No Panic Test")
}

pub fn no_trailing_underscore_test() {
  "
  pub fn with_trailing_() {
    1
  }

  pub fn without_trailing() {
    1
  }
  "
  |> test_example_source_no_gleam_toml
  |> birdie.snap("No Trailing Underscore Test")
}

pub fn no_panic_inside_use_call_test() {
  "
  import gleam/bool

  pub fn panic_in_use_call() {
    use <- bool.guard(True, panic as \"oops\")
    Nil
  }
  "
  |> test_example_source_no_gleam_toml
  |> birdie.snap("No Panic Inside Use Call")
}

pub fn no_panic_inside_use_test() {
  "
  import gleam/bool

  pub fn panic_inside_use() {
    use <- bool.guard(False, Nil)
    let _ = Nil
    panic as \"panic inside use\"
  }
  "
  |> test_example_source_no_gleam_toml
  |> birdie.snap("No Panic Inside Use")
}

pub fn no_unnecessary_empty_string_concatenation_test() {
  "
  pub fn concat_empty(a: String, b: String) {
    let _unused = a <> \"\"
    \"\" <> b
    }
  "
  |> test_example_source_no_gleam_toml
  |> birdie.snap("No Unnecessary Empty String Concatenation Test")
}

pub fn no_unnecessary_string_concatenation_test() {
  "
  pub fn string_concatenation() {
    \"a\" <> \"b\"
  }

  pub fn no_string_concatenation_to_report(var: String) {
    \"a\" <> var
  }
  "
  |> test_example_source_no_gleam_toml
  |> birdie.snap("No Unnecessary String Concatenation Test")
}

//// This is a module with bad gleam in it so I can simply run
//// the linter on this current project during the "prototyping" phase

import gleam/bool

pub fn this_code_panics() {
  panic as "I freakin panic bro"
}

pub fn panic_inside_use() {
  use <- bool.guard(False, Nil)
  Nil
  panic as "panic inside use"
}

pub fn panic_in_use_call() {
  use <- bool.guard(True, panic as "oops")
  Nil
}
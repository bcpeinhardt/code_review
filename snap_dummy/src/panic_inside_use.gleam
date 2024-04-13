import gleam/bool

pub fn panic_inside_use() {
  use <- bool.guard(False, Nil)
  let _ = Nil
  panic as "panic inside use"
}

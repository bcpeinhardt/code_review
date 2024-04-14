//// Read and parse all useful info about a Gleam project.
////

import filepath
import glance
import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import simplifile
import tom

// TYPES -----------------------------------------------------------------------

/// A Gleam project as seen by the linter.
///
pub type Project {
  Project(
    /// The project's source modules.
    ///
    src_modules: List(Module),
    /// The project's `gleam.toml`.
    ///
    config: Dict(String, tom.Toml),
  )
}

/// A Gleam project's parsed module.
///
pub type Module {
  Module(
    /// The "name" of the module is the path from the root of the project to the
    /// file with the `.gleam` ending removed.
    ///
    name: String,
    /// The parsed source code in the module.
    ///
    src: glance.Module,
  )
}

pub type Error {
  CannotListSrcModules(reason: simplifile.FileError, path: String)
  CannotReadSrcModule(reason: simplifile.FileError, path: String)
  CannotParseSrcModule(reason: glance.Error, path: String)
  CannotReadConfig(reason: simplifile.FileError, path: String)
  CannotParseConfig(reason: tom.ParseError)
}

// READING A PROJECT -----------------------------------------------------------

/// Reads in all the information the linter needs from the project.
///
pub fn read(from path: String) -> Result(Project, Error) {
  use config <- result.try(read_config(path))
  use src_modules <- result.try(read_src_modules(path))
  Ok(Project(src_modules, config))
}

fn read_config(root: String) -> Result(Dict(String, tom.Toml), Error) {
  let config_path = filepath.join(root, "gleam.toml")

  use raw_config <- result.try(
    simplifile.read(config_path)
    |> result.map_error(CannotReadConfig(_, config_path)),
  )

  tom.parse(raw_config)
  |> result.map_error(CannotParseConfig)
}

fn read_src_modules(root: String) -> Result(List(Module), Error) {
  let src_path = filepath.join(root, "src")

  use src_files <- result.try(
    simplifile.get_files(src_path)
    |> result.map_error(CannotListSrcModules(_, src_path)),
  )

  list.try_map(src_files, read_src_module)
}

fn read_src_module(from path: String) -> Result(Module, Error) {
  use raw_src_module <- result.try(
    simplifile.read(path)
    |> result.map_error(CannotReadSrcModule(_, path)),
  )

  use ast <- result.try(
    glance.module(raw_src_module)
    |> result.map_error(CannotParseSrcModule(_, path)),
  )

  Ok(Module(path, ast))
}

// ERROR REPORTING -------------------------------------------------------------

pub fn explain_error(error: Error) -> String {
  case error {
    CannotListSrcModules(..) -> todo as "properly explain CannotListSrcModules"
    CannotReadSrcModule(..) -> todo as "properly explain CannotReadSrcModule"
    CannotParseSrcModule(..) -> todo as "properly explain CannotParseSrcModule"
    CannotReadConfig(..) -> todo as "properly explain CannotReadConfig"
    CannotParseConfig(..) -> todo as "properly explain CannotParseConfig"
  }
}

// UTILS -----------------------------------------------------------------------

/// Finds the path leading to the project's root folder. This recursively walks
/// up from the current directory until it finds a `gleam.toml`.
///
/// This is needed since `gleam run` can be run anywhere inside the project!
///
pub fn root() -> String {
  find_root(".")
}

fn find_root(path: String) -> String {
  let toml = filepath.join(path, "gleam.toml")

  case simplifile.verify_is_file(toml) {
    Ok(False) | Error(_) -> find_root(filepath.join("..", path))
    Ok(True) -> path
  }
}

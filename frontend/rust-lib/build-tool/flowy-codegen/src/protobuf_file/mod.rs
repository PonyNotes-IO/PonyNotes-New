#![allow(unused_imports)]
#![allow(unused_attributes)]
#![allow(dead_code)]
mod ast;
mod proto_gen;
mod proto_info;
mod template;

use crate::Project;
use crate::util::path_string_with_component;
use itertools::Itertools;
use log::info;
pub use proto_gen::*;
pub use proto_info::*;
use std::fs;
use std::fs::File;
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::process::Command;
use walkdir::WalkDir;

pub fn dart_gen(crate_name: &str) {
  // 1. generate the proto files to proto_file_dir
  #[cfg(feature = "proto_gen")]
  let proto_crates = gen_proto_files(crate_name);

  for proto_crate in proto_crates {
    let mut proto_file_paths = vec![];
    let mut file_names = vec![];
    let proto_file_output_path = proto_crate
      .proto_output_path()
      .to_str()
      .unwrap()
      .to_string();
    let protobuf_output_path = proto_crate
      .protobuf_crate_path()
      .to_str()
      .unwrap()
      .to_string();

    for (path, file_name) in WalkDir::new(&proto_file_output_path)
      .into_iter()
      .filter_map(|e| e.ok())
      .map(|e| {
        let path = e.path().to_str().unwrap().to_string();
        let file_name = e.path().file_stem().unwrap().to_str().unwrap().to_string();
        (path, file_name)
      })
    {
      if path.ends_with(".proto") {
        // https://stackoverflow.com/questions/49077147/how-can-i-force-build-rs-to-run-again-without-cleaning-my-whole-project
        println!("cargo:rerun-if-changed={}", path);
        proto_file_paths.push(path);
        file_names.push(file_name);
      }
    }
    // 无 .proto 文件时跳过 protoc，避免空输入导致失败
    if proto_file_paths.is_empty() {
      continue;
    }

    let protoc_bin_path = protoc_bin_vendored::protoc_bin_path().unwrap();

    // 2. generate the protobuf files(Dart)
    #[cfg(feature = "dart")]
    generate_dart_protobuf_files(
      crate_name,
      &proto_file_output_path,
      &proto_file_paths,
      &file_names,
      &protoc_bin_path,
    );

    // 3. generate the protobuf files(Rust)
    generate_rust_protobuf_files(
      &protoc_bin_path,
      &proto_file_paths,
      &proto_file_output_path,
      &protobuf_output_path,
    );
  }
}

// #[allow(unused_variables)]
// fn ts_gen(crate_name: &str, dest_folder_name: &str, project: Project) {
//   // 1. generate the proto files to proto_file_dir
//   #[cfg(feature = "proto_gen")]
//   let proto_crates = gen_proto_files(crate_name);
//
//   for proto_crate in proto_crates {
//     let mut proto_file_paths = vec![];
//     let mut file_names = vec![];
//     let proto_file_output_path = proto_crate
//       .proto_output_path()
//       .to_str()
//       .unwrap()
//       .to_string();
//     let protobuf_output_path = proto_crate
//       .protobuf_crate_path()
//       .to_str()
//       .unwrap()
//       .to_string();
//
//     for (path, file_name) in WalkDir::new(&proto_file_output_path)
//       .into_iter()
//       .filter_map(|e| e.ok())
//       .map(|e| {
//         let path = e.path().to_str().unwrap().to_string();
//         let file_name = e.path().file_stem().unwrap().to_str().unwrap().to_string();
//         (path, file_name)
//       })
//     {
//       if path.ends_with(".proto") {
//         // https://stackoverflow.com/questions/49077147/how-can-i-force-build-rs-to-run-again-without-cleaning-my-whole-project
//         println!("cargo:rerun-if-changed={}", path);
//         proto_file_paths.push(path);
//         file_names.push(file_name);
//       }
//     }
//     let protoc_bin_path = protoc_bin_vendored::protoc_bin_path().unwrap();
//
//     // 2. generate the protobuf files(Dart)
//     #[cfg(feature = "ts")]
//     generate_ts_protobuf_files(
//       dest_folder_name,
//       &proto_file_output_path,
//       &proto_file_paths,
//       &file_names,
//       &protoc_bin_path,
//       &project,
//     );
//
//     // 3. generate the protobuf files(Rust)
//     generate_rust_protobuf_files(
//       &protoc_bin_path,
//       &proto_file_paths,
//       &proto_file_output_path,
//       &protobuf_output_path,
//     );
//   }
// }

fn generate_rust_protobuf_files(
  protoc_bin_path: &Path,
  proto_file_paths: &[String],
  proto_file_output_path: &str,
  protobuf_output_path: &str,
) {
  protoc_rust::Codegen::new()
    .out_dir(protobuf_output_path)
    .protoc_path(protoc_bin_path)
    .inputs(proto_file_paths)
    .include(proto_file_output_path)
    .run()
    .expect("Running rust protoc failed.");
  remove_box_pointers_lint_from_all_except_mod(protobuf_output_path);
}
fn remove_box_pointers_lint_from_all_except_mod(dir_path: &str) {
  let dir = fs::read_dir(dir_path).expect("Failed to read directory");
  for entry in dir {
    let entry = entry.expect("Failed to read directory entry");
    let path = entry.path();

    // Skip directories and mod.rs
    if path.is_file() {
      if let Some(file_name) = path.file_name().and_then(|f| f.to_str()) {
        if file_name != "mod.rs" {
          remove_box_pointers_lint(&path);
        }
      }
    }
  }
}

fn remove_box_pointers_lint(file_path: &Path) {
  let file = File::open(file_path).expect("Failed to open file");
  let reader = BufReader::new(file);
  let lines: Vec<String> = reader
    .lines()
    .map_while(Result::ok)
    .filter(|line| !line.contains("#![allow(box_pointers)]"))
    .collect();

  let mut file = File::create(file_path).expect("Failed to create file");
  for line in lines {
    writeln!(file, "{}", line).expect("Failed to write line");
  }
}

#[cfg(feature = "ts")]
fn generate_ts_protobuf_files(
  name: &str,
  proto_file_output_path: &str,
  paths: &[String],
  file_names: &Vec<String>,
  protoc_bin_path: &Path,
  project: &Project,
) {
  let root = project.model_root();
  let backend_service_path = project.dst();

  let mut output = PathBuf::new();
  output.push(root);
  output.push(backend_service_path);
  output.push("models");
  output.push(name);

  if !output.as_path().exists() {
    std::fs::create_dir_all(&output).unwrap();
  }
  let protoc_bin_path = protoc_bin_path.to_str().unwrap().to_owned();
  paths.iter().for_each(|path| {
    // if let Err(err) = Command::new(protoc_bin_path.clone())
    //   .arg(format!("--ts_out={}", output.to_str().unwrap()))
    //   .arg(format!("--proto_path={}", proto_file_output_path))
    //   .arg(path)
    //   .spawn()
    // {
    //   panic!("Generate ts pb file failed: {}, {:?}", path, err);
    // }

    println!("cargo:rerun-if-changed={}", output.to_str().unwrap());
    let result = cmd_lib::run_cmd! {
        ${protoc_bin_path} --ts_out=${output} --proto_path=${proto_file_output_path} ${path}
    };

    if result.is_err() {
      panic!("Generate ts pb file failed with: {}, {:?}", path, result)
    };
  });

  let ts_index = path_string_with_component(&output, vec!["index.ts"]);
  match std::fs::OpenOptions::new()
    .create(true)
    .write(true)
    .append(false)
    .truncate(true)
    .open(ts_index)
  {
    Ok(ref mut file) => {
      let mut export = String::new();
      export.push_str("// Auto-generated, do not edit \n");
      for file_name in file_names {
        let c = format!("export * from \"./{}\";\n", file_name);
        export.push_str(c.as_ref());
      }

      file.write_all(export.as_bytes()).unwrap();
      File::flush(file).unwrap();
    },
    Err(err) => {
      panic!("Failed to open file: {}", err);
    },
  }
}

/// 若未设置 CARGO_MAKE_WORKING_DIRECTORY / FLUTTER_FLOWY_SDK_PATH，则从 CARGO_MANIFEST_DIR
/// 向上查找包含 appflowy_flutter 的目录作为 frontend 根，使直接 cargo build 也能生成 Dart。
#[cfg(feature = "dart")]
fn resolve_dart_output_base() -> Option<(PathBuf, String)> {
  let from_work = std::env::var("CARGO_MAKE_WORKING_DIRECTORY").ok();
  let from_sdk = std::env::var("FLUTTER_FLOWY_SDK_PATH").ok();
  if let (Some(work), Some(sdk)) = (from_work, from_sdk) {
    return Some((PathBuf::from(&work), sdk));
  }
  let manifest_dir = std::env::var("CARGO_MANIFEST_DIR").ok()?;
  let mut dir = PathBuf::from(manifest_dir);
  let sdk_subpath = "appflowy_flutter/packages/appflowy_backend";
  loop {
    if dir.join("appflowy_flutter").exists() {
      // On Windows, canonicalize() returns paths with \\?\ prefix which breaks protoc
      // So we skip canonicalize on Windows and use the raw path
      #[cfg(target_os = "windows")]
      {
        return Some((dir, sdk_subpath.to_string()));
      }
      #[cfg(not(target_os = "windows"))]
      {
        if let Ok(canon) = dir.canonicalize() {
          return Some((canon, sdk_subpath.to_string()));
        }
        return Some((dir, sdk_subpath.to_string()));
      }
    }
    if !dir.pop() {
      break;
    }
  }
  None
}

#[cfg(feature = "dart")]
fn generate_dart_protobuf_files(
  name: &str,
  proto_file_output_path: &str,
  paths: &[String],
  file_names: &Vec<String>,
  protoc_bin_path: &Path,
) {
  let (working_dir, sdk_path) = match resolve_dart_output_base() {
    Some(p) => p,
    None => {
      log::error!(
        "Dart pb output unknown: set CARGO_MAKE_WORKING_DIRECTORY and FLUTTER_FLOWY_SDK_PATH, \
         or run from frontend (directory containing appflowy_flutter). Skip generate dart pb."
      );
      return;
    },
  };

  let mut output = PathBuf::new();
  output.push(working_dir);
  output.push(&sdk_path);
  output.push("lib");
  output.push("protobuf");
  output.push(name);

  if !output.as_path().exists() {
    std::fs::create_dir_all(&output).unwrap();
  }
  if !check_pb_dart_plugin() {
    log::warn!("Skip Dart pb generation: protoc-gen-dart not in PATH. Install with: dart pub global activate protoc_plugin");
    return;
  }
  let protoc_bin_path = protoc_bin_path.to_str().unwrap().to_owned();
  paths.iter().for_each(|path| {
    let result = cmd_lib::run_cmd! {
        ${protoc_bin_path} --dart_out=${output} --proto_path=${proto_file_output_path} ${path}
    };

    if result.is_err() {
      panic!("Generate dart pb file failed with: {}, {:?}", path, result)
    };
  });

  let protobuf_dart = path_string_with_component(&output, vec!["protobuf.dart"]);
  println!("cargo:rerun-if-changed={}", protobuf_dart);
  match std::fs::OpenOptions::new()
    .create(true)
    .write(true)
    .append(false)
    .truncate(true)
    .open(Path::new(&protobuf_dart))
  {
    Ok(ref mut file) => {
      let mut export = String::new();
      export.push_str("// Auto-generated, do not edit \n");
      for file_name in file_names {
        let c = format!("export './{}.pb.dart';\n", file_name);
        export.push_str(c.as_ref());
      }

      file.write_all(export.as_bytes()).unwrap();
      File::flush(file).unwrap();
    },
    Err(err) => {
      panic!("Failed to open file: {}", err);
    },
  }
}

/// 检查 protoc-gen-dart 是否在 PATH 中。返回 true 表示可用，false 则跳过 Dart 生成（不 panic，便于构建通过）。
pub fn check_pb_dart_plugin() -> bool {
  if cfg!(target_os = "windows") {
    true
  } else {
    let exit_result = Command::new("sh")
      .arg("-c")
      .arg("command -v protoc-gen-dart")
      .status();

    match exit_result {
      Ok(s) if s.success() => true,
      _ => {
        log::warn!(
          "protoc-gen-dart not in PATH. Add: export PATH=\"$PATH\":\"$HOME/.pub-cache/bin\""
        );
        false
      },
    }
  }
}

#[cfg(feature = "proto_gen")]
pub fn gen_proto_files(crate_name: &str) -> Vec<ProtobufCrate> {
  let crate_path = std::fs::canonicalize(".")
    .unwrap()
    .as_path()
    .display()
    .to_string();

  let crate_context = ProtoGenerator::r#gen(crate_name, &crate_path);
  let proto_crates = crate_context
    .iter()
    .map(|info| info.protobuf_crate.clone())
    .collect::<Vec<_>>();

  crate_context
    .into_iter()
    .flat_map(|info| info.files)
    .for_each(|file| {
      println!("cargo:rerun-if-changed={}", file.file_path);
    });

  proto_crates
}

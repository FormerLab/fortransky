cmake_minimum_required(VERSION 3.16)
project(fortransky LANGUAGES C Fortran)

set(CMAKE_Fortran_STANDARD 2008)
set(CMAKE_Fortran_STANDARD_REQUIRED ON)

find_package(PkgConfig REQUIRED)
pkg_check_modules(LIBCURL REQUIRED libcurl)

# Rust firehose bridge static library
set(FIREHOSE_BRIDGE_DIR "${CMAKE_SOURCE_DIR}/bridge/firehose-bridge")
set(FIREHOSE_BRIDGE_LIB "${FIREHOSE_BRIDGE_DIR}/target/release/libfortransky_firehose_bridge.a")

add_custom_target(firehose_bridge_rust
  COMMAND cargo build --release
  WORKING_DIRECTORY "${FIREHOSE_BRIDGE_DIR}"
  BYPRODUCTS "${FIREHOSE_BRIDGE_LIB}"
  COMMENT "Building Rust firehose bridge"
)

add_library(firehose_bridge_static STATIC IMPORTED)
set_target_properties(firehose_bridge_static PROPERTIES
  IMPORTED_LOCATION "${FIREHOSE_BRIDGE_LIB}"
)
add_dependencies(firehose_bridge_static firehose_bridge_rust)

add_executable(fortransky
  cshim/http_bridge.c
  src/util/strings.f90
  src/util/process.f90
  src/util/dither.f90
  src/core/models.f90
  src/core/config.f90
  src/core/app_state.f90
  src/core/post_store.f90
  src/storage/log_store.f90
  src/atproto/http_cbridge.f90
  src/atproto/json_extract.f90
  src/atproto/decode.f90
  src/atproto/client.f90
  src/atproto/firehose_bridge.f90
  src/ui/tui.f90
  src/app/main.f90
)

add_dependencies(fortransky firehose_bridge_rust)

target_include_directories(fortransky PRIVATE
  ${LIBCURL_INCLUDE_DIRS}
  "${CMAKE_SOURCE_DIR}/cshim"
)
target_link_libraries(fortransky PRIVATE
  ${LIBCURL_LIBRARIES}
  firehose_bridge_static
  # Rust stdlib deps needed when linking a Rust staticlib from C/Fortran
  dl
  pthread
  m
)
target_compile_options(fortransky PRIVATE ${LIBCURL_CFLAGS_OTHER})
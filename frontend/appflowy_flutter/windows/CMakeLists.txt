cmake_minimum_required(VERSION 3.14)
project(appflowy_flutter LANGUAGES CXX)

set(BINARY_NAME "PonyNotes")

# 抑制 flutter_inappwebview_windows、media_kit_libs_windows_video 等插件的 CMP0175 警告
if(POLICY CMP0175)
  cmake_policy(SET CMP0175 OLD)
endif()
cmake_policy(SET CMP0063 NEW)

set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

# Configure build options.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)

if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()

set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")

# Bundle a copy of the installed WebView2 Runtime outside the system-managed
# EdgeWebView directory so startup can avoid the sticky system runtime.
set(PONYNOTES_BUNDLED_WEBVIEW2_SOURCE_DIR "" CACHE PATH
  "Optional WebView2 runtime folder to package next to PonyNotes.exe")
if(NOT PONYNOTES_BUNDLED_WEBVIEW2_SOURCE_DIR)
  set(PONYNOTES_WEBVIEW2_INSTALL_ROOT
    "C:/Program Files (x86)/Microsoft/EdgeWebView/Application")
  if(EXISTS "${PONYNOTES_WEBVIEW2_INSTALL_ROOT}")
    file(GLOB PONYNOTES_WEBVIEW2_RUNTIME_CANDIDATES
      RELATIVE "${PONYNOTES_WEBVIEW2_INSTALL_ROOT}"
      "${PONYNOTES_WEBVIEW2_INSTALL_ROOT}/*")
    set(PONYNOTES_WEBVIEW2_BEST_VERSION "")
    foreach(candidate ${PONYNOTES_WEBVIEW2_RUNTIME_CANDIDATES})
      if(candidate MATCHES "^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$"
         AND EXISTS "${PONYNOTES_WEBVIEW2_INSTALL_ROOT}/${candidate}/msedgewebview2.exe")
        if(NOT PONYNOTES_WEBVIEW2_BEST_VERSION
           OR "${candidate}" VERSION_GREATER "${PONYNOTES_WEBVIEW2_BEST_VERSION}")
          set(PONYNOTES_WEBVIEW2_BEST_VERSION "${candidate}")
        endif()
      endif()
    endforeach()

    if(PONYNOTES_WEBVIEW2_BEST_VERSION)
      set(PONYNOTES_BUNDLED_WEBVIEW2_SOURCE_DIR
        "${PONYNOTES_WEBVIEW2_INSTALL_ROOT}/${PONYNOTES_WEBVIEW2_BEST_VERSION}")
    endif()
  endif()
endif()

if(PONYNOTES_BUNDLED_WEBVIEW2_SOURCE_DIR)
  message(STATUS "Bundling WebView2 runtime from: ${PONYNOTES_BUNDLED_WEBVIEW2_SOURCE_DIR}")
else()
  message(STATUS "No WebView2 runtime bundle source detected; PonyNotes will use the system runtime")
endif()

# Flutter library and tool build rules.
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build
add_subdirectory("runner")

# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)

# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")

# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)

if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(DART_FFI_DIR "${CMAKE_INSTALL_PREFIX}")
set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${DART_FFI_DLL}" DESTINATION "${DART_FFI_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)

if(PONYNOTES_BUNDLED_WEBVIEW2_SOURCE_DIR
   AND EXISTS "${PONYNOTES_BUNDLED_WEBVIEW2_SOURCE_DIR}/msedgewebview2.exe")
  install(DIRECTORY "${PONYNOTES_BUNDLED_WEBVIEW2_SOURCE_DIR}/"
    DESTINATION "${CMAKE_INSTALL_PREFIX}/webview2_fixed"
    COMPONENT Runtime)
endif()

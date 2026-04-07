cmake_minimum_required(VERSION 3.10.0)

project(AppFlowy)

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Android-specific settings
set(CMAKE_ANDROID_ARCH_ABI "arm64-v8a")
set(CMAKE_ANDROID_NDK "${ANDROID_NDK}")
set(CMAKE_ANDROID_STL_TYPE "c++_shared")

message(STATUS "NDK PATH: ${ANDROID_NDK}")
message(STATUS "CMake version: ${CMAKE_VERSION}")
message(STATUS "Android ABI: ${CMAKE_ANDROID_ARCH_ABI}")
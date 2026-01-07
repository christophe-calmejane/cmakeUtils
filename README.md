# CMake Utils
Copyright (C) 2020-2026, Emilien Vallot and Christophe Calmejane

## What is it?

CMake Utils is a collection of cmake scripts designed to improve developers productivity.

## How to use it?

The scripts are split in 2 parts:
 - Helper functions and macros
 - FindPackage modules

### Helper functions and macros

Use the cmake `include()` command to include the file containing the function or macro you want to use, then directly call your function or macro.

### FindPackage modules

Add the path to this repository's subfolder _modules_ to the `CMAKE_PREFIX_PATH` variable using `list(APPEND CMAKE_PREFIX_PATH path/to/modules)`

# Common Project Macros to help setup a CMake project

# Global variables (will be used by all projects), must be set after a global project() call (no language or version required though) and before including ProjectProperties.cmake
#  Mandatory variables:
#   CU_COMPANY_NAME: Name of your company
#   CU_PROJECT_PRODUCTDESCRIPTION: Short description of your project
#   CU_PROJECT_STARTING_YEAR: Year of first release
#   [macOS] CU_TEAM_IDENTIFIER: Team identifier for your company
#   [macOS] CU_BINARY_SIGNING_IDENTITY: Code signing identity for binaries
#   [macOS] CU_INSTALLER_SIGNING_IDENTITY: Code signing identity for the installer
#   [windows] CU_SIGNTOOL_OPTIONS: Signing options for binaries
#  Optional variables:
#   CU_PROJECT_FULL_NAME (Defaults to '${PROJECT_NAME}'): Full name of your project
#   CU_COMPANY_DOMAIN (Defaults to 'com'): Domain name of your company
#   CU_COMPANY_URL (Defaults to 'https://www.${LOWER:CU_COMPANY_NAME}.${LOWER:CU_COMPANY_DOMAIN}'): URL of your company
#   CU_PROJECT_URLABOUTINFO (Defaults to '${CU_COMPANY_URL}'): URL of your project
#   CU_PROJECT_CONTACT (Defautls to '${LOWER:PROJECT_NAME}@${LOWER:CU_COMPANY_NAME}.com'): Contact email of your project
#   CU_COPYRIGHT_HOLDER (Defaults to '${CU_COMPANY_NAME}'): Copyright holder of your project
#   CU_BETA_TAG (Defaults to '-beta'): Tag to append to the version number to indicate a beta version

# cu_setup_project method
#  This method is used to setup a project that can contain one or more targets. Some variables can be overridden before the call, otherwise the global variables are used.
#  Mandatory variables:
#   3rd argument to cu_setup_project: Overrides CU_PROJECT_PRODUCTDESCRIPTION
#  Optional variables:
#   CU_PROJECT_COMPANYNAME (Defaults to '${CU_COMPANY_NAME}'): Company name to use just for this project
#   CU_PROJECT_LEGALCOPYRIGHT (Defaults to '${CU_COPYRIGHT_HOLDER}'): Legal copyright holder to use just for this project
#   CU_PROJECT_READABLE_COPYRIGHT (Defaults to 'Copyright ${CU_PROJECT_STARTING_YEAR}-${CU_YEAR}, ${CU_COPYRIGHT_HOLDER}'): Copyright holder to use just for this project

# cu_setup_executable_options method
#  This method is used to setup the options for an executable target. Some variables can be overridden before the call, otherwise the global variables are used.
#  Optional variables:
#   CU_TARGET_BUNDLE_IDENTIFIER (Defaults to '${CU_REVERSE_DOMAIN_NAME}.\${TARGET_NAME}'): Bundle identifier for the executable

# cu_set_warning_flags method
#  This method is used to add specific warning flags to one or more targets.
#  Mandatory variables:
#   TARGETS <targets...>: List of targets to which the warning flags will be added. If 'ALL' is specified, all targets will be affected.
#   COMPILER <compiler>: Compiler to which the warning flags will be added (MSVC, CLANG, GCC)
#  Optional variables:
#   PRIVATE <flags...>: List of flags to add to the target's PRIVATE compile options
#   PUBLIC <flags...>: List of flags to add to the target's PUBLIC compile options

# Set this variable before the include guard so it's always correctly defined for the current repository
set(CU_ROOT_DIR "${PROJECT_SOURCE_DIR}") # Folder containing the main CMakeLists.txt for the current repository including this file

# Avoid multi inclusion of this file (cannot use include_guard as multiple copies of this file are included from multiple places)
if(CU_PROJECT_MACROS_INCLUDED)
	# We still want to include the local_definitions file if it exists
	include("local_definitions.cmake" OPTIONAL)
	return()
endif()
set(CU_PROJECT_MACROS_INCLUDED true)

# Some global variables
set(CU_TOP_LEVEL_SOURCE_DIR "${PROJECT_SOURCE_DIR}") # Folder containing the main CMakeLists.txt for the first repository including this file
set(CU_TOP_LEVEL_BINARY_DIR "${PROJECT_BINARY_DIR}") # Folder containing the top level binary files (CMake root output folder)
set(CMAKE_MACROS_FOLDER "${CMAKE_CURRENT_LIST_DIR}")
set(CU_TARGET_ARCH "32") # Legacy variable
if(CMAKE_SIZEOF_VOID_P EQUAL 8)
	set(CU_TARGET_ARCH "64")
endif()
set(CU_ARCH "UNKNOWN") # New variable to replace CU_TARGET_ARCH (will be computed later in the file)
set(CU_DOTNET_PLATFORM_TARGET "") # csproj "PlatformTarget" used for C# application projects (will be computed later in the file)
set(CU_DOTNET_RID_APP "") # csproj "RuntimeIdentifier" used for C# application projects, which must be an exact RID entry (will be computed later in the file)
set(CU_DOTNET_RID_NUGET "") # csproj "RuntimeIdentifier" used for C# NuGets, which can use RID Graph (will be computed later in the file)

if(NOT DEFINED PROJECT_NAME)
	message(FATAL_ERROR "project() must be called before including ProjectMacros.cmake")
endif()

# Default Component
set(CMAKE_INSTALL_DEFAULT_COMPONENT_NAME "${PROJECT_NAME}")

# Enable cmake folders
set_property(GLOBAL PROPERTY USE_FOLDERS ON)

# Configure installation path: we override the default installation path.
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
	set(CMAKE_INSTALL_PREFIX "./Install" CACHE PATH "default install path" FORCE)
endif()

# Convert installation path to absolute path (if not already)
if(NOT IS_ABSOLUTE "${CMAKE_INSTALL_PREFIX}")
	# Check for cmake minimum version
	cmake_minimum_required(VERSION 3.20) # cmake_path added in cmake 3.20
	cmake_path(ABSOLUTE_PATH CMAKE_INSTALL_PREFIX BASE_DIRECTORY "${CU_TOP_LEVEL_BINARY_DIR}" NORMALIZE OUTPUT_VARIABLE CMAKE_INSTALL_PREFIX)
endif()

# Setup "Release" build type, if not specified
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
	message(STATUS "Setting build type to 'Release' as none was specified.")
	set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Specifies the build type." FORCE)
endif()

# Include TargetSetupDeploy script
include(${CMAKE_CURRENT_LIST_DIR}/helpers/TargetSetupDeploy.cmake)

###############################################################################
# Internal functions
function(cu_private_detect_arch)
	# Compute build architecture
	if(CMAKE_SYSTEM_NAME STREQUAL "Windows")
		# Currently only detecting x86 and x64 on Windows (no ARM support yet)
		if(CMAKE_SIZEOF_VOID_P EQUAL 8)
			set(CU_ARCH "x64")
		else()
			set(CU_ARCH "x86")
		endif()
		set(CU_DOTNET_PLATFORM_TARGET "${CU_ARCH}")
		set(CU_DOTNET_RID_APP "win-${CU_ARCH}")
		set(CU_DOTNET_RID_NUGET "win-${CU_ARCH}") # To be changed to "win" if we support multi-arch someday

	elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin" OR CMAKE_SYSTEM_NAME STREQUAL "iOS")
		list(LENGTH CMAKE_OSX_ARCHITECTURES COUNT_ARCHS)
		# Extract the first architecture from CMAKE_OSX_ARCHITECTURES
		list(GET CMAKE_OSX_ARCHITECTURES 0 _OSX_ARCH)
		if(_OSX_ARCH STREQUAL "x86_64")
			set(CU_ARCH "x64")
		elseif(_OSX_ARCH STREQUAL "arm64")
			set(CU_ARCH "arm64")
		elseif(_OSX_ARCH STREQUAL "armv7")
			set(CU_ARCH "arm")
		elseif(_OSX_ARCH STREQUAL "armv7s")
			set(CU_ARCH "arm")
		else()
			message(FATAL_ERROR "Unsupported CMAKE_OSX_ARCHITECTURES: ${_OSX_ARCH}")
		endif()
		if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
			set(OS_NAME "osx")
		else()
			set(OS_NAME "ios") # Should actually be 'iossimulator' instead of 'ios' for iOS simulator
		endif()
		# If we build for multi-arch
		if(COUNT_ARCHS GREATER 1)
			set(CU_DOTNET_PLATFORM_TARGET "AnyCPU")
			set(CU_DOTNET_RID_APP "") # Not specifying a RID for multi-arch seems to be the best option, we let the runtime choose the best one (can still be overridden from the dotnet command line)
			set(CU_DOTNET_RID_NUGET "${OS_NAME}") # We should use the RID graph for this one, targetting all architectures for that OS
		else()
			set(CU_DOTNET_PLATFORM_TARGET "${CU_ARCH}")
			set(CU_DOTNET_RID_APP "${OS_NAME}-${CU_ARCH}") # Specifying the exact RID for the application
			set(CU_DOTNET_RID_NUGET "${OS_NAME}-${CU_ARCH}") # Specifying the exact RID for the NuGet
		endif()

	elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
		# Currently only detecting system architecture on Linux (not cross-compiling). We usually compile for the same architecture as the system.
		if(CMAKE_SYSTEM_PROCESSOR STREQUAL "x86_64")
			set(CU_ARCH "x64")
		elseif(CMAKE_SYSTEM_PROCESSOR STREQUAL "x86")
			set(CU_ARCH "x86")
		elseif(CMAKE_SYSTEM_PROCESSOR STREQUAL "aarch64")
			set(CU_ARCH "arm64")
		else()
			message(FATAL_ERROR "Unsupported CMAKE_SYSTEM_PROCESSOR: ${CMAKE_SYSTEM_PROCESSOR}")
		endif()
		set(CU_DOTNET_PLATFORM_TARGET "${CU_ARCH}")
		set(CU_DOTNET_RID_APP "linux-${CU_ARCH}")
		set(CU_DOTNET_RID_NUGET "linux-${CU_ARCH}") # To be changed to "linux" if we support multi-arch someday

	elseif(CMAKE_SYSTEM_NAME STREQUAL "Android")
		# Extract the first architecture from ANDROID_ABI
		list(GET ANDROID_ABI 0 _ANDROID_ARCH)
		if(_ANDROID_ARCH STREQUAL "x86_64")
			set(CU_ARCH "x64")
		elseif(_ANDROID_ARCH STREQUAL "arm64-v8a")
			set(CU_ARCH "arm64")
		else()
			message(FATAL_ERROR "Unsupported ANDROID_ABI: ${_ANDROID_ARCH}")
		endif()
		set(CU_DOTNET_PLATFORM_TARGET "${CU_ARCH}")
		set(CU_DOTNET_RID_APP "android-${CU_ARCH}")
		set(CU_DOTNET_RID_NUGET "android-${CU_ARCH}") # To be changed to "android" if we support multi-arch someday

	else()
		message(FATAL_ERROR "Unsupported CMAKE_SYSTEM_NAME: ${CMAKE_SYSTEM_NAME}")
	endif()

	# Check for cmake minimum version
	cmake_minimum_required(VERSION 3.25) # return(PROPAGATE) added in cmake 3.25
	cmake_policy(SET CMP0140 NEW)

	return(PROPAGATE CU_ARCH CU_DOTNET_PLATFORM_TARGET CU_DOTNET_RID_APP CU_DOTNET_RID_NUGET)
endfunction()

#
function(cu_private_set_warning_flags TARGET_NAME)
	# Get the compiler
	if(MSVC)
		set(COMPILER "MSVC")
	elseif(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
		set(COMPILER "CLANG")
	elseif(CMAKE_COMPILER_IS_GNUCC OR CMAKE_COMPILER_IS_GNUCXX)
		set(COMPILER "GCC")
	else()
		message(WARNING "cu_private_set_warning_flags: Unknown compiler")
		return()
	endif()

	# Get the ALL target flags and apply (if any)
	get_property(all_private_options GLOBAL PROPERTY CUWF_ALL_${COMPILER}_PRIVATE_COMPILE_OPTIONS)
	get_property(all_public_options GLOBAL PROPERTY CUWF_ALL_${COMPILER}_PUBLIC_COMPILE_OPTIONS)
	if(all_private_options)
		target_compile_options(${TARGET_NAME} PRIVATE ${all_private_options})
	endif()
	if(all_public_options)
		target_compile_options(${TARGET_NAME} PUBLIC ${all_public_options})
	endif()

	# Get the target flags and apply (if any)
	get_property(private_options GLOBAL PROPERTY CUWF_${TARGET_NAME}_${COMPILER}_PRIVATE_COMPILE_OPTIONS)
	get_property(public_options GLOBAL PROPERTY CUWF_${TARGET_NAME}_${COMPILER}_PUBLIC_COMPILE_OPTIONS)
	if(private_options)
		target_compile_options(${TARGET_NAME} PRIVATE ${private_options})
	endif()
	if(public_options)
		target_compile_options(${TARGET_NAME} PUBLIC ${public_options})
	endif()
endfunction()

#
function(cu_set_output_colorization TARGET_NAME)
	if(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
		target_compile_options(${TARGET_NAME} PRIVATE -fcolor-diagnostics)
	elseif(CMAKE_COMPILER_IS_GNUCC OR CMAKE_COMPILER_IS_GNUCXX)
		target_compile_options(${TARGET_NAME} PRIVATE -fdiagnostics-color=always)
	endif()
endfunction()

#
function(cu_private_set_default_warning_flags TARGET_NAME)
	if(MSVC)
		# Don't use Wall on MSVC, it prints too many stupid warnings
		target_compile_options(${TARGET_NAME} PRIVATE
			/WX # Treat warnings as errors
			/W4 # Warning level 4
			$<$<COMPILE_LANGUAGE:CXX>:/w14265> # Warn if a class has virtual functions but no virtual destructor
		)

	elseif(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
		target_compile_options(${TARGET_NAME} PRIVATE
			-Wall # Enable all warnings
			-Werror # Treat warnings as errors
			-Wextra # Enable extra warnings
			-Wpedantic # Enable pedantic warnings
			$<$<COMPILE_LANGUAGE:CXX>:-Wnon-virtual-dtor> # Warn if a class has virtual functions but no virtual destructor
			-Wfloat-conversion # Warn about float conversions
		)

	elseif(CMAKE_COMPILER_IS_GNUCC OR CMAKE_COMPILER_IS_GNUCXX)
		target_compile_options(${TARGET_NAME} PRIVATE
			-Wall # Enable all warnings
			-Werror # Treat warnings as errors
			-Wextra # Enable extra warnings
			-Wpedantic # Enable pedantic warnings
			$<$<COMPILE_LANGUAGE:CXX>:-Wnon-virtual-dtor> # Warn if a class has virtual functions but no virtual destructor
			-Wfloat-conversion # Warn about float conversions
		)
	else()
		message(WARNING "cu_private_set_default_warning_flags: Unknown compiler")
	endif()

	# Check for overrides
	cu_private_set_warning_flags(${TARGET_NAME})
endfunction()

#
function(cu_private_get_sign_command_options OUT_VAR)
	set(${OUT_VAR} SIGNTOOL_OPTIONS ${CU_SIGNTOOL_OPTIONS} /d \"${CU_COMPANY_NAME} ${PROJECT_NAME}\" CODESIGN_OPTIONS --timestamp --deep --strict --force --options=runtime CODESIGN_IDENTITY \"${CU_BINARY_SIGNING_IDENTITY}\" PARENT_SCOPE)
endfunction()

#
function(cu_private_get_target_resource_folder_name TARGET_NAME OUT_VAR)
	cu_is_macos_bundle(${TARGET_NAME} isBundle)
	if(${isBundle})
		set(${OUT_VAR} "Resources" PARENT_SCOPE)
	else()
		set(${OUT_VAR} "resources" PARENT_SCOPE)
	endif()
endfunction()

#
function(cu_private_get_target_resource_path_string TARGET_NAME OUT_VAR)
	cu_private_get_target_resource_folder_name(${TARGET_NAME} folderName)
	cu_is_macos_bundle(${TARGET_NAME} isBundle)
	if(${isBundle})
		set(${OUT_VAR} "$<TARGET_BUNDLE_CONTENT_DIR:${TARGET_NAME}>/${folderName}" PARENT_SCOPE)
	else()
		set(${OUT_VAR} "$<TARGET_FILE_DIR:${TARGET_NAME}>/${folderName}" PARENT_SCOPE)
	endif()
endfunction()

# Sign a binary after build, using POST_BUILD rules
# BINARY_NAME is only used to generate a unique cmake file
function(cu_private_sign_postbuild_binary TARGET_NAME BINARY_PATH BINARY_NAME)
	# Get signing options
	cu_private_get_sign_command_options(SIGN_COMMAND_OPTIONS)

	# Expand options to individual parameters
	string(REPLACE ";" " " SIGN_COMMAND_OPTIONS "${SIGN_COMMAND_OPTIONS}")

	cu_is_macos_bundle(${TARGET_NAME} isBundle)
	if(${isBundle})
		set(binary_path "$<TARGET_BUNDLE_DIR:${TARGET_NAME}>")
	else()
		set(binary_path "$<TARGET_FILE:${TARGET_NAME}>")
	endif()

	# Generate code-signing code
	string(CONCAT CODESIGNING_CODE
		"include(\"${CMAKE_MACROS_FOLDER}/helpers/SignBinary.cmake\")\n"
		"cu_sign_binary(BINARY_PATH \"${BINARY_PATH}\" ${SIGN_COMMAND_OPTIONS})\n"
	)

	# Write to a cmake file
	set(CODESIGN_SCRIPT ${CMAKE_CURRENT_BINARY_DIR}/codesign_$<CONFIG>_${BINARY_NAME}.cmake)
	file(GENERATE
		OUTPUT ${CODESIGN_SCRIPT}
		CONTENT ${CODESIGNING_CODE}
	)
	# Run the codesign script as POST_BUILD command on the target
	add_custom_command(TARGET ${TARGET_NAME}
		POST_BUILD
		COMMAND ${CMAKE_COMMAND} -P ${CODESIGN_SCRIPT}
		VERBATIM
	)
endfunction()

# Sign a binary after installation, using install rules
function(cu_private_sign_installed_binary BINARY_PATH)
	# Xcode already forces automatic signing, so only sign for the other cases
	if(NOT "${CMAKE_GENERATOR}" STREQUAL "Xcode")
		# Get signing options
		cu_private_get_sign_command_options(SIGN_COMMAND_OPTIONS)

		# Expand options to individual parameters
		string(REPLACE ";" " " SIGN_COMMAND_OPTIONS "${SIGN_COMMAND_OPTIONS}")

		# Generate code-signing code
		string(CONCAT CODESIGNING_CODE
			"include(\"${CMAKE_MACROS_FOLDER}/helpers/SignBinary.cmake\")\n"
			"get_filename_component(INSTALLED_PATH \"\${CMAKE_INSTALL_PREFIX}/${BINARY_PATH}\" ABSOLUTE BASE_DIR \"${CMAKE_BINARY_DIR}\")\n"
			"cu_sign_binary(BINARY_PATH \"\${INSTALLED_PATH}\" ${SIGN_COMMAND_OPTIONS})\n"
		)

		# Write as install rule
		install(CODE
			"${CODESIGNING_CODE}"
		)
	endif()
endfunction()

#
function(cu_private_setup_signing_command TARGET_NAME)
	# Parse optional arguments
	cmake_parse_arguments(CUPSSC "INSTALL;NO_POST_BUILD" "" "" ${ARGN})

	# Xcode already forces automatic signing, so only sign for the other cases
	if(NOT "${CMAKE_GENERATOR}" STREQUAL "Xcode")
		# Get signing options
		cu_private_get_sign_command_options(SIGN_COMMAND_OPTIONS)

		# Expand options to individual parameters
		string(REPLACE ";" " " SIGN_COMMAND_OPTIONS "${SIGN_COMMAND_OPTIONS}")

		cu_is_macos_bundle(${TARGET_NAME} isBundle)
		if(${isBundle})
			set(binary_path "$<TARGET_BUNDLE_DIR:${TARGET_NAME}>")
		else()
			set(binary_path "$<TARGET_FILE:${TARGET_NAME}>")
		endif()

		# Generate code-signing code
		string(CONCAT CODESIGNING_CODE
			"include(\"${CMAKE_MACROS_FOLDER}/helpers/SignBinary.cmake\")\n"
			"cu_sign_binary(BINARY_PATH \"${binary_path}\" ${SIGN_COMMAND_OPTIONS})\n"
		)

		# Write to a cmake file
		if(NOT ${CUPSSC_NO_POST_BUILD})
			set(CODESIGN_SCRIPT ${CMAKE_CURRENT_BINARY_DIR}/codesign_$<CONFIG>_${TARGET_NAME}.cmake)
			file(GENERATE
				OUTPUT ${CODESIGN_SCRIPT}
				CONTENT ${CODESIGNING_CODE}
			)
			# Run the codesign script as POST_BUILD command on the target
			add_custom_command(TARGET ${TARGET_NAME}
				POST_BUILD
				COMMAND ${CMAKE_COMMAND} -P ${CODESIGN_SCRIPT}
				VERBATIM
			)
		endif()

		# Write as install rule
		if(CUPSSC_INSTALL)
			install(CODE
				"${CODESIGNING_CODE}"
			)
		endif()
	endif()
endfunction()

###############################################################################
# Set parallel build
# Sets the parallel build option for IDE that supports it
# This is overridden when compiling from command line with "cmake --build"
function(cu_set_parallel_build TARGET_NAME)
	if(MSVC)
		target_compile_options(${TARGET_NAME} PRIVATE /MP)
	endif()
endfunction()

###############################################################################
# Set TARGET_SYSTEM_xxx compile definition
function(cu_set_target_system_definition TARGET_NAME)
	if(CMAKE_SYSTEM_NAME STREQUAL "Windows")
		set(TARGET_SYSTEM_NAME "TARGET_SYSTEM_WINDOWS")
	elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
		set(TARGET_SYSTEM_NAME "TARGET_SYSTEM_DARWIN")
	elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
		set(TARGET_SYSTEM_NAME "TARGET_SYSTEM_LINUX")
	elseif(CMAKE_SYSTEM_NAME STREQUAL "iOS")
		set(TARGET_SYSTEM_NAME "TARGET_SYSTEM_IOS")
	elseif(CMAKE_SYSTEM_NAME STREQUAL "Android")
		set(TARGET_SYSTEM_NAME "TARGET_SYSTEM_ANDROID")
	else()
		message(FATAL_ERROR "Unknown CMAKE_SYSTEM_NAME: ${CMAKE_SYSTEM_NAME}")
	endif()

	target_compile_definitions(${TARGET_NAME} PRIVATE ${TARGET_SYSTEM_NAME})

endfunction()

###############################################################################
# Set maximum warning level, and treat warnings as errors
# Applies on a target, must be called after target has been defined with
# 'add_library' or 'add_executable'.
function(cu_set_maximum_warnings TARGET_NAME)
	if(MSVC)
		# Don't use Wall on MSVC, it prints too many stupid warnings
		target_compile_options(${TARGET_NAME} PRIVATE /W4 /WX)
		# Using clang-cl with MSVC (special case as MSBuild will convert MSVC Flags to Clang flags automatically)
		if(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
			target_compile_options(${TARGET_NAME} PRIVATE -Wno-nonportable-include-path -Wno-microsoft-include)
		endif()
	elseif(CMAKE_COMPILER_IS_GNUCC OR CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
		target_compile_options(${TARGET_NAME} PRIVATE -Wall -Werror -g)
	endif()
endfunction()

###############################################################################
# Set the warning flags for the target
function(cu_set_warning_flags)
	cmake_parse_arguments(CUSWF "" "COMPILER" "TARGETS;PRIVATE;PUBLIC" ${ARGN})

	# Check that mandatory arguments are set (ie. COMPILER and TARGETS)
	if(NOT CUSWF_COMPILER)
		message(FATAL_ERROR "cu_set_warning_flags: COMPILER argument is mandatory")
	endif()
	if(NOT CUSWF_TARGETS)
		message(FATAL_ERROR "cu_set_warning_flags: TARGETS argument is mandatory")
	endif()

	# Check that COMPILER is valid (ie. MSVC, CLANG, GCC)
	if(NOT CUSWF_COMPILER STREQUAL "MSVC" AND NOT CUSWF_COMPILER STREQUAL "CLANG" AND NOT CUSWF_COMPILER STREQUAL "GCC")
		message(FATAL_ERROR "cu_set_warning_flags: COMPILER argument must be MSVC, CLANG or GCC")
	endif()

	foreach(target ${CUSWF_TARGETS})
		# Store the flags in global properties (only if set)
		if(CUSWF_PRIVATE)
			set_property(GLOBAL PROPERTY CUWF_${target}_${CUSWF_COMPILER}_PRIVATE_COMPILE_OPTIONS ${CUSWF_PRIVATE})
		endif()
		if(CUSWF_PUBLIC)
			set_property(GLOBAL PROPERTY CUWF_${target}_${CUSWF_COMPILER}_PUBLIC_COMPILE_OPTIONS ${CUSWF_PUBLIC})
		endif()
	endforeach()
endfunction()

###############################################################################
# Set the DEBUG define in debug mode
# Applies on a target, must be called after target has been defined with
# 'add_library' or 'add_executable'.
function(cu_set_debug_define TARGET_NAME)
	# Flags to add for DEBUG
	target_compile_options(${TARGET_NAME} PRIVATE $<$<CONFIG:Debug>:-DDEBUG>)
endfunction()

###############################################################################
# Remove VisualStudio useless deprecated warnings (CRT, CRT_SECURE, WINSOCK)
# Applies on a target, must be called after target has been defined with
# 'add_library' or 'add_executable'.
function(cu_remove_vs_deprecated_warnings TARGET_NAME)
	if(MSVC)
		target_compile_options(${TARGET_NAME} PRIVATE -D_CRT_SECURE_NO_DEPRECATE -D_CRT_SECURE_NO_WARNINGS -D_WINSOCK_DEPRECATED_NO_WARNINGS)
	endif()
endfunction()

###############################################################################
# Returns TRUE if TARGET is a macOS/iOS framework library
function(cu_is_macos_framework TARGET_NAME IS_FRAMEWORK)
	if(APPLE)
		get_target_property(isFramework ${TARGET_NAME} FRAMEWORK)
		if(${isFramework})
			set(${IS_FRAMEWORK} TRUE PARENT_SCOPE)
			return()
		endif()
	endif()
	set(${IS_FRAMEWORK} FALSE PARENT_SCOPE)
endfunction()

###############################################################################
# Returns TRUE if TARGET is a macOS bundle application
function(cu_is_macos_bundle TARGET_NAME IS_BUNDLE)
	if(APPLE)
		get_target_property(isBundle ${TARGET_NAME} MACOSX_BUNDLE)
		if(${isBundle})
			set(${IS_BUNDLE} TRUE PARENT_SCOPE)
			return()
		endif()
	endif()
	set(${IS_BUNDLE} FALSE PARENT_SCOPE)
endfunction()

###############################################################################
# Force symbols file generation for build configs (pdb or dSYM)
# Applies on a target, must be called after target has been defined with
# 'add_library' or 'add_executable'.
function(cu_force_symbols_file TARGET_NAME)
	get_target_property(targetType ${TARGET_NAME} TYPE)

	if(MSVC)
		target_compile_options(${TARGET_NAME} PRIVATE /Zi)
		set_target_properties(${TARGET_NAME} PROPERTIES LINK_FLAGS_RELEASE "/DEBUG /OPT:REF /OPT:ICF /INCREMENTAL:NO")
	elseif(APPLE)
		target_compile_options(${TARGET_NAME} PRIVATE -g)

		if("${CMAKE_GENERATOR}" STREQUAL "Xcode")
			if(${targetType} STREQUAL "STATIC_LIBRARY")
				# macOS do not support dSYM file for static libraries
				set_target_properties(${TARGET_NAME} PROPERTIES
					XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT[variant=Debug] "dwarf"
					XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT[variant=Release] "dwarf"
					XCODE_ATTRIBUTE_DEPLOYMENT_POSTPROCESSING[variant=Debug] "NO"
					XCODE_ATTRIBUTE_DEPLOYMENT_POSTPROCESSING[variant=Release] "NO"
				)
			else()
				# Currently Xcode does not inject the get-task-allow entitlement for executables that have
				# DEPLOYMENT_POSTPROCESSING set to YES. This prevents debugging, which is extremely annoying.
				# So set DEPLOYMENT_POSTPROCESSING to NO for debug builds (this means the binary won't be striped)
				# Bug report submited to Apple: https://feedbackassistant.apple.com/feedback/9219851
				set_target_properties(${TARGET_NAME} PROPERTIES
					XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT[variant=Debug] "dwarf-with-dsym"
					XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT[variant=Release] "dwarf-with-dsym"
					XCODE_ATTRIBUTE_DEPLOYMENT_POSTPROCESSING[variant=Debug] "NO"
					XCODE_ATTRIBUTE_DEPLOYMENT_POSTPROCESSING[variant=Release] "YES"
				)
			endif()
		else()
			# If not using Xcode, we have to do the dSYM/strip steps manually (but only for binary targets)
			if(${targetType} STREQUAL "SHARED_LIBRARY")
				cu_is_macos_framework(${TARGET_NAME} isFramework)
				if(${isFramework})
					set(DSYM_DST "$<TARGET_BUNDLE_DIR:${TARGET_NAME}>.dSYM")
				else()
					set(DSYM_DST "$<TARGET_FILE:${TARGET_NAME}>.dSYM")
				endif()
			elseif(${targetType} STREQUAL "EXECUTABLE")
				cu_is_macos_bundle(${TARGET_NAME} isBundle)
				if(${isBundle})
					set(DSYM_DST "$<TARGET_BUNDLE_DIR:${TARGET_NAME}>.dSYM")
				else()
					set(DSYM_DST "$<TARGET_FILE:${TARGET_NAME}>.dSYM")
				endif()
			endif()
			if(DEFINED DSYM_DST)
				add_custom_command(
					TARGET ${TARGET_NAME}
					POST_BUILD
					COMMAND dsymutil "$<TARGET_FILE:${TARGET_NAME}>" -o "${DSYM_DST}"
					COMMENT "Extracting dSYM for ${TARGET_NAME}"
					VERBATIM
				)
				add_custom_command(
					TARGET ${TARGET_NAME}
					POST_BUILD
					COMMAND strip -x "$<TARGET_FILE:${TARGET_NAME}>"
					COMMENT "Stripping symbols from ${TARGET_NAME}"
					VERBATIM
				)
			endif()
		endif()
	elseif(CMAKE_COMPILER_IS_GNUCC OR CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
		target_compile_options(${TARGET_NAME} PRIVATE -g)
	endif()
endfunction()

###############################################################################
# Copy symbol files to a common location.
function(cu_copy_symbols TARGET_NAME)
	set(SYMBOLS_DEST_PATH "${CMAKE_BINARY_DIR}/Symbols/$<CONFIG>/")
	get_target_property(targetType ${TARGET_NAME} TYPE)
	if(MSVC)
		# No pdb files for static libraries, symbols are embedded in the lib
		if(NOT ${targetType} STREQUAL "STATIC_LIBRARY")
			add_custom_command(
				TARGET ${TARGET_NAME}
				POST_BUILD
				COMMAND ${CMAKE_COMMAND} -E make_directory "${SYMBOLS_DEST_PATH}"
				COMMAND ${CMAKE_COMMAND} -E copy "$<TARGET_PDB_FILE:${TARGET_NAME}>" "${SYMBOLS_DEST_PATH}"
				COMMENT "Copying ${TARGET_NAME} symbols"
				VERBATIM
			)
		endif()

	elseif(APPLE)
		if(${targetType} STREQUAL "SHARED_LIBRARY")
			cu_is_macos_framework(${TARGET_NAME} isFramework)
			if(${isFramework})
				set(DSYM_SRC "$<TARGET_BUNDLE_DIR:${TARGET_NAME}>.dSYM")
				set(DSYM_DST_NAME "$<TARGET_BUNDLE_DIR_NAME:${TARGET_NAME}>.dSYM")
				# Check for cmake minimum version
				cmake_minimum_required(VERSION 3.24) # TARGET_BUNDLE_DIR_NAME added in cmake 3.24
			else()
				set(DSYM_SRC "$<TARGET_FILE:${TARGET_NAME}>.dSYM")
				set(DSYM_DST_NAME "$<TARGET_FILE_NAME:${TARGET_NAME}>.dSYM")
			endif()
		elseif(${targetType} STREQUAL "EXECUTABLE")
			cu_is_macos_bundle(${TARGET_NAME} isBundle)
			if(${isBundle})
				set(DSYM_SRC "$<TARGET_BUNDLE_DIR:${TARGET_NAME}>.dSYM")
				set(DSYM_DST_NAME "$<TARGET_BUNDLE_DIR_NAME:${TARGET_NAME}>.dSYM")
				# Check for cmake minimum version
				cmake_minimum_required(VERSION 3.24) # TARGET_BUNDLE_DIR_NAME added in cmake 3.24
			else()
				set(DSYM_SRC "$<TARGET_FILE:${TARGET_NAME}>.dSYM")
				set(DSYM_DST_NAME "$<TARGET_FILE_NAME:${TARGET_NAME}>.dSYM")
			endif()
		endif()
		# Ignoring iOS until https://gitlab.kitware.com/cmake/cmake/-/issues/24161 is fixed
		if(DEFINED DSYM_SRC AND NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
			add_custom_command(
				TARGET ${TARGET_NAME}
				POST_BUILD
				COMMAND ${CMAKE_COMMAND} -E make_directory "${SYMBOLS_DEST_PATH}"
				COMMAND ${CMAKE_COMMAND} -E copy_directory "${DSYM_SRC}" "${SYMBOLS_DEST_PATH}${DSYM_DST_NAME}"
				COMMENT "Copying ${TARGET_NAME} symbols and extracting dSYM for ${TARGET_NAME}"
				VERBATIM
			)
		endif()
	endif()
endfunction()

###############################################################################
# Setup symbols for a target.
function(cu_setup_symbols TARGET_NAME)
	# Temporary workaround for Ninja always rebuilding the target when using POST_BUILD commands (https://gitlab.kitware.com/cmake/cmake/-/issues/26585)
	# Disable symbols when using Ninja on a SHARED_LIBRARY target for a Debug build
	if("${CMAKE_GENERATOR}" STREQUAL "Ninja" AND "${CMAKE_BUILD_TYPE}" STREQUAL "Debug")
		get_target_property(targetType ${TARGET_NAME} TYPE)
		if(${targetType} STREQUAL "SHARED_LIBRARY")
			message(WARNING "Disabling symbols for ${TARGET_NAME} in Debug build with Ninja generator")
			return()
		endif()
	endif()

	cmake_parse_arguments(CUSS "NO_COPY_DEBUG_SYMBOLS" "" "" ${ARGN})

	# Force symbols file generation
	cu_force_symbols_file(${TARGET_NAME})

	# Copy symbols to a common location
	if (NOT ${CUSS_NO_COPY_DEBUG_SYMBOLS})
		cu_copy_symbols(${TARGET_NAME})
	endif()
endfunction()

###############################################################################
# Setup Xcode automatic codesigning (required since Catalina).
function(cu_setup_xcode_codesigning TARGET_NAME)
	# Set codesigning for macOS
	if(APPLE)
		if("${CMAKE_GENERATOR}" STREQUAL "Xcode")
			# Force Xcode signing identity but only if defined to something valid (we will re-sign later anyway)
			if("${CU_TEAM_IDENTIFIER}" STREQUAL "-")
				set_target_properties(${TARGET_NAME} PROPERTIES XCODE_ATTRIBUTE_DEVELOPMENT_TEAM "")
				set_target_properties(${TARGET_NAME} PROPERTIES XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "YES")
				set_target_properties(${TARGET_NAME} PROPERTIES XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "-")
				set_target_properties(${TARGET_NAME} PROPERTIES XCODE_ATTRIBUTE_CODE_SIGN_STYLE "Automatic")
			else()
				set_target_properties(${TARGET_NAME} PROPERTIES XCODE_ATTRIBUTE_DEVELOPMENT_TEAM "${CU_TEAM_IDENTIFIER}")
			endif()
			# For xcode code signing to go deeply so all our dylibs are signed as well (will fail with xcode >= 11 otherwise)
			# We also need to force the signing identity here, as xcode sometimes choose the wrong one when only given the DEVELOPMENT_TEAM value
			set_target_properties(${TARGET_NAME} PROPERTIES XCODE_ATTRIBUTE_OTHER_CODE_SIGN_FLAGS "--timestamp --deep --strict --force --options=runtime -s \"${CU_BINARY_SIGNING_IDENTITY}\"")
			# Enable Hardened Runtime (required to notarize applications)
			set_target_properties(${TARGET_NAME} PROPERTIES XCODE_ATTRIBUTE_ENABLE_HARDENED_RUNTIME YES)
		else()
			# Silence CU_TEAM_IDENTIFIER unused variable warning
			if(CU_TEAM_IDENTIFIER)
			endif()
		endif()
	endif()
endfunction()

###############################################################################
# Setup BITCODE for iOS.
function(cu_setup_bitcode TARGET_NAME)
	if(APPLE)
		if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
			# Always force bitcode generation (not using the marker). Disable BITCODE if this is problematic
			if("${CMAKE_GENERATOR}" STREQUAL "Xcode")
				set_target_properties(${TARGET_NAME} PROPERTIES XCODE_ATTRIBUTE_ENABLE_BITCODE YES)
				set_target_properties(${TARGET_NAME} PROPERTIES XCODE_ATTRIBUTE_BITCODE_GENERATION_MODE bitcode)
			else()
				target_compile_options(${TARGET_NAME} PRIVATE -fembed-bitcode)
			endif()
		endif()
	endif()
endfunction()

###############################################################################
# Setup xcode scheme
function(cu_setup_xcode_scheme TARGET_NAME)
	if(APPLE)
		if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
			# Enable scheme generation
			set_target_properties(${TARGET_NAME} PROPERTIES XCODE_GENERATE_SCHEME YES)
			# Disable "Allow debugging when using document Versions Browser" which prevents xcode from passing args to the target
			set_target_properties(${TARGET_NAME} PROPERTIES XCODE_SCHEME_DEBUG_DOCUMENT_VERSIONING NO)
		endif()
	endif()
endfunction()

###############################################################################
# Set Precompiled Headers on a target
function(cu_set_precompiled_headers TARGET_NAME HEADER_NAME)
	# Currently, only activating for MSVC
	# gcc is actually 2x slower when activating precompiled headers
	# xcode doesn't need it, and it actually fails when compiling objective-c++ files
	if(CMAKE_HOST_WIN32 AND MSVC AND NOT "${CMAKE_GENERATOR}" STREQUAL "Fastbuild")
		target_precompile_headers(${TARGET_NAME} PRIVATE ${HEADER_NAME})
		target_sources(${TARGET_NAME} PRIVATE ${HEADER_NAME})
	endif()
endfunction()

###############################################################################
# Setup ASAN options for the target
function(cu_setup_asan_options TARGET_NAME)
	get_target_property(targetType ${TARGET_NAME} TYPE)
	if(MSVC)
		target_compile_options(${TARGET_NAME} PRIVATE $<$<CONFIG:Debug>:-fsanitize=address>)
		if(NOT ${targetType} STREQUAL "STATIC_LIBRARY")
			target_link_options(${TARGET_NAME} PRIVATE $<$<CONFIG:Debug>:/INCREMENTAL:NO>)
		endif()

		# We have to change global flags as there is no cl.exe flag to cancel /RTC
		string(REPLACE "/RTC1" "" CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG}")
		string(REPLACE "/RTC1" "" CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG}")
		set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG}" CACHE STRING "Force C flags for ASAN" FORCE)
		set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG}" CACHE STRING "Force C++ flags for ASAN" FORCE)

	elseif(APPLE AND CMAKE_CXX_COMPILER_ID MATCHES "Clang")
		target_compile_options(${TARGET_NAME} PRIVATE $<$<CONFIG:Debug>:-fsanitize=address>)
		if(NOT ${targetType} STREQUAL "STATIC_LIBRARY")
			target_link_options(${TARGET_NAME} PRIVATE $<$<CONFIG:Debug>:-fsanitize=address>)
		endif()
	endif()
endfunction()

###############################################################################
# Setup minimum version for Apple platforms
# Optional parameters:
#  - "MACOS <Min version>" => Set the minimum version for macOS platform
#  - "IOS <Min version>" => Set the minimum version for iOS platform
function(cu_setup_apple_minimum_versions)
	# Parse arguments
	cmake_parse_arguments(CUSAMV "" "MACOS;IOS" "" ${ARGN})

	# Get the correct variable to check
	if(CMAKE_SYSTEM_NAME AND CMAKE_SYSTEM_NAME STREQUAL "iOS")
		set(PARAM_TO_READ "CUSAMV_IOS")
	elseif(CMAKE_SYSTEM_NAME AND CMAKE_SYSTEM_NAME STREQUAL "Darwin")
		set(PARAM_TO_READ "CUSAMV_MACOS")
	endif()

	if(${PARAM_TO_READ})
		# We only want to override the minimum version if it is not already set (by this very function) or if it is set to a lower version
		# This is to override the default minimum version set by the first project() call that automatically sets CMAKE_OSX_DEPLOYMENT_TARGET if not defined

		# We use a global property to store the minimum version set by this function
		get_property(minimumVersion GLOBAL PROPERTY CU_APPLE_MINIMUM_VERSION)
		if(NOT DEFINED minimumVersion OR minimumVersion VERSION_LESS ${${PARAM_TO_READ}})
			set(CMAKE_OSX_DEPLOYMENT_TARGET ${${PARAM_TO_READ}} CACHE INTERNAL "Force minimum target version" FORCE)
			set_property(GLOBAL PROPERTY CU_APPLE_MINIMUM_VERSION ${${PARAM_TO_READ}})
		endif()
	endif()
endfunction()

###############################################################################
# Set a file as a resource for a target.
# This will copy the file to the resources folder for non bundle targets and to the Resources folder for bundles
# Optional parameters:
#  - "INSTALL" => Will also install the file (for non-bundle target as the file will already be inside the bundle otherwise)
function(cu_set_resource_file TARGET_NAME SOURCE_FILE_PATH DESTINATION_NAME)
	# Parse arguments
	cmake_parse_arguments(CUSRF "INSTALL" "" "" ${ARGN})

	cu_private_get_target_resource_path_string(${TARGET_NAME} resourcePath)
	add_custom_command(
		TARGET ${TARGET_NAME}
		POST_BUILD
		COMMAND ${CMAKE_COMMAND} -E copy_if_different "${SOURCE_FILE_PATH}" "${resourcePath}/${DESTINATION_NAME}"
		VERBATIM
	)

	cu_is_macos_bundle(${TARGET_NAME} isBundle)
	if(NOT ${isBundle})
		if(CUSRF_INSTALL)
			install(FILES ${SOURCE_FILE_PATH} DESTINATION resources RENAME ${DESTINATION_NAME})
		endif()
	endif()
endfunction()

###############################################################################
# Set an executable target as a resource for a target.
# This will copy the executable and all its dependencies to the resources folder for non bundle targets and to the Resources folder for bundles.
# Mandatory parameters:
# - "TARGET_NAME" => The target name to which the resource will be added during its POST_BUILD phase
# - "BINARY_TARGET_NAME" => The target name of the executable to copy, this can be an IMPORTED target
# - "DESTINATION_FOLDER" => The folder where the executable (and dependencies) will be copied, relative to the resources folder
# Optional parameters:
#  - "INSTALL" => Will also install the file(s) (for non-bundle target as the file will already be inside the bundle otherwise)
#  - "SIGN"-> Code sign all binaries
function(cu_set_executable_target_resource TARGET_NAME BINARY_TARGET_NAME DESTINATION_FOLDER)
	# Check BINARY_TARGET_NAME is a executable target
	get_target_property(targetType ${BINARY_TARGET_NAME} TYPE)
	if(NOT ${targetType} STREQUAL "EXECUTABLE")
		message(FATAL_ERROR "Target ${BINARY_TARGET_NAME} is not an executable")
	endif()

	# Parse arguments
	cmake_parse_arguments(CUSRBT "INSTALL;SIGN" "" "" ${ARGN})

	# Compute some paths
	cu_private_get_target_resource_folder_name(${TARGET_NAME} resourceFolder)
	cu_private_get_target_resource_path_string(${TARGET_NAME} resourcePath)

	# Set executable file as a resource (do not forward the INSTALL parameter, it will be handled by cu_setup_deploy_runtime)
	cu_set_resource_file(${TARGET_NAME} "$<TARGET_FILE:${BINARY_TARGET_NAME}>" "${DESTINATION_FOLDER}/$<TARGET_FILE_NAME:${BINARY_TARGET_NAME}>")

	# Sign the executable (once copied) if requested
	if(CUSRBT_SIGN)
		# Xcode already forces automatic signing, so only sign for the other cases
		if(NOT "${CMAKE_GENERATOR}" STREQUAL "Xcode")
			cu_private_sign_postbuild_binary(${TARGET_NAME} "${resourcePath}/${DESTINATION_FOLDER}/$<TARGET_FILE_NAME:${BINARY_TARGET_NAME}>" "${BINARY_TARGET_NAME}")
		endif()
	endif()

	set(additionalParameters "")
	if(CUSRBT_INSTALL)
		list(APPEND additionalParameters "INSTALL")
	endif()
	if(CUSRBT_SIGN)
		list(APPEND additionalParameters "SIGN")
	endif()

	# Deploy dependencies
	cu_setup_deploy_runtime(${BINARY_TARGET_NAME} ${additionalParameters} DEPLOY_DESTINATION "${resourcePath}/${DESTINATION_FOLDER}" RUNTIME_DIR "${resourceFolder}/${DESTINATION_FOLDER}" ATTACH_TO_TARGET_POSTBUILD ${TARGET_NAME})
endfunction()

###############################################################################
# Set a folder as a resource for a target.
# This will copy the given folder to the resources folder for non bundle targets and to the Resources folder for bundles
# Optional parameters:
#  - "INSTALL" => Will also install the folder (for non-bundle target as it will already be inside the bundle otherwise)
function(cu_set_resource_directory TARGET_NAME SOURCE_DIRECTORY_PATH DESTINATION_PATH)
	# Parse arguments
	cmake_parse_arguments(CUSRD "INSTALL" "" "" ${ARGN})

	get_filename_component(LAST_FOLDER_NAME "${SOURCE_DIRECTORY_PATH}" NAME)
	cu_is_macos_bundle(${TARGET_NAME} isBundle)
	if(${isBundle})
		add_custom_command(
			TARGET ${TARGET_NAME}
			POST_BUILD
			COMMAND ${CMAKE_COMMAND} -E copy_directory "${SOURCE_DIRECTORY_PATH}" "$<TARGET_BUNDLE_CONTENT_DIR:${TARGET_NAME}>/Resources/${DESTINATION_PATH}/${LAST_FOLDER_NAME}"
			VERBATIM
		)
	else()
		add_custom_command(
			TARGET ${TARGET_NAME}
			POST_BUILD
			COMMAND ${CMAKE_COMMAND} -E copy_directory "${SOURCE_DIRECTORY_PATH}" "$<TARGET_FILE_DIR:${TARGET_NAME}>/Resources/${DESTINATION_PATH}/${LAST_FOLDER_NAME}"
			VERBATIM
		)
		if(CUSRD_INSTALL)
			install(DIRECTORY ${SOURCE_DIRECTORY_PATH} DESTINATION resources/${DESTINATION_PATH})
		endif()
	endif()
endfunction()

###############################################################################
# Setup common options for a library target
# Optional parameters:
#  - "NO_ALIAS_TARGET" => Will not create an alias target for the target
#  - "NO_DEBUG_SYMBOLS" => Will not generate debug symbols for the target
#  - "ALIAS_NAME <name>" => Force the alias name for the target (ie. ${PROJECT_NAME}::name) (defaults to either 'static' or 'shared')
#  - "UNICODE" => Will force unicode character set for the target (Windows only) instead of multi-byte character set (default)
#  - "NO_COPY_DEBUG_SYMBOLS" => Won't copy debug symbols from the build folder when set, but it will still generate them.
#  - "NO_OUTPUT_COLORIZATION" => Will disable colorization of the output
function(cu_setup_library_options TARGET_NAME)
	# Parse arguments
	cmake_parse_arguments(CUSLO "NO_MAX_WARNINGS;NO_ALIAS_TARGET;NO_DEBUG_SYMBOLS;UNICODE;NO_COPY_DEBUG_SYMBOLS;NO_OUTPUT_COLORIZATION" "ALIAS_NAME" "" ${ARGN})

	# Check legacy parameters
	if(CUSLO_NO_MAX_WARNINGS)
		message(WARNING "NO_MAX_WARNINGS is deprecated, use the cu_set_warning_flags function instead.")
	endif()

	# Get target type for specific options
	get_target_property(targetType ${TARGET_NAME} TYPE)

	# Did we get any optional args?
	list(LENGTH CUSLO_UNPARSED_ARGUMENTS COUNT_EXTRA_ARGS)
	if(${COUNT_EXTRA_ARGS} GREATER 0)
		message(FATAL_ERROR "No extra arg expected when calling cu_setup_library_options.\nPotentially check for define change from ${TARGET_NAME}_cxx_STATICS to ${TARGET_NAME}_STATICS in exports.hpp\n")
	endif()

	if(MSVC)
		# Set WIN32 version since we want to target WinVista minimum
		target_compile_definitions(${TARGET_NAME} PRIVATE _WIN32_WINNT=0x0600)

		if(NOT CUSLO_UNICODE)
			# Force multi-byte character strings
			if(COMMAND qt6_disable_unicode_defines)
				qt6_disable_unicode_defines(${TARGET_NAME})
			endif()
		else()
			target_compile_definitions(${TARGET_NAME} PRIVATE UNICODE _UNICODE)
		endif()
	endif()

	if(NOT APPLE AND NOT WIN32)
		# Build using fPIC
		target_compile_options(${TARGET_NAME} PRIVATE -fPIC)
	endif()

	# Static library special options
	if(${targetType} STREQUAL "STATIC_LIBRARY")
		target_link_libraries(${TARGET_NAME} PUBLIC ${LINK_LIBRARIES} ${ADD_LINK_LIBRARIES})
		# Set a preprocessor define to properly setup symbols visibility/linkage (a shared library will automatically create a ${TARGET_NAME}_EXPORTS define)
		target_compile_options(${TARGET_NAME} PUBLIC "-D${TARGET_NAME}_STATICS")
		# Defaults to hidden symbols for Gcc/Clang
		if(NOT MSVC)
			if(CMAKE_COMPILER_IS_GNUCC OR CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
				target_compile_options(${TARGET_NAME} PRIVATE -fvisibility=hidden)
			endif()
		endif()
		# Add target alias
		if(NOT CUSLO_NO_ALIAS_TARGET)
			set(ALIAS_NAME "static")
			if(DEFINED CUSLO_ALIAS_NAME)
				set(ALIAS_NAME "${CUSLO_ALIAS_NAME}")
			endif()
			add_library(${PROJECT_NAME}::${ALIAS_NAME} ALIAS ${TARGET_NAME})
			message(STATUS "Added alias for ${TARGET_NAME} (${PROJECT_NAME}::${ALIAS_NAME})")
		endif()

	# Shared library special options
	elseif(${targetType} STREQUAL "SHARED_LIBRARY")
		target_link_libraries(${TARGET_NAME} PRIVATE ${LINK_LIBRARIES} ${ADD_LINK_LIBRARIES})
		# Defaults to hidden symbols for Gcc/Clang
		if(NOT MSVC)
			if(CMAKE_COMPILER_IS_GNUCC OR CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
				target_compile_options(${TARGET_NAME} PRIVATE -fvisibility=hidden)
			endif()
		endif()
		if(WIN32)
			# Touch the import library so even if we don't change exported symbols, the lib is 'changed' and anything depending on the dll will be relinked
			add_custom_command(
				TARGET ${TARGET_NAME}
				POST_BUILD
				COMMAND ${CMAKE_COMMAND} -E touch_nocreate "$<TARGET_LINKER_FILE:${TARGET_NAME}>"
				COMMAND ${CMAKE_COMMAND} -E echo "Touching $<TARGET_LINKER_FILE:${TARGET_NAME}> import library"
				VERBATIM
			)
		endif()
		# Generate so-version on Linux and macOS
		if(NOT WIN32)
			set_target_properties(${TARGET_NAME} PROPERTIES VERSION ${CU_PROJECT_CMAKEVERSION_STRING} SOVERSION ${CU_PROJECT_VERSION_MAJOR})
		endif()
		# Add target alias
		if(NOT CUSLO_NO_ALIAS_TARGET)
			set(ALIAS_NAME "shared")
			if(DEFINED CUSLO_ALIAS_NAME)
				set(ALIAS_NAME "${CUSLO_ALIAS_NAME}")
			endif()
			add_library(${PROJECT_NAME}::${ALIAS_NAME} ALIAS ${TARGET_NAME})
			message(STATUS "Added alias for ${TARGET_NAME} (${PROJECT_NAME}::${ALIAS_NAME})")
		endif()

	# Module library special options
	elseif(${targetType} STREQUAL "MODULE_LIBRARY")
		target_link_libraries(${TARGET_NAME} PRIVATE ${LINK_LIBRARIES} ${ADD_LINK_LIBRARIES})
		# Defaults to hidden symbols for Gcc/Clang
		if(NOT MSVC)
			if(CMAKE_COMPILER_IS_GNUCC OR CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
				target_compile_options(${TARGET_NAME} PRIVATE -fvisibility=hidden)
			endif()
		endif()

	# Unsupported target type
	else()
		message(FATAL_ERROR "Unsupported target type for cu_setup_library_options: ${targetType}")
	endif()

	# Setup ASAN options
	if(CU_ENABLE_ASAN)
		cu_setup_asan_options(${TARGET_NAME})
	endif()

	# Colorize the output
	if (NOT CUSLO_NO_OUTPUT_COLORIZATION)
		cu_set_output_colorization(${TARGET_NAME})
	endif()

	# Set the warning flags for the target
	cu_private_set_default_warning_flags(${TARGET_NAME})
	
	# Set parallel build
	cu_set_parallel_build(${TARGET_NAME})

	# Set the "DEBUG" define in debug compilation mode
	cu_set_debug_define(${TARGET_NAME})
	
	# Prevent visual studio deprecated warnings about CRT and Sockets
	cu_remove_vs_deprecated_warnings(${TARGET_NAME})
	
	# Add a postfix in debug mode
	set_target_properties(${TARGET_NAME} PROPERTIES DEBUG_POSTFIX "-d")

	if(${targetType} STREQUAL "SHARED_LIBRARY")
		# Set rpath for macOS (force dependent shared libraries to load from the same directory as this library)
		if(APPLE)
			set_target_properties(${TARGET_NAME} PROPERTIES INSTALL_RPATH "@loader_path")
			# Directly use install rpath for command line apps too
			set_target_properties(${TARGET_NAME} PROPERTIES BUILD_WITH_INSTALL_RPATH TRUE)

		# Set rpath for linux (force dependent shared libraries to load from the same directory as this library)
		elseif(NOT WIN32)
			set_target_properties(${TARGET_NAME} PROPERTIES INSTALL_RPATH "$ORIGIN")
			# Directly use install rpath
			set_target_properties(${TARGET_NAME} PROPERTIES BUILD_WITH_INSTALL_RPATH TRUE)
		endif()
	endif()

	# Set xcode automatic codesigning
	cu_setup_xcode_codesigning(${TARGET_NAME})

	# Set BITCODE => Actually don't set it up, it's deprecated
	# cu_setup_bitcode(${TARGET_NAME})

	# Set TARGET_SYSTEM_xxx compile definition
	cu_set_target_system_definition(${TARGET_NAME})

	# Use cmake folders
	set_target_properties(${TARGET_NAME} PROPERTIES FOLDER "Libraries")

	# Additional include directories
	target_include_directories(${TARGET_NAME} PUBLIC $<INSTALL_INTERFACE:include> $<BUILD_INTERFACE:${CU_ROOT_DIR}/include> PRIVATE ${CMAKE_CURRENT_BINARY_DIR})
	
	if (NOT CUSLO_NO_DEBUG_SYMBOLS)
		# Setup debug symbols
		set(COPY_SYMBOLS_ARG "")
		if (${CUSLO_NO_COPY_DEBUG_SYMBOLS})
			set(COPY_SYMBOLS_ARG "NO_COPY_DEBUG_SYMBOLS")
		endif()
		cu_setup_symbols(${TARGET_NAME} ${COPY_SYMBOLS_ARG})
	endif()

endfunction()

###############################################################################
# Setup install rules for header files
# Optional parameters:
#  - "CONFIGURATIONS <List of install configuration>" -> Select the configurations for which the install rules will be generated (Default: Release)
function(cu_setup_headers_install_rules FILES_LIST INCLUDE_ABSOLUTE_BASE_FOLDER)
	# Parse arguments
	cmake_parse_arguments(CUSHIR "" "" "CONFIGURATIONS" ${ARGN})

	# Create default configurations list
	set(configurationsList "Release")

	# If configurations are provided, use them instead
	if(CUSHIR_CONFIGURATIONS)
		set(configurationsList ${CUSHIR_CONFIGURATIONS})
	endif()

	# And remove duplicates
	list(REMOVE_DUPLICATES configurationsList)

	foreach(f ${FILES_LIST})
		get_filename_component(dir ${f} DIRECTORY)
		file(RELATIVE_PATH dir ${INCLUDE_ABSOLUTE_BASE_FOLDER} ${dir})
		install(FILES ${f} CONFIGURATIONS ${configurationsList} DESTINATION include/${dir})
	endforeach()
endfunction()

###############################################################################
# Setup install rules for a library target, as well a signing if specified
# Optional parameters:
#  - "INSTALL" -> Generate CMake install rules
#  - "SIGN" -> Code sign (ignored for everything but SHARED_LIBRARY)
#  - "RUNTIME_DIR <install directory>" -> directory where to install RUNTIME file type (defaults to "bin")
#  - "NO_EXPORT_TARGET" -> Do not export cmake target
function(cu_setup_deploy_library TARGET_NAME)
	# Get target type for specific options
	get_target_property(targetType ${TARGET_NAME} TYPE)

	# Parse arguments
	cmake_parse_arguments(SDL "INSTALL;SIGN;NO_EXPORT_TARGET" "RUNTIME_DIR" "" ${ARGN})

	# Install directories
	set(RUNTIME_INSTALL_DIR "bin")
	if(SDL_RUNTIME_DIR)
		set(RUNTIME_INSTALL_DIR "${SDL_RUNTIME_DIR}")
	endif()

	if(SDL_INSTALL)
		# Static library install rules
		if(${targetType} STREQUAL "STATIC_LIBRARY")
			install(TARGETS ${TARGET_NAME} EXPORT ${TARGET_NAME} ARCHIVE DESTINATION lib)
			if(NOT SDL_NO_EXPORT_TARGET)
				install(EXPORT ${TARGET_NAME} DESTINATION cmake)
			endif()

		# Shared library install rules
		elseif(${targetType} STREQUAL "SHARED_LIBRARY")
			# Check for SIGN option
			if(SDL_SIGN)
				cu_private_setup_signing_command(${TARGET_NAME})
			endif()

			install(TARGETS ${TARGET_NAME} EXPORT ${TARGET_NAME} RUNTIME DESTINATION ${RUNTIME_INSTALL_DIR} LIBRARY DESTINATION lib ARCHIVE DESTINATION lib FRAMEWORK DESTINATION lib)
			if(NOT SDL_NO_EXPORT_TARGET)
				install(EXPORT ${TARGET_NAME} DESTINATION cmake)
			endif()

		# Module install rules
		elseif(${targetType} STREQUAL "MODULE_LIBRARY")
			# Check for SIGN option
			if(SDL_SIGN)
				cu_private_setup_signing_command(${TARGET_NAME})
			endif()

			install(TARGETS ${TARGET_NAME} EXPORT ${TARGET_NAME} LIBRARY DESTINATION ${RUNTIME_INSTALL_DIR}) # Module libraries are always shared

		# Interface library install rules
		elseif(${targetType} STREQUAL "INTERFACE_LIBRARY")
			install(TARGETS ${TARGET_NAME} EXPORT ${TARGET_NAME})
			if(NOT SDL_NO_EXPORT_TARGET)
				install(EXPORT ${TARGET_NAME} DESTINATION cmake)
			endif()

		# Unsupported target type
		else()
			message(FATAL_ERROR "Unsupported target type for cu_setup_deploy_library macro: ${targetType}")
		endif()
	endif()
endfunction()

###############################################################################
# Setup macOS bundle information
# Applies on a target, must be called after target has been defined with
# 'add_executable'.
macro(cu_setup_bundle_information TARGET_NAME)
	if(APPLE)
		cu_is_macos_bundle(${TARGET_NAME} isBundle)
		if(${isBundle})
			if(NOT CU_TARGET_BUNDLE_IDENTIFIER)
				# We want to use the Marketing Version as part of the bundle identifier name because we want this to be a different binary than another marketing version.
				# This is because of how macOS indexes files in spotlight, which would prevent installation of the same binary with different marketing versions (same name).
				set(CU_PROJECT_BUNDLEIDENTIFIER "${CU_REVERSE_DOMAIN_NAME}.${TARGET_NAME}${CU_PROJECT_MARKETING_VERSION}")
			else()
				set(CU_PROJECT_BUNDLEIDENTIFIER "${CU_TARGET_BUNDLE_IDENTIFIER}")
				message(STATUS "Overriding default bundle identifier for ${TARGET_NAME} with ${CU_PROJECT_BUNDLEIDENTIFIER}")
			endif()

			# Validate bundle identifier (can contains only alphanumeric characters (A-Z,a-z,0-9), hyphen (-), and period (.))
			if(NOT "${CU_PROJECT_BUNDLEIDENTIFIER}" MATCHES "^[A-Za-z0-9.-]+$")
				message(FATAL_ERROR "Invalid bundle identifier (can contains only alphanumeric characters (A-Z,a-z,0-9), hyphen (-), and period (.)): ${CU_PROJECT_BUNDLEIDENTIFIER}")
			endif()

			set_target_properties(${TARGET_NAME} PROPERTIES
					XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "${CU_PROJECT_BUNDLEIDENTIFIER}"
					MACOSX_BUNDLE_INFO_STRING "${PROJECT_NAME} version ${CU_PROJECT_FRIENDLY_VERSION} ${CU_PROJECT_READABLE_COPYRIGHT}"
					MACOSX_BUNDLE_ICON_FILE "AppIcon"
					MACOSX_BUNDLE_GUI_IDENTIFIER "${CU_PROJECT_BUNDLEIDENTIFIER}"
					MACOSX_BUNDLE_BUNDLE_NAME "${PROJECT_NAME}"
					MACOSX_BUNDLE_BUNDLE_VERSION "${CU_BUILD_NUMBER}"
					MACOSX_BUNDLE_COPYRIGHT "${CU_PROJECT_READABLE_COPYRIGHT}")
		endif()
		set(CU_PROJECT_BUNDLEIDENTIFIER "${CU_PROJECT_BUNDLEIDENTIFIER}" PARENT_SCOPE)
	endif()
endmacro()

###############################################################################
# Add target to vscode launch configuration
function(cu_add_vscode_launch_configuration TARGET_NAME)
	cu_is_macos_bundle(${TARGET_NAME} isBundle)
	cu_is_macos_framework(${TARGET_NAME} isFramework)
	set(USE_BUNDLE_DIR FALSE)
	if(${isBundle} OR ${isFramework})
		set(USE_BUNDLE_DIR TRUE)
	endif()
	# Add this target to the list of targets to be launched
	get_property(targetsList GLOBAL PROPERTY CU_VSCODE_LAUNCH_TARGETS)
	list(APPEND targetsList "${TARGET_NAME}#${CMAKE_CURRENT_BINARY_DIR}#${USE_BUNDLE_DIR}")
	set_property(GLOBAL PROPERTY CU_VSCODE_LAUNCH_TARGETS ${targetsList})
endfunction()

###############################################################################
# Setup common options for an executable target.
# Optional parameters:
#  - "NO_DEBUG_SYMBOLS" => Will not generate debug symbols for the target
#  - "UNICODE" => Will force unicode character set for the target (Windows only) instead of multi-byte character set (default)
#  - "NO_COPY_DEBUG_SYMBOLS" => Won't copy debug symbols from the build folder when set, but it will still generate them.
#  - "NO_OUTPUT_COLORIZATION" => Will disable colorization of the output
function(cu_setup_executable_options TARGET_NAME)
	# Parse arguments
	cmake_parse_arguments(CUSEO "NO_MAX_WARNINGS;NO_DEBUG_SYMBOLS;UNICODE;NO_COPY_DEBUG_SYMBOLS;NO_OUTPUT_COLORIZATION" "" "" ${ARGN})

	# Check legacy parameters
	if(CUSEO_NO_MAX_WARNINGS)
		message(WARNING "NO_MAX_WARNINGS is deprecated, use the cu_set_warning_flags function instead.")
	endif()

	if(MSVC)
		# Set WIN32 version since we want to target WinVista minimum
		target_compile_definitions(${TARGET_NAME} PRIVATE _WIN32_WINNT=0x0600)

		if(NOT CUSEO_UNICODE)
			# Force multi-byte character strings
			if(COMMAND qt6_disable_unicode_defines)
				qt6_disable_unicode_defines(${TARGET_NAME})
			endif()
		else()
			target_compile_definitions(${TARGET_NAME} PRIVATE UNICODE _UNICODE)
		endif()
	endif()

	# Defaults to hidden symbols for Gcc/Clang
	if(NOT MSVC)
		if(CMAKE_COMPILER_IS_GNUCC OR CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
			target_compile_options(${TARGET_NAME} PRIVATE -fvisibility=hidden)
		endif()
	endif()

	# Add link libraries
	target_link_libraries(${TARGET_NAME} PRIVATE ${LINK_LIBRARIES})

	# Setup ASAN options
	if(CU_ENABLE_ASAN)
		cu_setup_asan_options(${TARGET_NAME})
	endif()

	# Colorize the output
	if (NOT CUSEO_NO_OUTPUT_COLORIZATION)
		cu_set_output_colorization(${TARGET_NAME})
	endif()

	# Set the warning flags for the target
	cu_private_set_default_warning_flags(${TARGET_NAME})
	
	# Set parallel build
	cu_set_parallel_build(${TARGET_NAME})

	# Set the "DEBUG" define in debug compilation mode
	cu_set_debug_define(${TARGET_NAME})
	
	# Prevent visual studio deprecated warnings about CRT and Sockets
	cu_remove_vs_deprecated_warnings(${TARGET_NAME})
	
	# Add a postfix in debug mode (but only if not a macOS bundle/framework as it is not supported and will cause error in other parts of the scripts)
	cu_is_macos_bundle(${TARGET_NAME} isBundle)
	cu_is_macos_framework(${TARGET_NAME} isFramework)
	if(NOT ${isBundle} AND NOT ${isFramework})
		set_target_properties(${TARGET_NAME} PROPERTIES DEBUG_POSTFIX "-d")
	endif()

	# Set target properties
	cu_setup_bundle_information(${TARGET_NAME})

	if (NOT CUSEO_NO_DEBUG_SYMBOLS)
		# Setup debug symbols
		set(COPY_SYMBOLS_ARG "")
		if (${CUSEO_NO_COPY_DEBUG_SYMBOLS})
			set(COPY_SYMBOLS_ARG "NO_COPY_DEBUG_SYMBOLS")
		endif()
		cu_setup_symbols(${TARGET_NAME} ${COPY_SYMBOLS_ARG})
	endif()

	# Add vscode launch configuration
	cu_add_vscode_launch_configuration(${TARGET_NAME})

	# Set rpath for macOS
	if(APPLE)
		if(${isBundle})
			set_target_properties(${TARGET_NAME} PROPERTIES INSTALL_RPATH "@executable_path/../Frameworks")
			# Directly use install rpath for app bundles, since we copy dylibs into the bundle during post build
			set_target_properties(${TARGET_NAME} PROPERTIES BUILD_WITH_INSTALL_RPATH TRUE)
		else()
			set_target_properties(${TARGET_NAME} PROPERTIES INSTALL_RPATH "@executable_path/../lib")
			# Directly use install rpath for command line apps too
			set_target_properties(${TARGET_NAME} PROPERTIES BUILD_WITH_INSTALL_RPATH TRUE)
		endif()

	# Set rpath for linux
	elseif(NOT WIN32)
		set_target_properties(${TARGET_NAME} PROPERTIES INSTALL_RPATH "$ORIGIN/../lib")
		# Directly use install rpath
		set_target_properties(${TARGET_NAME} PROPERTIES BUILD_WITH_INSTALL_RPATH TRUE)
	endif()
	
	# Set xcode automatic codesigning
	cu_setup_xcode_codesigning(${TARGET_NAME})

	# Set BITCODE => Actually don't set it up, it's deprecated
	# cu_setup_bitcode(${TARGET_NAME})

	# Set xcode scheme
	cu_setup_xcode_scheme(${TARGET_NAME})

	# Set TARGET_SYSTEM_xxx compile definition
	cu_set_target_system_definition(${TARGET_NAME})

	target_include_directories(${TARGET_NAME} PRIVATE "${CMAKE_CURRENT_BINARY_DIR}" "${CU_ROOT_DIR}/include")

endfunction()

###############################################################################
# Setup runtime deployment rules for an executable target, for easy debug and install (if specified)
# Optional parameters:
#  - "INSTALL" -> Generate CMake install rules
#  - "SIGN"-> Code sign all binaries
#  - "NO_DEPENDENCIES" -> Do not copy/install/sign dependencies
#  - "BUNDLE_DIR <install directory>" -> directory where to install BUNDLE file type (defaults to ".")
#  - "RUNTIME_DIR <install directory>" -> directory where to install RUNTIME file type (defaults to "bin")
#  - "QT_MAJOR_VERSION <version>" -> Qt major version (defaults to 5)
#  - "QML_DIR <qml directory>" -> directory containing the qml source files of the target (defaults to ".")
#  - "EXPORT_TARGET" -> Export cmake target
#  - "ATTACH_TO_TARGET_POSTBUILD <target>" -> Attach deploy actions to the specified target instead of the target itself (required for IMPORTED targets)
function(cu_setup_deploy_runtime TARGET_NAME)
	# Get target type for specific options
	get_target_property(targetType ${TARGET_NAME} TYPE)

	# Only for executables
	if(NOT ${targetType} STREQUAL "EXECUTABLE")
		message(FATAL_ERROR "Unsupported target type for cu_setup_deploy_runtime macro: ${targetType}")
	endif()

	# Parse optional arguments
	cmake_parse_arguments(SDR "INSTALL;SIGN;NO_DEPENDENCIES;EXPORT_TARGET" "BUNDLE_DIR;RUNTIME_DIR;QT_MAJOR_VERSION;ATTACH_TO_TARGET_POSTBUILD;QML_DIR" "" ${ARGN})

	# Get signing options
	cu_private_get_sign_command_options(SIGN_COMMAND_OPTIONS)

	# Get additional folders for runtime deployment
	get_property(depSearchDirsDebug GLOBAL PROPERTY CU_DEPLOY_RUNTIME_SEARCH_DIRS_DEBUG)
	get_property(depSearchDirsOptimized GLOBAL PROPERTY CU_DEPLOY_RUNTIME_SEARCH_DIRS_OPTIMIZED)

	# Get Qt major version
	set(QT_MAJOR_VERSION 5)
	if(SDR_QT_MAJOR_VERSION)
		set(QT_MAJOR_VERSION ${SDR_QT_MAJOR_VERSION})
	endif()

	# Install directories
	set(BUNDLE_INSTALL_DIR ".")
	if(SDR_BUNDLE_DIR)
		set(BUNDLE_INSTALL_DIR "${SDR_BUNDLE_DIR}")
	endif()
	set(RUNTIME_INSTALL_DIR "bin")
	if(SDR_RUNTIME_DIR)
		set(RUNTIME_INSTALL_DIR "${SDR_RUNTIME_DIR}")
	endif()

	set(QML_DIR_ARG "")
	if(SDR_QML_DIR)
		set(QML_DIR_ARG QML_DIR ${SDR_QML_DIR})
	endif()

	# Deploy runtime dependencies
	if(NOT ${SDR_NO_DEPENDENCIES})
		cu_deploy_runtime_target(${ARGV} ${SIGN_COMMAND_OPTIONS} INSTALL_DESTINATION ${RUNTIME_INSTALL_DIR} DEP_SEARCH_DIRS_DEBUG ${depSearchDirsDebug} DEP_SEARCH_DIRS_OPTIMIZED ${depSearchDirsOptimized} QT_MAJOR_VERSION ${QT_MAJOR_VERSION} ${QML_DIR_ARG})
	endif()

	get_target_property(targetImported ${TARGET_NAME} IMPORTED)

	# If target is imported, make sure ATTACH_TO_TARGET_POSTBUILD is defined
	if(${targetImported} AND NOT SDR_ATTACH_TO_TARGET_POSTBUILD)
		message(FATAL_ERROR "ATTACH_TO_TARGET_POSTBUILD is required for imported targets")
	endif()

	# Sign the binary during post build if requested (but not for imported targets as they are already built)
	if(SDR_SIGN AND NOT ${targetImported})
		cu_private_setup_signing_command(${TARGET_NAME})
	endif()

	if(SDR_INSTALL)
		set(EXPORT_TARGET_COMMANDS "")
		set(INSTALL_TARGET_KEYWORD "TARGETS")
		if(${targetImported})
			# Check for cmake minimum version
			cmake_minimum_required(VERSION 3.21) # IMPORTED_RUNTIME_ARTIFACTS added in cmake 3.21
			set(INSTALL_TARGET_KEYWORD "IMPORTED_RUNTIME_ARTIFACTS")
		else()
			if(${SDR_EXPORT_TARGET})
				list(APPEND EXPORT_TARGET_COMMANDS EXPORT ${TARGET_NAME})
			endif()
		endif()
		if(${targetImported})
			cu_is_macos_bundle(${SDR_ATTACH_TO_TARGET_POSTBUILD} isAttachedToBundle)
			# We want to install and sign the imported target but only if the target we are attached to is not a bundle (otherwise we assume TARGET_NAME is being copied inside the bundle)
			if(SDR_SIGN AND NOT ${isAttachedToBundle})
				install(${INSTALL_TARGET_KEYWORD} ${TARGET_NAME} ${EXPORT_TARGET_COMMANDS} BUNDLE DESTINATION ${BUNDLE_INSTALL_DIR} RUNTIME DESTINATION ${RUNTIME_INSTALL_DIR})
				cu_private_sign_installed_binary("${RUNTIME_INSTALL_DIR}/$<TARGET_FILE_NAME:${TARGET_NAME}>")
			endif()
		else()
			# Install the target
			install(${INSTALL_TARGET_KEYWORD} ${TARGET_NAME} ${EXPORT_TARGET_COMMANDS} BUNDLE DESTINATION ${BUNDLE_INSTALL_DIR} RUNTIME DESTINATION ${RUNTIME_INSTALL_DIR})
			if(${SDR_EXPORT_TARGET})
				install(EXPORT ${TARGET_NAME} DESTINATION cmake)
			endif()
		endif()
	endif()
endfunction()

###############################################################################
# Internal macros and functions
macro(_cu_list_targets TARGET_NAME TARGET_LIST)
	get_target_property(libs ${TARGET_NAME} LINK_LIBRARIES)
	if(libs)
		foreach(lib ${libs})
			if(TARGET ${lib} AND NOT ${lib} IN_LIST ${TARGET_LIST})
				list(APPEND ${TARGET_LIST} ${lib})
				_cu_list_targets(${lib} ${TARGET_LIST})
			endif()
		endforeach()
	endif()
	get_target_property(libs ${TARGET_NAME} INTERFACE_LINK_LIBRARIES)
	if(libs)
		foreach(lib ${libs})
			if(TARGET ${lib} AND NOT ${lib} IN_LIST ${TARGET_LIST})
				list(APPEND ${TARGET_LIST} ${lib})
				_cu_list_targets(${lib} ${TARGET_LIST})
			endif()
		endforeach()
	endif()
endmacro()

macro(_cu_vscode_append_build_task BUILD_CONFIG TARGET_NAME IS_DEFAULT IS_LAST)
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t\t{\n")

	if("${TARGET_NAME}" STREQUAL "All")
		set(TARGET_COMMAND "")
	else()
		set(TARGET_COMMAND " --target ${TARGET_NAME}")
	endif()
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t\t\t\"label\": \"Build ${TARGET_NAME} [${BUILD_CONFIG}]\",\n")
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t\t\t\"type\": \"shell\",\n")
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t\t\t\"command\": \"cmake --build ${CMAKE_BINARY_DIR} --config ${BUILD_CONFIG}${TARGET_COMMAND}\",\n")
	if(WIN32)
		string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t\t\t\"problemMatcher\": [\"\$msCompile\"],\n")
	endif()
	if(${IS_DEFAULT})
		string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t\t\t\"group\": {\n")
		string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t\t\t\t\"kind\": \"build\",\n")
		string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t\t\t\t\"isDefault\": true,\n")
		string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t\t\t},\n")
	else()
		string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t\t\t\"group\": \"build\",\n")
	endif()
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t\t\t\"presentation\": {\n")
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t\t\t\t\"reveal\": \"always\",\n")
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t\t\t\t\"focus\": false,\n")
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t\t\t\t\"panel\": \"shared\",\n")
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t\t\t\t\"clear\": true\n")
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t\t\t}\n")

	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t\t}")
	if(NOT ${IS_LAST})
		string(APPEND VS_WORKSPACE_FILE_CONTENT ",")
	endif()
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\n")
endmacro()

function(_cu_vscode_get_include_paths INCLUDE_PATHS)
	get_property(targetsList GLOBAL PROPERTY CU_VSCODE_LAUNCH_TARGETS)

	# Get a list of all targets (including transitive)
	set(allTargetsList "")
	foreach(tarInfo ${targetsList})
		string(REPLACE "#" ";" tarInfo "${tarInfo}")
		list(GET tarInfo 0 tar)
		_cu_list_targets(${tar} allTargetsList)
	endforeach()
	# Get include paths from all targets
	set(INCLUDE_PATHS_LIST "")
	foreach(tar ${allTargetsList})
		# Get include paths from target properties
		get_target_property(includePaths ${tar} INCLUDE_DIRECTORIES)
		if(includePaths)
			foreach(includePath ${includePaths})
				# Escape quotes
				string(REPLACE "\"" "\\\"" includePath "${includePath}")
				list(APPEND INCLUDE_PATHS_LIST "${includePath}")
			endforeach()
		endif()
		get_target_property(interfaceIncludePaths ${tar} INTERFACE_INCLUDE_DIRECTORIES)
		if(interfaceIncludePaths)
			foreach(includePath ${interfaceIncludePaths})
				# Escape quotes
				string(REPLACE "\"" "\\\"" includePath "${includePath}")
				list(APPEND INCLUDE_PATHS_LIST "${includePath}")
			endforeach()
		endif()
	endforeach()

	# Remove duplicates
	list(REMOVE_DUPLICATES INCLUDE_PATHS_LIST)

	# Return the list
	set(${INCLUDE_PATHS} "${INCLUDE_PATHS_LIST}" PARENT_SCOPE)
endfunction()

function(_cu_vscode_get_compiler_defines COMPILER_DEFINES)
	get_property(targetsList GLOBAL PROPERTY CU_VSCODE_LAUNCH_TARGETS)

	# Get a list of all targets (including transitive)
	set(allTargetsList "")
	foreach(tarInfo ${targetsList})
		string(REPLACE "#" ";" tarInfo "${tarInfo}")
		list(GET tarInfo 0 tar)
		_cu_list_targets(${tar} allTargetsList)
	endforeach()
	# Get defines from all targets
	set(DEFINES_LIST "")
	foreach(tar ${allTargetsList})
		# Get defines from target properties
		get_target_property(defines ${tar} COMPILE_DEFINITIONS)
		if(defines)
			foreach(define ${defines})
				# Escape quotes
				string(REPLACE "\"" "\\\"" define "${define}")
				list(APPEND DEFINES_LIST "${define}")
			endforeach()
		endif()
		get_target_property(interfaceDefines ${tar} INTERFACE_COMPILE_DEFINITIONS)
		if(interfaceDefines)
			foreach(define ${interfaceDefines})
				# Escape quotes
				string(REPLACE "\"" "\\\"" define "${define}")
				list(APPEND DEFINES_LIST "${define}")
			endforeach()
		endif()
		# TODO: All defines are not listed, old projects still add them as compilation options using /D
		# Retrieve all defines from compilation options (COMPILE_OPTIONS and INTERFACE_COMPILE_OPTIONS)
		# Be careful as some defines use -D and some use /D
		# Be careful as some defines use generator expression ($<$<CONFIG:Debug>:-DDEBUG>) so we might want to forward as is
		# TODO: We probably don't want to add defines from all targets globally as some might be mutually exclusive (shared lib vs static lib)
	endforeach()

	# Remove duplicates
	list(REMOVE_DUPLICATES DEFINES_LIST)

	# Return the list
	set(${COMPILER_DEFINES} "${DEFINES_LIST}" PARENT_SCOPE)
endfunction()

macro(_cu_vscode_append_build_task_target TARGET_NAME IS_DEFAULT IS_LAST)
	# Multi-config project
	if(DEFINED CMAKE_CONFIGURATION_TYPES)
		_cu_vscode_append_build_task("Debug" "${TARGET_NAME}" ${IS_DEFAULT} FALSE)
		_cu_vscode_append_build_task("Release" "${TARGET_NAME}" FALSE ${IS_LAST})
	else()
		# Single-config project
		_cu_vscode_append_build_task("${CMAKE_BUILD_TYPE}" "${TARGET_NAME}" ${IS_DEFAULT} ${IS_LAST})
	endif()
endmacro()

function(_cu_vscode_write_workspace)
	message(STATUS "Generating Visual Studio Code workspace file")

	get_property(targetsList GLOBAL PROPERTY CU_VSCODE_LAUNCH_TARGETS)

	# Multi-config project
	if(DEFINED CMAKE_CONFIGURATION_TYPES)
		set(VS_WORKSPACE_GENERATE_CONFIG "Debug")
	else()
		# Single-config project
		set(VS_WORKSPACE_GENERATE_CONFIG "${CMAKE_BUILD_TYPE}")
	endif()

	## Set workspace file
	set(VS_WORKSPACE_FILE "${CMAKE_BINARY_DIR}/${PROJECT_NAME}.code-workspace")

	## File header
	set(VS_WORKSPACE_FILE_CONTENT "{\n")

	## Settings
	# Prefix
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\"settings\": {\n")
	# Exclude files
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t\"files.exclude\": {\n")
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t\t\"**/.git\": true,\n")
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t\t\"**/.vscode\": true,\n")
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t\t\"**/_*\": true,\n")
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t\t\"**/.DS_Store\": true,\n")
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t\t\"**/Thumbs.db\": true\n")
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t},\n")
	# C_Cpp_Defaults
	# Merge configuration flag
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t\"C_Cpp.default.mergeConfigurations\": true,\n")
	# Write compiler path
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t\"C_Cpp.default.compilerPath\": \"${CMAKE_CXX_COMPILER}\",\n")
	# Write c/cpp standard
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t\"C_Cpp.default.cStandard\": \"c${CMAKE_CXX_STANDARD}\",\n\t\t\"C_Cpp.default.cppStandard\": \"c++${CMAKE_CXX_STANDARD}\",\n")
	if(WIN32)
		if("${CU_TARGET_ARCH}" STREQUAL "32")
			set(INTELLISENSE_MODE "windows-msvc-x86")
		else()
			set(INTELLISENSE_MODE "windows-msvc-x64")
		endif()
	elseif(APPLE)
		set(INTELLISENSE_MODE "clang-x64")
	else()
		set(INTELLISENSE_MODE "gcc-x64")
	endif()
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t\"C_Cpp.default.intelliSenseMode\": \"${INTELLISENSE_MODE}\",\n")
	# Write include paths
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t\"C_Cpp.default.includePath\": [")
	_cu_vscode_get_include_paths(INCLUDE_PATHS_LIST)
	set(isFirstTarget TRUE)
	foreach(includePath ${INCLUDE_PATHS_LIST})
		# Ignore INSTALL_INTERFACE include paths
		if("${includePath}" MATCHES "^\\$<INSTALL_INTERFACE")
			continue()
		endif()
		# We must add a comma if it's not the first target
		if(NOT ${isFirstTarget})
			string(APPEND VS_WORKSPACE_FILE_CONTENT ",")
		endif()
		set(isFirstTarget FALSE)
		string(APPEND VS_WORKSPACE_FILE_CONTENT "\n\t\t\t\"${includePath}\"")
	endforeach()
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\n\t\t],\n")
	# Write defines
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t\"C_Cpp.default.defines\": [")
	_cu_vscode_get_compiler_defines(DEFINES_LIST)
	set(isFirstTarget TRUE)
	foreach(define ${DEFINES_LIST})
		# We must add a comma if it's not the first target
		if(NOT ${isFirstTarget})
			string(APPEND VS_WORKSPACE_FILE_CONTENT ",")
		endif()
		set(isFirstTarget FALSE)
		string(APPEND VS_WORKSPACE_FILE_CONTENT "\n\t\t\t\"${define}\"")
	endforeach()
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\n\t\t]\n")
	# Postfix
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t},\n")

	## Add folders
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\"folders\": [\n")
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t{\n")
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t\t\"path\": \"..\"\n")
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t},\n")
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t{\n")
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t\t\"path\": \".\"\n")
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t}\n")
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t],\n")

	## Add build tasks
	# Prefix
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\"tasks\": {\n")
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t\"version\": \"2.0.0\",\n")
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t\"tasks\": [\n")
	# Add each target
	foreach(tarInfo ${targetsList})
		string(REPLACE "#" ";" tarInfo "${tarInfo}")
		list(GET tarInfo 0 tar)
		_cu_vscode_append_build_task_target("${tar}" FALSE FALSE)
	endforeach()
	# Add 'install' target
	_cu_vscode_append_build_task_target("install" FALSE FALSE)
	# Add 'All' target
	_cu_vscode_append_build_task_target("All" TRUE TRUE)
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t]\n")
	# Postfix
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t},\n")

	## Add launch tasks
	# Prefix
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\"launch\": {\n")
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t\"version\": \"0.2.0\",\n")
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t\t\"configurations\": [")
	# Add each target
	set(isFirstTarget TRUE)
	foreach(tarInfo ${targetsList})
		string(REPLACE "#" ";" tarInfo "${tarInfo}")
		list(GET tarInfo 0 tar)
		list(GET tarInfo 1 folder)
		list(GET tarInfo 2 isBundle)
		# We must add a comma if it's not the first target
		if(NOT ${isFirstTarget})
			string(APPEND VS_WORKSPACE_FILE_CONTENT ",")
		endif()
		set(isFirstTarget FALSE)
		string(APPEND VS_WORKSPACE_FILE_CONTENT "\n\t\t\t{")
		string(APPEND VS_WORKSPACE_FILE_CONTENT "\n\t\t\t\t\"name\": \"$<TARGET_NAME:${tar}>\",")
		string(APPEND VS_WORKSPACE_FILE_CONTENT "\n\t\t\t\t\"request\": \"launch\",")
		string(APPEND VS_WORKSPACE_FILE_CONTENT "\n\t\t\t\t\"preLaunchTask\": \"Build ${tar} [${VS_WORKSPACE_GENERATE_CONFIG}]\",")
		string(APPEND VS_WORKSPACE_FILE_CONTENT "\n\t\t\t\t\"cwd\": \"${folder}\",")
		string(APPEND VS_WORKSPACE_FILE_CONTENT "\n\t\t\t\t\"args\": [],")
		string(APPEND VS_WORKSPACE_FILE_CONTENT "\n\t\t\t\t\"stopAtEntry\": false,")
		string(APPEND VS_WORKSPACE_FILE_CONTENT "\n\t\t\t\t\"environment\": [],")
		if(APPLE)
			if(${isBundle})
				string(APPEND VS_WORKSPACE_FILE_CONTENT "\n\t\t\t\t\"MIMode\": \"lldb\",\n\t\t\t\t\"type\": \"cppdbg\",\n\t\t\t\t\"program\": \"$<TARGET_BUNDLE_DIR:${tar}>\"")
			else()
				string(APPEND VS_WORKSPACE_FILE_CONTENT "\n\t\t\t\t\"MIMode\": \"lldb\",\n\t\t\t\t\"type\": \"cppdbg\",\n\t\t\t\t\"program\": \"$<TARGET_FILE:${tar}>\"")
			endif()
		elseif(WIN32)
			string(APPEND VS_WORKSPACE_FILE_CONTENT "\n\t\t\t\t\"console\": \"externalTerminal\",\n\t\t\t\t\"type\": \"cppvsdbg\",\n\t\t\t\t\"program\": \"$<TARGET_FILE:${tar}>\"")
		else()
			string(APPEND VS_WORKSPACE_FILE_CONTENT "\n\t\t\t\t\"MIMode\": \"gdb\",\n\t\t\t\t\"type\": \"cppdbg\",\n\t\t\t\t\"program\": \"$<TARGET_FILE:${tar}>\"")
		endif()
		string(APPEND VS_WORKSPACE_FILE_CONTENT "\n\t\t\t}")
	endforeach()
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\n\t\t]\n")
	# Postfix
	string(APPEND VS_WORKSPACE_FILE_CONTENT "\t}\n")

	## End workspace file
	string(APPEND VS_WORKSPACE_FILE_CONTENT "}\n")

	# Write file for only one configuration
	file(GENERATE OUTPUT "${VS_WORKSPACE_FILE}" CONTENT "${VS_WORKSPACE_FILE_CONTENT}" CONDITION "$<CONFIG:${VS_WORKSPACE_GENERATE_CONFIG}>")
endfunction()

###############################################################################
# Utility function to download a file from an URL.
function(cu_download_file URL DESTINATION)
	file(DOWNLOAD ${URL} ${DESTINATION} STATUS DOWNLOAD_RESULT)
	list(GET DOWNLOAD_RESULT 0 ERR_CODE)
	if(NOT ${ERR_CODE} EQUAL 0)
		list(GET DOWNLOAD_RESULT 1 ERR_MSG)
		message(FATAL_ERROR "Failed to download file from ${URL}: ${ERR_MSG}")
	endif()
	message(STATUS "Downloaded file from ${URL} to ${DESTINATION}")
endfunction()

###############################################################################
# Helper function to build the marketing version string based on input variables
# Optional parameters:
#  - OUTPUT_VAR_VERSION_SPLIT <output variable> => Will output the version split in a list
#  - OVERRIDE_VERSION <version string> => Use a custom version string instead of PRJ_VERSION. This version doesn't have the same restrictions as the PRJ_VERSION
function(cu_build_marketing_version OUTPUT_VAR PRJ_VERSION MARKETING_DIGITS MARKETING_POSTFIX)
	# Parse arguments
	cmake_parse_arguments(CBMV "" "OUTPUT_VAR_VERSION_SPLIT;OVERRIDE_VERSION" "" ${ARGN})

	set(VERSION "${PRJ_VERSION}")
	if(CBMV_OVERRIDE_VERSION)
		set(VERSION "${CBMV_OVERRIDE_VERSION}")
	endif()
	# Split passed version
	string(REGEX MATCHALL "([0-9]+)" VERSION_SPLIT "${VERSION}")
	list(LENGTH VERSION_SPLIT VERSION_SPLIT_LENGTH)
	# Ensure VERSION_SPLIT always has 4 elements by adding 0s if missing
	if(${VERSION_SPLIT_LENGTH} LESS 4)
		math(EXPR LOOP_COUNT "4 - ${VERSION_SPLIT_LENGTH}")
		foreach(index RANGE 1 ${LOOP_COUNT})
			list(APPEND VERSION_SPLIT "0")
		endforeach()
		list(LENGTH VERSION_SPLIT VERSION_SPLIT_LENGTH)
	endif()

	# Compute Marketing Version String
	set(RESULT "")
	if(${MARKETING_DIGITS} GREATER 0)
		list(GET VERSION_SPLIT 0 RESULT)
		if(${MARKETING_DIGITS} GREATER 1)
			math(EXPR LOOP_COUNT "${MARKETING_DIGITS} - 1")
			foreach(index RANGE 1 ${LOOP_COUNT})
				list(GET VERSION_SPLIT ${index} LOOP_VERSION)
				string(APPEND RESULT ".${LOOP_VERSION}")
			endforeach()
		endif()
	endif()
	if(DEFINED MARKETING_POSTFIX AND NOT "${MARKETING_POSTFIX}" STREQUAL "")
		# Validate postfix format
		if(NOT ${MARKETING_POSTFIX} MATCHES "^[a-zA-Z0-9_+-]+$")
			message(FATAL_ERROR "MARKETING_POSTFIX contains invalid characters (Only alphanum, underscore, plus and minus are allowed): ${MARKETING_POSTFIX}")
		endif()
		string(APPEND RESULT "${MARKETING_POSTFIX}")
	endif()

	# Return result to the caller
	set(${OUTPUT_VAR} "${RESULT}" PARENT_SCOPE)

	# Return version split if requested
	if(CBMV_OUTPUT_VAR_VERSION_SPLIT)
		set(${CBMV_OUTPUT_VAR_VERSION_SPLIT} "${VERSION_SPLIT}" PARENT_SCOPE)
	endif()
endfunction()

###############################################################################
# Macro to be called as the last cmake command from the main cmake file
# Optional parameters:
#  - "NO_VSCODE_WORKSPACE" => Will not generate vscode workspace file
macro(cu_finalize)
	# Parse arguments
	cmake_parse_arguments(CUF "NO_VSCODE_WORKSPACE" "" "" ${ARGN})

	# Allow generator expressions in install(CODE/SCRIPT)
	cmake_policy(SET CMP0087 NEW)

	if(NOT CUF_NO_VSCODE_WORKSPACE)
		# Write vscode files
		_cu_vscode_write_workspace()
	endif()

	# Check if MARKETING_VERSION_DIGITS and MARKETING_VERSION_POSTFIX are set (if not, it means gen_cmake doesn't match this file)
	if(NOT DEFINED MARKETING_VERSION_DIGITS OR NOT DEFINED MARKETING_VERSION_POSTFIX)
		message(WARNING "MARKETING_VERSION_DIGITS and MARKETING_VERSION_POSTFIX are not set, please upgrade bashUtils to the latest version (ignore if gen_cmake/gen_install is not used)")
	else()
		# Dummy call to prevent warning (unused variable)
		cu_build_marketing_version(DUMMY_MARKETING_VERSION "1.0.0.0" ${MARKETING_VERSION_DIGITS} "${MARKETING_VERSION_POSTFIX}")
	endif()
endmacro()

###############################################################################
# Setup common variables for a C/CXX project
# WARNING, this is a macro, meaning variables defined inside this function will be accessible from the caller
# Optional parameters:
#  - "MARKETING_VERSION_DIGITS <digits count>" => Number of digits to use for the marketing version (defaults to 2)
#  - "MARKETING_VERSION_POSTFIX <postfix name>" => Postfix string to add to the marketing version (Only alphanum, underscore, plus and minus are allowed)
#  - "MARKETING_VERSION <version string>" => Use a custom version string for the marketing version. This version doesn't have the same restrictions as the PRJ_VERSION
macro(cu_setup_project PRJ_NAME PRJ_VERSION PRJ_DESC)
	message(STATUS "Defining project ${PRJ_NAME}")
	project(${PRJ_NAME} LANGUAGES C CXX VERSION ${PRJ_VERSION})
	set(CU_PROJECT_PRODUCTDESCRIPTION ${PRJ_DESC}) # Immediately override the default product description

	# Parse optional arguments
	cmake_parse_arguments(CUSP "" "MARKETING_VERSION_DIGITS;MARKETING_VERSION_POSTFIX;MARKETING_VERSION" "" ${ARGN})

	# Forward the optional arguments
	cu_setup_project_version_variables(${PRJ_VERSION} MARKETING_VERSION_DIGITS ${CUSP_MARKETING_VERSION_DIGITS} MARKETING_VERSION_POSTFIX ${CUSP_MARKETING_VERSION_POSTFIX} MARKETING_VERSION ${CUSP_MARKETING_VERSION})
endmacro()

###############################################################################
# Define many variables based on project version
# WARNING, this is a macro, meaning variables defined inside this function will be accessible from the caller
# Optional parameters:
#  - "MARKETING_VERSION_DIGITS <digits count>" => Number of digits to use for the marketing version (defaults to 2)
#  - "MARKETING_VERSION_POSTFIX <postfix name>" => Postfix string to add to the marketing version (Only alphanum, underscore, plus and minus are allowed)
#  - "MARKETING_VERSION <version string>" => Use a custom version string for the marketing version. This version doesn't have the same restrictions as the PRJ_VERSION
macro(cu_setup_project_version_variables PRJ_VERSION)
	# Parse optional arguments
	cmake_parse_arguments(CUSPVV "" "MARKETING_VERSION_DIGITS;MARKETING_VERSION_POSTFIX;MARKETING_VERSION" "" ${ARGN})

	if(CUSPVV_MARKETING_VERSION_DIGITS)
		set(CU_PROJECT_MARKETING_VERSION_DIGITS ${CUSPVV_MARKETING_VERSION_DIGITS})
	endif()
	if(CUSPVV_MARKETING_VERSION_POSTFIX)
		set(CU_PROJECT_MARKETING_VERSION_POSTFIX ${CUSPVV_MARKETING_VERSION_POSTFIX})
	endif()

	# Define some project properties
	if(NOT CU_PROJECT_COMPANYNAME)
		set(CU_PROJECT_COMPANYNAME "${CU_COMPANY_NAME}")
		message(STATUS "CU_PROJECT_COMPANYNAME not set, using default value: ${CU_PROJECT_COMPANYNAME}")
	endif()
	if(NOT CU_PROJECT_LEGALCOPYRIGHT)
		set(CU_PROJECT_LEGALCOPYRIGHT "(c) ${CU_COPYRIGHT_HOLDER}")
		message(STATUS "CU_PROJECT_LEGALCOPYRIGHT not set, using default value: ${CU_PROJECT_LEGALCOPYRIGHT}")
	endif()
	if(NOT CU_PROJECT_READABLE_COPYRIGHT)
		string(TIMESTAMP CU_YEAR %Y)
		if(${CU_YEAR} STREQUAL ${CU_PROJECT_STARTING_YEAR})
			set(CU_PROJECT_READABLE_COPYRIGHT "Copyright ${CU_YEAR}, ${CU_COPYRIGHT_HOLDER}")
		else()
			set(CU_PROJECT_READABLE_COPYRIGHT "Copyright ${CU_PROJECT_STARTING_YEAR}-${CU_YEAR}, ${CU_COPYRIGHT_HOLDER}")
		endif()
		message(STATUS "CU_PROJECT_READABLE_COPYRIGHT not set, using default value: ${CU_PROJECT_READABLE_COPYRIGHT}")
	endif()

	# Split PRJ_VERSION string
	string(REGEX MATCHALL "([0-9]+)" CU_PROJECT_VERSION_SPLIT "${PRJ_VERSION}")
	list(LENGTH CU_PROJECT_VERSION_SPLIT CU_PROJECT_VERSION_SPLIT_LENGTH)
	if(${CU_PROJECT_VERSION_SPLIT_LENGTH} LESS 3)
		message(FATAL_ERROR "Cannot parse version string")
	endif()
	list(GET CU_PROJECT_VERSION_SPLIT 0 CU_PROJECT_VERSION_MAJOR)
	list(GET CU_PROJECT_VERSION_SPLIT 1 CU_PROJECT_VERSION_MINOR)
	list(GET CU_PROJECT_VERSION_SPLIT 2 CU_PROJECT_VERSION_PATCH)
	if(${CU_PROJECT_VERSION_SPLIT_LENGTH} EQUAL 4)
		list(GET CU_PROJECT_VERSION_SPLIT 3 CU_PROJECT_VERSION_BETA)
	else()
		list(APPEND CU_PROJECT_VERSION_SPLIT "0")
		set(CU_PROJECT_VERSION_BETA "0")
	endif()
	unset(CU_PROJECT_VERSION_SPLIT_LENGTH)

	if(${CU_PROJECT_VERSION_BETA} STREQUAL "0")
		set(CU_PROJECT_CMAKEVERSION_STRING "${CU_PROJECT_VERSION_MAJOR}.${CU_PROJECT_VERSION_MINOR}.${CU_PROJECT_VERSION_PATCH}")
		set(CU_PROJECT_FRIENDLY_VERSION "${CU_PROJECT_VERSION_MAJOR}.${CU_PROJECT_VERSION_MINOR}.${CU_PROJECT_VERSION_PATCH}")
	else()
		set(CU_PROJECT_CMAKEVERSION_STRING "${CU_PROJECT_VERSION_MAJOR}.${CU_PROJECT_VERSION_MINOR}.${CU_PROJECT_VERSION_PATCH}.${CU_PROJECT_VERSION_BETA}")
		set(CU_PROJECT_FRIENDLY_VERSION "${CU_PROJECT_VERSION_MAJOR}.${CU_PROJECT_VERSION_MINOR}.${CU_PROJECT_VERSION_PATCH}${CU_BETA_TAG}${CU_PROJECT_VERSION_BETA}")
	endif()
	set(CU_PROJECT_FILEVERSION_STRING "${CU_PROJECT_VERSION_MAJOR}.${CU_PROJECT_VERSION_MINOR}.${CU_PROJECT_VERSION_PATCH}.${CU_PROJECT_VERSION_BETA}")

	# Backward compatibility defines
	set(CU_PROJECT_VERSION_STRING "${CU_PROJECT_FRIENDLY_VERSION}")
	set(CU_PROJECT_PRODUCTVERSION "${CU_PROJECT_VERSION_MAJOR}.${CU_PROJECT_VERSION_MINOR}.${CU_PROJECT_VERSION_PATCH}")
	set(CU_PROJECT_VERSIONMAJ "${CU_PROJECT_VERSION_MAJOR}")
	set(CU_PROJECT_VERSIONMIN "${CU_PROJECT_VERSION_MINOR}")
	set(CU_PROJECT_VERSIONPATCH "${CU_PROJECT_VERSION_PATCH}")
	set(CU_PROJECT_VERSIONBETA "${CU_PROJECT_VERSION_BETA}")

	# Compute Marketing Version String (Visible)
	if(NOT DEFINED CU_PROJECT_MARKETING_VERSION_DIGITS)
		set(CU_PROJECT_MARKETING_VERSION_DIGITS 2)
		message(STATUS "CU_PROJECT_MARKETING_VERSION_DIGITS not set, using default value: ${CU_PROJECT_MARKETING_VERSION_DIGITS} digits")
	endif()
	cu_build_marketing_version(CU_PROJECT_MARKETING_VERSION ${PRJ_VERSION} ${CU_PROJECT_MARKETING_VERSION_DIGITS} "${CU_PROJECT_MARKETING_VERSION_POSTFIX}")

	# Compute user marketing version string
	if(CUSPVV_MARKETING_VERSION)
		cu_build_marketing_version(CU_PROJECT_USER_MARKETING_VERSION ${CUSPVV_MARKETING_VERSION} ${CU_PROJECT_MARKETING_VERSION_DIGITS} "${CU_PROJECT_MARKETING_VERSION_POSTFIX}" OUTPUT_VAR_VERSION_SPLIT CU_USER_MARKETING_VERSION_SPLIT)
	else()
		unset(CU_PROJECT_USER_MARKETING_VERSION)
		unset(CU_USER_MARKETING_VERSION_SPLIT)
	endif()

	# Compute a build number based on version
	set(BETA_NUMBER_DIGITS_COUNT 5)
	math(EXPR CU_BUILD_NUMBER "${CU_PROJECT_VERSION_MAJOR} * 1000000 + ${CU_PROJECT_VERSION_MINOR} * 1000 + ${CU_PROJECT_VERSION_PATCH}")
	if(${CU_PROJECT_VERSION_BETA} STREQUAL "0")
		string(APPEND CU_BUILD_NUMBER ".")
		foreach(index RANGE 1 ${BETA_NUMBER_DIGITS_COUNT})
			string(APPEND CU_BUILD_NUMBER "9")
		endforeach()
	else()
		string(LENGTH "${CU_PROJECT_VERSION_BETA}" LEN)
		string(APPEND CU_BUILD_NUMBER ".")
		if(${LEN} LESS ${BETA_NUMBER_DIGITS_COUNT})
			math(EXPR LOOP_COUNT "${BETA_NUMBER_DIGITS_COUNT} - ${LEN}")
			foreach(index RANGE 1 ${LOOP_COUNT})
				string(APPEND CU_BUILD_NUMBER "0")
			endforeach()
		endif()
		string(APPEND CU_BUILD_NUMBER "${CU_PROJECT_VERSION_BETA}")
	endif()
endmacro()

# Detect architecture
cu_private_detect_arch()

# Print version message
message(STATUS "CMake Macros v12.0")

# Load and parse an optional cmake file, allowing overriding variables and other things before really processing the main CMakeLists.txt file
include("local_definitions.cmake" OPTIONAL)

# Common Project Macros to help setup a CMake project

# Avoid multi inclusion of this file (cannot use include_guard as multiple copies of this file are included from multiple places)
if(CU_PROJECT_MACROS_INCLUDED)
	return()
endif()
set(CU_PROJECT_MACROS_INCLUDED true)

# Some global variables
set(CU_ROOT_DIR "${PROJECT_SOURCE_DIR}") # Folder containing the main CMakeLists.txt for the repository including this file
set(CU_TOP_LEVEL_BINARY_DIR "${PROJECT_BINARY_DIR}") # Folder containing the top level binary files (CMake root output folder)
set(CMAKE_MACROS_FOLDER "${CMAKE_CURRENT_LIST_DIR}")
set(CU_TARGET_ARCH "32")
if(CMAKE_SIZEOF_VOID_P EQUAL 8)
	set(CU_TARGET_ARCH "64")
endif()

# Include TargetSetupDeploy script
include(${CMAKE_CURRENT_LIST_DIR}/helpers/TargetSetupDeploy.cmake)

###############################################################################
# Internal functions
function(cu_private_get_sign_command_options OUT_VAR)
	set(${OUT_VAR} SIGNTOOL_OPTIONS ${CU_SIGNTOOL_OPTIONS} /d \"${CU_COMPANY_NAME} ${PROJECT_NAME}\" CODESIGN_OPTIONS --timestamp --deep --strict --force --options=runtime CODESIGN_IDENTITY \"${CU_BINARY_SIGNING_IDENTITY}\" PARENT_SCOPE)
endfunction()

#
function(cu_private_setup_signing_command TARGET_NAME)
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
				set_target_properties(${TARGET_NAME} PROPERTIES
					XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT[variant=Debug] "dwarf-with-dsym"
					XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT[variant=Release] "dwarf-with-dsym"
					XCODE_ATTRIBUTE_DEPLOYMENT_POSTPROCESSING[variant=Debug] "NO"
					XCODE_ATTRIBUTE_DEPLOYMENT_POSTPROCESSING[variant=Release] "YES"
				)
			endif()
		else()
			# If not using Xcode, we have to do the dSYM/strip steps manually (but only for binary targets)
			if(${targetType} STREQUAL "SHARED_LIBRARY" OR ${targetType} STREQUAL "EXECUTABLE")
				add_custom_command(
					TARGET ${TARGET_NAME}
					POST_BUILD
					COMMAND dsymutil "$<TARGET_FILE:${TARGET_NAME}>"
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
			if(${isFramework} AND "${CMAKE_GENERATOR}" STREQUAL "Xcode") # Only xcode seems to put dSYM at the same location than bundle/framework dir
				install(FILES "$<TARGET_BUNDLE_DIR:${TARGET_NAME}>.dSYM" DESTINATION "${SYMBOLS_DEST_PATH}" CONFIGURATIONS Release Debug)
			else()
				install(FILES "$<TARGET_FILE:${TARGET_NAME}>.dSYM" DESTINATION "${SYMBOLS_DEST_PATH}" CONFIGURATIONS Release Debug)
			endif()
		elseif(${targetType} STREQUAL "EXECUTABLE")
			cu_is_macos_bundle(${TARGET_NAME} isBundle)
			if(${isBundle} AND "${CMAKE_GENERATOR}" STREQUAL "Xcode") # Only xcode seems to put dSYM at the same location than bundle/framework dir
				install(FILES "$<TARGET_BUNDLE_DIR:${TARGET_NAME}>.dSYM" DESTINATION "${SYMBOLS_DEST_PATH}" CONFIGURATIONS Release Debug)
			else()
				install(FILES "$<TARGET_FILE:${TARGET_NAME}>.dSYM" DESTINATION "${SYMBOLS_DEST_PATH}" CONFIGURATIONS Release Debug)
			endif()
		endif()
	endif()
endfunction()

###############################################################################
# Setup symbols for a target.
function(cu_setup_symbols TARGET_NAME)
	# Force symbols file generation
	cu_force_symbols_file(${TARGET_NAME})

	# Copy symbols to a common location
	cu_copy_symbols(${TARGET_NAME})
endfunction()

###############################################################################
# Setup Xcode automatic codesigning (required since Catalina).
function(cu_setup_xcode_codesigning TARGET_NAME)
	# Set codesigning for macOS
	if(APPLE)
		if("${CMAKE_GENERATOR}" STREQUAL "Xcode")
			# Force Xcode signing identity but only if defined to something valid (we will re-sign later anyway)
			if(NOT "${CU_TEAM_IDENTIFIER}" STREQUAL "-")
				set_target_properties(${TARGET_NAME} PROPERTIES XCODE_ATTRIBUTE_DEVELOPMENT_TEAM "${CU_TEAM_IDENTIFIER}")
			endif()
			# For xcode code signing to go deeply so all our dylibs are signed as well (will fail with xcode >= 11 otherwise)
			set_target_properties(${TARGET_NAME} PROPERTIES XCODE_ATTRIBUTE_OTHER_CODE_SIGN_FLAGS "--timestamp --deep --strict --force --options=runtime")
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
	else()
		set(PARAM_TO_READ "CUSAMV_MACOS")
	endif()

	if(${PARAM_TO_READ})
		# Check if we must set a new value (nothing in cache or greater version already set)
		if(NOT DEFINED CMAKE_OSX_DEPLOYMENT_TARGET OR CMAKE_OSX_DEPLOYMENT_TARGET VERSION_LESS ${${PARAM_TO_READ}})
			set(CMAKE_OSX_DEPLOYMENT_TARGET ${${PARAM_TO_READ}} CACHE INTERNAL "Force minimum target version" FORCE)
		endif()
	endif()
endfunction()

###############################################################################
# Setup common options for a library target
function(cu_setup_library_options TARGET_NAME)
	# Get target type for specific options
	get_target_property(targetType ${TARGET_NAME} TYPE)

	# Cannot use ARGN directly with list() command. Copy to a variable first.
	set (EXTRA_ARGS ${ARGN})
	# Did we get any optional args?
	list(LENGTH EXTRA_ARGS COUNT_EXTRA_ARGS)
	if(${COUNT_EXTRA_ARGS} GREATER 0)
		message(FATAL_ERROR "No extra arg expected when calling cu_setup_library_options.\nPotentially check for define change from ${TARGET_NAME}_cxx_STATICS to ${TARGET_NAME}_STATICS in exports.hpp\n")
	endif()

	if(MSVC)
		# Set WIN32 version since we want to target WinVista minimum
		target_compile_options(${TARGET_NAME} PRIVATE -D_WIN32_WINNT=0x0600)
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
			set_target_properties(${TARGET_NAME} PROPERTIES VERSION ${PROJECT_VERSION} SOVERSION ${PROJECT_VERSION_MAJOR})
		endif()

	# Unsupported target type
	else()
		message(FATAL_ERROR "Unsupported target type for cu_setup_library_options: ${targetType}")
	endif()

	# Setup ASAN options
	if(CU_ENABLE_ASAN)
		cu_setup_asan_options(${TARGET_NAME})
	endif()

	# Set full warnings (including treat warnings as error)
	cu_set_maximum_warnings(${TARGET_NAME})
	
	# Set parallel build
	cu_set_parallel_build(${TARGET_NAME})

	# Set the "DEBUG" define in debug compilation mode
	cu_set_debug_define(${TARGET_NAME})
	
	# Prevent visual studio deprecated warnings about CRT and Sockets
	cu_remove_vs_deprecated_warnings(${TARGET_NAME})
	
	# Add a postfix in debug mode
	set_target_properties(${TARGET_NAME} PROPERTIES DEBUG_POSTFIX "-d")

	# Set xcode automatic codesigning
	cu_setup_xcode_codesigning(${TARGET_NAME})

	# Use cmake folders
	set_target_properties(${TARGET_NAME} PROPERTIES FOLDER "Libraries")

	# Additional include directories
	target_include_directories(${TARGET_NAME} PUBLIC $<INSTALL_INTERFACE:include> $<BUILD_INTERFACE:${CU_ROOT_DIR}/include> PRIVATE ${CMAKE_CURRENT_BINARY_DIR})
	
	# Setup debug symbols
	cu_setup_symbols(${TARGET_NAME})

endfunction()

###############################################################################
# Setup install rules for header files
function(cu_setup_headers_install_rules FILES_LIST INCLUDE_ABSOLUTE_BASE_FOLDER)
	foreach(f ${FILES_LIST})
		get_filename_component(dir ${f} DIRECTORY)
		file(RELATIVE_PATH dir ${INCLUDE_ABSOLUTE_BASE_FOLDER} ${dir})
		install(FILES ${f} CONFIGURATIONS Release DESTINATION include/${dir})
	endforeach()
endfunction()

###############################################################################
# Setup install rules for a library target, as well a signing if specified
# Optional parameters:
#  - INSTALL -> Generate CMake install rules
#  - SIGN -> Code sign (ignored for everything but SHARED_LIBRARY)
function(cu_setup_deploy_library TARGET_NAME)
	# Get target type for specific options
	get_target_property(targetType ${TARGET_NAME} TYPE)

	# Parse arguments
	cmake_parse_arguments(SDL "INSTALL;SIGN" "" "" ${ARGN})

	if(SDL_INSTALL)
		# Static library install rules
		if(${targetType} STREQUAL "STATIC_LIBRARY")
			install(TARGETS ${TARGET_NAME} EXPORT ${TARGET_NAME} ARCHIVE DESTINATION lib)
			install(EXPORT ${TARGET_NAME} DESTINATION cmake)

		# Shared library install rules
		elseif(${targetType} STREQUAL "SHARED_LIBRARY")
			# Check for SIGN option
			if(SDL_SIGN)
				cu_private_setup_signing_command(${TARGET_NAME})
			endif()

			install(TARGETS ${TARGET_NAME} EXPORT ${TARGET_NAME} RUNTIME DESTINATION bin LIBRARY DESTINATION lib ARCHIVE DESTINATION lib FRAMEWORK DESTINATION lib)
			install(EXPORT ${TARGET_NAME} DESTINATION cmake)

		# Interface library install rules
		elseif(${targetType} STREQUAL "INTERFACE_LIBRARY")
			install(TARGETS ${TARGET_NAME} EXPORT ${TARGET_NAME})
			install(EXPORT ${TARGET_NAME} DESTINATION cmake)

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
function(cu_setup_bundle_information TARGET_NAME)
	if(APPLE)
		cu_is_macos_bundle(${TARGET_NAME} isBundle)
		if(${isBundle})
			if(NOT CU_TARGET_BUNDLEIDENTIFIER)
				set(CU_TARGET_BUNDLEIDENTIFIER "${CU_REVERSE_DOMAIN_NAME}.${TARGET_NAME}")
				message(STATUS "CU_TARGET_BUNDLEIDENTIFIER not set, using default value: ${CU_TARGET_BUNDLEIDENTIFIER}")
			endif()

			set_target_properties(${TARGET_NAME} PROPERTIES
					XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "${CU_TARGET_BUNDLEIDENTIFIER}"
					MACOSX_BUNDLE_INFO_STRING "${CU_PROJECT_PRODUCTDESCRIPTION}"
					MACOSX_BUNDLE_ICON_FILE "AppIcon"
					MACOSX_BUNDLE_GUI_IDENTIFIER "${CU_TARGET_BUNDLEIDENTIFIER}"
					MACOSX_BUNDLE_BUNDLE_NAME "${PROJECT_NAME}"
					MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}"
					MACOSX_BUNDLE_COPYRIGHT "${CU_PROJECT_READABLE_COPYRIGHT}")
		endif()
	endif()
endfunction()

###############################################################################
# Setup common options for an executable target.
function(cu_setup_executable_options TARGET_NAME)
	if(MSVC)
		# Set WIN32 version since we want to target WinVista minimum
		target_compile_options(${TARGET_NAME} PRIVATE -D_WIN32_WINNT=0x0600)
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

	# Set full warnings (including treat warnings as error)
	cu_set_maximum_warnings(${TARGET_NAME})
	
	# Set parallel build
	cu_set_parallel_build(${TARGET_NAME})

	# Set the "DEBUG" define in debug compilation mode
	cu_set_debug_define(${TARGET_NAME})
	
	# Prevent visual studio deprecated warnings about CRT and Sockets
	cu_remove_vs_deprecated_warnings(${TARGET_NAME})
	
	# Add a postfix in debug mode (but only if not a macOS bundle as it is not supported and will cause error in other parts of the scripts)
	cu_is_macos_bundle(${TARGET_NAME} isBundle)
	if(NOT ${isBundle})
		set_target_properties(${TARGET_NAME} PROPERTIES DEBUG_POSTFIX "-d")
	endif()

	# Set target properties
	cu_setup_bundle_information(${TARGET_NAME})

	# Setup debug symbols
	cu_setup_symbols(${TARGET_NAME})

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
		set_target_properties(${TARGET_NAME} PROPERTIES INSTALL_RPATH "../lib")
	endif()
	
	# Set xcode automatic codesigning
	cu_setup_xcode_codesigning(${TARGET_NAME})

	target_include_directories(${TARGET_NAME} PRIVATE "${CMAKE_CURRENT_BINARY_DIR}" "${CU_ROOT_DIR}/include")

endfunction()

###############################################################################
# Setup runtime deployment rules for an executable target, for easy debug and install (if specified)
# Optional parameters:
#  - INSTALL -> Generate CMake install rules
#  - SIGN -> Code sign all binaries
#  - "BUNDLE_DIR <install directory>" => directory where to install BUNDLE file type (defaults to ".")
#  - "RUNTIME_DIR <install directory>" => directory where to install RUNTIME file type (defaults to "bin")
function(cu_setup_deploy_runtime TARGET_NAME)
	# Get target type for specific options
	get_target_property(targetType ${TARGET_NAME} TYPE)

	# Only for executables
	if(NOT ${targetType} STREQUAL "EXECUTABLE")
		message(FATAL_ERROR "Unsupported target type for cu_setup_deploy_runtime macro: ${targetType}")
	endif()

	# Get signing options
	cu_private_get_sign_command_options(SIGN_COMMAND_OPTIONS)

	# cmakeUtils deploy runtime
	cu_deploy_runtime_target(${ARGV} ${SIGN_COMMAND_OPTIONS})

	# Check for install and sign of the binary itself
	cmake_parse_arguments(SDR "INSTALL;SIGN" "BUNDLE_DIR;RUNTIME_DIR" "" ${ARGN})

	# Install directories
	set(BUNDLE_INSTALL_DIR ".")
	if(SDR_BUNDLE_DIR)
		set(BUNDLE_INSTALL_DIR "${SDR_BUNDLE_DIR}")
	endif()
	set(RUNTIME_INSTALL_DIR "bin")
	if(SDR_RUNTIME_DIR)
		set(RUNTIME_INSTALL_DIR "${SDR_RUNTIME_DIR}")
	endif()

	if(SDR_SIGN)
		cu_private_setup_signing_command(${TARGET_NAME})
	endif()

	if(SDR_INSTALL)
		install(TARGETS ${TARGET_NAME} BUNDLE DESTINATION ${BUNDLE_INSTALL_DIR} RUNTIME DESTINATION ${RUNTIME_INSTALL_DIR})
	endif()
endfunction()

###############################################################################
# Setup common variables for a C/CXX project
macro(cu_setup_project PRJ_NAME PRJ_VERSION PRJ_DESC)
	project(${PRJ_NAME} LANGUAGES C CXX VERSION ${PRJ_VERSION})

	set(CU_PROJECT_PRODUCTDESCRIPTION ${PRJ_DESC})

	set(CU_PROJECT_VERSIONMAJ ${PROJECT_VERSION_MAJOR})
	set(CU_PROJECT_VERSIONMIN ${PROJECT_VERSION_MINOR})
	set(CU_PROJECT_VERSIONPATCH ${PROJECT_VERSION_PATCH})
	if(NOT CU_PROJECT_VERSIONPATCH)
		set(CU_PROJECT_VERSIONPATCH 0)
	endif()
	set(CU_PROJECT_VERSIONBETA ${PROJECT_VERSION_TWEAK})
	if(NOT CU_PROJECT_VERSIONBETA)
		set(CU_PROJECT_VERSIONBETA 0)
		set(CU_PROJECT_VERSION_STRING "${CU_PROJECT_VERSIONMAJ}.${CU_PROJECT_VERSIONMIN}.${CU_PROJECT_VERSIONPATCH}")
		set(CU_PROJECT_CMAKEVERSION_STRING "${CU_PROJECT_VERSIONMAJ}.${CU_PROJECT_VERSIONMIN}.${CU_PROJECT_VERSIONPATCH}")
	else()
		set(CU_PROJECT_VERSION_STRING "${CU_PROJECT_VERSIONMAJ}.${CU_PROJECT_VERSIONMIN}.${CU_PROJECT_VERSIONPATCH}-beta${CU_PROJECT_VERSIONBETA}")
		set(CU_PROJECT_CMAKEVERSION_STRING "${CU_PROJECT_VERSIONMAJ}.${CU_PROJECT_VERSIONMIN}.${CU_PROJECT_VERSIONPATCH}.${CU_PROJECT_VERSIONBETA}")
	endif()

	set(CU_PROJECT_PRODUCTVERSION "${CU_PROJECT_VERSIONMAJ}.${CU_PROJECT_VERSIONMIN}.${CU_PROJECT_VERSIONPATCH}")
	set(CU_PROJECT_FILEVERSION_STRING "${CU_PROJECT_VERSIONMAJ}.${CU_PROJECT_VERSIONMIN}.${CU_PROJECT_VERSIONPATCH}.${CU_PROJECT_VERSIONBETA}")

	# Compute a build number based on version
	math(EXPR CU_BUILD_NUMBER "${CU_PROJECT_VERSIONMAJ} * 1000000 + ${CU_PROJECT_VERSIONMIN} * 1000 + ${CU_PROJECT_VERSIONPATCH}")
	if(${CU_PROJECT_VERSIONBETA} STREQUAL "0")
		set(CU_BUILD_NUMBER "${CU_BUILD_NUMBER}.999")
	else()
		set(CU_BUILD_NUMBER "${CU_BUILD_NUMBER}.${CU_PROJECT_VERSIONBETA}")
	endif()
endmacro()

###############################################################################
# Define many variables based on project version
macro(cu_setup_project_version_variables PRJ_VERSION)
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
		set(CU_PROJECT_FRIENDLY_VERSION "${CU_PROJECT_VERSION_MAJOR}.${CU_PROJECT_VERSION_MINOR}.${CU_PROJECT_VERSION_PATCH}-beta${CU_PROJECT_VERSION_BETA}")
	endif()
	set(CU_PROJECT_FILEVERSION_STRING "${CU_PROJECT_VERSION_MAJOR}.${CU_PROJECT_VERSION_MINOR}.${CU_PROJECT_VERSION_PATCH}.${CU_PROJECT_VERSION_BETA}")

	# Compute Marketing Version String (Visible)
	if(NOT DEFINED MARKETING_VERSION_DIGITS)
		set(MARKETING_VERSION_DIGITS 2)
	endif()
	set(CU_PROJECT_MARKETING_VERSION "")
	if(${MARKETING_VERSION_DIGITS} GREATER 0)
		set(CU_PROJECT_MARKETING_VERSION "${CU_PROJECT_VERSION_MAJOR}")
		if(${MARKETING_VERSION_DIGITS} GREATER 1)
			math(EXPR LOOP_COUNT "${MARKETING_VERSION_DIGITS} - 1")
			foreach(index RANGE 1 ${LOOP_COUNT})
				list(GET CU_PROJECT_VERSION_SPLIT ${index} LOOP_VERSION)
				string(APPEND CU_PROJECT_MARKETING_VERSION ".${LOOP_VERSION}")
			endforeach()
		endif()
	endif()
	if(${MARKETING_VERSION_POSTFIX})
		string(APPEND CU_PROJECT_MARKETING_VERSION "${MARKETING_VERSION_POSTFIX}")
	endif()

	# Compute a build number based on version
	math(EXPR CU_BUILD_NUMBER "${CU_PROJECT_VERSION_MAJOR} * 1000000 + ${CU_PROJECT_VERSION_MINOR} * 1000 + ${CU_PROJECT_VERSION_PATCH}")
	if(${CU_PROJECT_VERSION_BETA} STREQUAL "0")
		set(CU_BUILD_NUMBER "${CU_BUILD_NUMBER}.999")
	else()
		set(CU_BUILD_NUMBER "${CU_BUILD_NUMBER}.${CU_PROJECT_VERSION_BETA}")
	endif()
endmacro()

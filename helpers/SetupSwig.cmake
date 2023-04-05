###############################################################################
### CMake script for easy setup of SWIG

# Avoid multi inclusion of this file (cannot use include_guard as multiple copies of this file are included from multiple places)
if(CU_SETUP_SWIG_INCLUDED)
	return()
endif()
set(CU_SETUP_SWIG_INCLUDED true)

function(_private_convert_from_cygwin PATH_VARIABLE)
	find_program(CYGPATH cygpath)
	if(CYGPATH)
		execute_process(COMMAND "${CYGPATH}" -m "${${PATH_VARIABLE}}" OUTPUT_VARIABLE ${PATH_VARIABLE})
		string(STRIP "${${PATH_VARIABLE}}" ${PATH_VARIABLE})
		set(${PATH_VARIABLE} "${${PATH_VARIABLE}}" PARENT_SCOPE)
	endif()
endfunction()

function(_private_search_swig_dir_cygwin)
	if(SWIG_EXECUTABLE)
		message(STATUS "Searching for SWIG_DIR as cygwin path")
		execute_process(COMMAND "${SWIG_EXECUTABLE}" -swiglib OUTPUT_VARIABLE _swig_output ERROR_VARIABLE _swig_error RESULT_VARIABLE _swig_result)
		if(NOT _swig_result)
			string(REGEX REPLACE "[\n\r]+" ";" _SWIG_LIB ${_swig_output})
			_private_convert_from_cygwin(_SWIG_LIB)
			set(SWIG_DIR "${_SWIG_LIB}" PARENT_SCOPE)
		endif()
	endif()
endfunction()

########
# Setup SWIG
# Mandatory parameters:
#  - "TARGET_NAME <target name>" => Name of the target to link against
#  - "INTERFACE_FILE <SWIG interface file>" => Path of the SWIG interface file
#  - "LANGUAGES <target copy directory>" => Directory where to copy runtime dependencies
# Optional parameters:
#  - "SWIG_TARGET_PREFIX <prefix name to use>" => Force a specific prefix for the SWIG target instead of the default (TARGET_NAME)
#  - "REQUIRED" => Flag indicating if an error should be thrown in case swig or a language is not found
#  - "INSTALL_SUPPORT_FILES" => Flag indicating if support files are installed
#  - "VERSION <version>" => Minimum version of SWIG required
function(cu_setup_swig_target)
	# Check for cmake minimum version
	cmake_minimum_required(VERSION 3.14)

	cmake_parse_arguments(CUSST "REQUIRED;INSTALL_SUPPORT_FILES" "TARGET_NAME;INTERFACE_FILE;SWIG_TARGET_PREFIX;VERSION" "LANGUAGES" ${ARGN})

	# Check required parameters validity
	if(NOT CUSST_TARGET_NAME)
		message(FATAL_ERROR "TARGET_NAME required")
	endif()
	if(NOT TARGET ${CUSST_TARGET_NAME})
		message(FATAL_ERROR "Specified target name does not exist: ${CUSST_TARGET_NAME}")
	endif()

	if(NOT CUSST_INTERFACE_FILE)
		message(FATAL_ERROR "INTERFACE_FILE required")
	endif()
	if(NOT EXISTS "${CUSST_INTERFACE_FILE}")
		message(FATAL_ERROR "SWIG interface file not found: ${CUSST_INTERFACE_FILE} (try to specify full path)")
	endif()

	if(NOT CUSST_LANGUAGES)
		message(FATAL_ERROR "LANGUAGES required: Specify at least one SWIG language")
	endif()

	if(${CMAKE_VERSION} VERSION_GREATER_EQUAL "3.21.0")
		cmake_policy(SET CMP0122 NEW)
	endif()

	find_package(SWIG ${CUSST_VERSION} COMPONENTS ${CUSST_LANGUAGES})
	if(NOT SWIG_FOUND AND SWIG_EXECUTABLE AND NOT SWIG_DIR AND WIN32)
		_private_search_swig_dir_cygwin()
		if(SWIG_DIR)
			find_package(SWIG ${CUSST_VERSION} COMPONENTS ${CUSST_LANGUAGES})
		endif()
	endif()

	if(SWIG_FOUND)
		# Include SWIG module (version 2), as C++
		include(UseSWIG REQUIRED)
		set(UseSWIG_MODULE_VERSION 2)
		set_property(SOURCE ${CUSST_INTERFACE_FILE} PROPERTY CPLUSPLUS ON)

		# Generate a target for each supported swig languages
		foreach(SWIG_LANG ${CUSST_LANGUAGES})
			# Define some variables
			set(SWIG_FOLDER "${CMAKE_CURRENT_BINARY_DIR}/SWIG_${SWIG_LANG}")
			set(SWIG_TARGET_NAME ${CUSST_TARGET_NAME}-${SWIG_LANG})
			if(DEFINED CUSST_SWIG_TARGET_PREFIX)
				set(SWIG_TARGET_NAME ${CUSST_SWIG_TARGET_PREFIX}-${SWIG_LANG})
			endif()
			set(SWIG_BUNDLE_IDENTIFIER "${CU_REVERSE_DOMAIN_NAME}.${SWIG_TARGET_NAME}")
			message(STATUS "Generating SWIG bindings for ${SWIG_LANG}: ${SWIG_TARGET_NAME}")

			# Create the target library as SHARED (required for dynamic loading) (Cannot use MODULE as it fails to generate a proper FRAMEWORK on iOS)
			swig_add_library(${SWIG_TARGET_NAME} TYPE SHARED LANGUAGE ${SWIG_LANG} SOURCES ${CUSST_INTERFACE_FILE} OUTFILE_DIR "${SWIG_FOLDER}" OUTPUT_DIR "${SWIG_FOLDER}/${SWIG_LANG}.files")

			# Force the output prefix until https://gitlab.kitware.com/cmake/cmake/-/issues/21542 is fixed
			set_property(TARGET ${SWIG_TARGET_NAME} PROPERTY PREFIX "${CMAKE_SHARED_LIBRARY_PREFIX}")

			# Set compile flags
			#set_property(TARGET ${SWIG_TARGET_NAME} PROPERTY SWIG_COMPILE_DEFINITIONS ${SWIG_COMPILE_FLAGS})

			# Set include directories to be the same than project
			set_property(TARGET ${SWIG_TARGET_NAME} PROPERTY SWIG_USE_TARGET_INCLUDE_DIRECTORIES TRUE)

			# Link with specified target
			swig_link_libraries(${SWIG_TARGET_NAME} PRIVATE ${CUSST_TARGET_NAME})

			# On macOS build as a Framework
			if(CMAKE_SYSTEM_NAME STREQUAL "iOS" OR CMAKE_SYSTEM_NAME STREQUAL "Darwin")
				set_target_properties(${SWIG_TARGET_NAME} PROPERTIES
					FRAMEWORK TRUE
					XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "${SWIG_BUNDLE_IDENTIFIER}"
					MACOSX_FRAMEWORK_IDENTIFIER ${SWIG_BUNDLE_IDENTIFIER}
					MACOSX_FRAMEWORK_BUNDLE_VERSION ${CU_BUILD_NUMBER}
					MACOSX_FRAMEWORK_SHORT_VERSION_STRING ${CU_PROJECT_MARKETING_VERSION}
					SOVERSION ${CU_PROJECT_VERSION_MAJOR}
				)
			endif()

			# Should we install support files
			if(CUSST_INSTALL_SUPPORT_FILES)
				install(DIRECTORY "${SWIG_FOLDER}/${SWIG_LANG}.files/" CONFIGURATIONS Release DESTINATION "swig/${SWIG_LANG}")
			endif()
		endforeach()

		# Should we install support files
		if(CUSST_INSTALL_SUPPORT_FILES)
			install(FILES "${CUSST_INTERFACE_FILE}" CONFIGURATIONS Release DESTINATION swig)
		endif()

	else()
		if(CUSST_REQUIRED)
			message(FATAL_ERROR "Couldn't find SWIG module or languages")
		else()
			message(STATUS "Couldn't find SWIG module or languages")
		endif()
	endif()
endfunction()

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
#  - "LANGUAGES <target language> [<other target language>...]" => List of target languages to generate bindings for
# Optional parameters:
#  - "SWIG_TARGET_PREFIX <prefix name to use>" => Force a specific prefix for the SWIG target (Default: ${TARGET_NAME})
#  - "REQUIRED" => Flag indicating if an error should be thrown in case swig or a language is not found
#  - "INSTALL_SUPPORT_FILES" => Flag indicating if support files are installed
#  - "VERSION <version>" => Minimum version of SWIG required
#  - "FILE_DEPENDENCIES <file> [<other file>...]" => List of files to add as dependencies of the SWIG target
#  - "INSTALL_CONFIGURATIONS <List of install configuration>" -> Select the configurations for which the install rules will be generated (Default: Release)
#  - "INTERFACE_FILE_COMPILE_OPTIONS_CSHARP <List of compile options>" -> List of compile options to add to the SWIG interface file for C#
#  - "INTERFACE_FILE_COMPILE_OPTIONS_LUA <List of compile options>" -> List of compile options to add to the SWIG interface file for LUA
#  - "INTERFACE_FILE_COMPILE_OPTIONS_PYTHON <List of compile options>" -> List of compile options to add to the SWIG interface file for PYTHON
#  - "OUTVAR_PREFIX_SUPPORT_FILES_FOLDER <variable name>" => Variable name prefix to store the support files folder. Full variable name will be ${OUTVAR_PREFIX_SUPPORT_FILES_FOLDER}_${SWIG_LANG}
function(cu_setup_swig_target)
	# Check for cmake minimum version
	cmake_minimum_required(VERSION 3.29) # Required due to bug in previous versions (https://gitlab.kitware.com/cmake/cmake/-/issues/25405)

	cmake_parse_arguments(CUSST "REQUIRED;INSTALL_SUPPORT_FILES" "TARGET_NAME;INTERFACE_FILE;SWIG_TARGET_PREFIX;VERSION;OUTVAR_PREFIX_SUPPORT_FILES_FOLDER" "LANGUAGES;FILE_DEPENDENCIES;INSTALL_CONFIGURATIONS;INTERFACE_FILE_COMPILE_OPTIONS_CSHARP;INTERFACE_FILE_COMPILE_OPTIONS_LUA;INTERFACE_FILE_COMPILE_OPTIONS_PYTHON" ${ARGN})

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

	# Create default configurations list
	set(configurationsList "Release")

	# If configurations are provided, use them instead
	if(CUSST_INSTALL_CONFIGURATIONS)
		set(configurationsList ${CUSST_INSTALL_CONFIGURATIONS})
	endif()

	# Check for cmake minimum version and set policy
	cmake_minimum_required(VERSION 3.21) # https://gitlab.kitware.com/cmake/cmake/-/issues/21542 fixed in cmake 3.21
	cmake_policy(SET CMP0122 NEW)

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

		# If building for iOS we must create a framework (so it's embedded in the app bundle, shared library are not allowed)
		if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
			set(BUILD_AS_MACOSX_FRAMEWORK TRUE)
		else()
			set(BUILD_AS_MACOSX_FRAMEWORK FALSE)
		endif()

		# Add dependencies to the interface file (globally for all languages)
		foreach(SWIG_FILE_DEPENDENCY ${CUSST_FILE_DEPENDENCIES})
			set_property(SOURCE ${CUSST_INTERFACE_FILE} APPEND PROPERTY DEPENDS ${SWIG_FILE_DEPENDENCY})
		endforeach()

		# Generate a target for each supported swig languages
		foreach(SWIG_LANG ${CUSST_LANGUAGES})
			# Define some variables
			set(SWIG_TARGET_NAME ${CUSST_TARGET_NAME}-${SWIG_LANG})
			if(DEFINED CUSST_SWIG_TARGET_PREFIX)
				set(SWIG_TARGET_NAME ${CUSST_SWIG_TARGET_PREFIX}-${SWIG_LANG})
			endif()
			set(SWIG_FOLDER "${CMAKE_CURRENT_BINARY_DIR}/SWIG_${SWIG_TARGET_NAME}")
			set(SWIG_BUNDLE_IDENTIFIER "${CU_REVERSE_DOMAIN_NAME}.${SWIG_TARGET_NAME}")
			message(STATUS "Generating SWIG bindings for ${SWIG_LANG}: ${SWIG_TARGET_NAME}")

			# We must set swig definition file compile options per language
			set(SWIG_FILE_COMPILE_OPTIONS "")
			# If building as a framework, force the output name
# Not needed anymore, it looks like swig_add_library is now able to properly set the dllimport value
#			if(BUILD_AS_MACOSX_FRAMEWORK)
#				list(APPEND SWIG_FILE_COMPILE_OPTIONS -dllimport "${SWIG_TARGET_NAME}.framework/${SWIG_TARGET_NAME}")
#			endif()
			# If swig file compile options are provided, add them to the SWIG_FILE_COMPILE_OPTIONS list
			if(${SWIG_LANG} STREQUAL "csharp")
				if(CUSST_INTERFACE_FILE_COMPILE_OPTIONS_CSHARP)
					foreach(OPT ${CUSST_INTERFACE_FILE_COMPILE_OPTIONS_CSHARP})
						list(APPEND SWIG_FILE_COMPILE_OPTIONS ${OPT})
					endforeach()
				endif()
				# If we are on a 64 bits platform, we must define USE_SIZE_T_64
				if(CMAKE_SIZEOF_VOID_P EQUAL 8)
					list(APPEND SWIG_FILE_COMPILE_OPTIONS -DUSE_SIZE_T_64)
				endif()
			elseif(${SWIG_LANG} STREQUAL "lua")
				if(CUSST_INTERFACE_FILE_COMPILE_OPTIONS_LUA)
					foreach(OPT ${CUSST_INTERFACE_FILE_COMPILE_OPTIONS_LUA})
						list(APPEND SWIG_FILE_COMPILE_OPTIONS ${OPT})
					endforeach()
				endif()
			elseif(${SWIG_LANG} STREQUAL "python")
				if(CUSST_INTERFACE_FILE_COMPILE_OPTIONS_PYTHON)
					foreach(OPT ${CUSST_INTERFACE_FILE_COMPILE_OPTIONS_PYTHON})
						list(APPEND SWIG_FILE_COMPILE_OPTIONS ${OPT})
					endforeach()
				endif()
			endif()
			# If we have some compile options for the swig definition file, set them
			if(SWIG_FILE_COMPILE_OPTIONS)
				set_property(SOURCE ${CUSST_INTERFACE_FILE} PROPERTY COMPILE_OPTIONS ${SWIG_FILE_COMPILE_OPTIONS})
			endif()

			# Support files output directory
			set(SWIG_SUPPORT_FILES_FOLDER "${SWIG_FOLDER}/${SWIG_LANG}.files")

			# If output variable for support files folder is provided, store it
			if(CUSST_OUTVAR_PREFIX_SUPPORT_FILES_FOLDER)
				set(${CUSST_OUTVAR_PREFIX_SUPPORT_FILES_FOLDER}_${SWIG_LANG} "${SWIG_SUPPORT_FILES_FOLDER}" PARENT_SCOPE)
			endif()

			# Create the target library as SHARED (required for dynamic loading) (Cannot use MODULE as it fails to generate a proper FRAMEWORK on iOS)
			swig_add_library(${SWIG_TARGET_NAME} TYPE SHARED LANGUAGE ${SWIG_LANG} SOURCES ${CUSST_INTERFACE_FILE} OUTFILE_DIR "${SWIG_FOLDER}" OUTPUT_DIR "${SWIG_SUPPORT_FILES_FOLDER}")

			# Set compile flags
			#set_property(TARGET ${SWIG_TARGET_NAME} PROPERTY SWIG_COMPILE_DEFINITIONS ${SWIG_COMPILE_FLAGS})

			# Set include directories to be the same than project
			set_property(TARGET ${SWIG_TARGET_NAME} PROPERTY SWIG_USE_TARGET_INCLUDE_DIRECTORIES TRUE)

			# Link with specified target
			swig_link_libraries(${SWIG_TARGET_NAME} PRIVATE ${CUSST_TARGET_NAME})

			# If building as a framework, set the framework properties
			if(BUILD_AS_MACOSX_FRAMEWORK)
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
				install(DIRECTORY "${SWIG_SUPPORT_FILES_FOLDER}/" CONFIGURATIONS ${configurationsList} DESTINATION "swig/${SWIG_LANG}")
			endif()
		endforeach()

		# Should we install support files
		if(CUSST_INSTALL_SUPPORT_FILES)
			install(FILES "${CUSST_INTERFACE_FILE}" CONFIGURATIONS ${configurationsList} DESTINATION swig)
		endif()

	else()
		if(CUSST_REQUIRED)
			message(FATAL_ERROR "Couldn't find SWIG module or languages")
		else()
			message(STATUS "Couldn't find SWIG module or languages")
		endif()
	endif()
endfunction()

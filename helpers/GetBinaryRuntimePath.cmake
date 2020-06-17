###############################################################################
### CMake script to retrieve the runtime path of a binary

# Avoid multi inclusion of this file (cannot use include_guard as multiple copies of this file are included from multiple places)
if(CU_GET_BINARY_RUNTIME_PATH_INCLUDED)
	return()
endif()
set(CU_GET_BINARY_RUNTIME_PATH_INCLUDED true)

########
# Get Runtime path for specified binary
# The returned path is always absolute. If the runtime path stored in the binary is relative then an absolute path is computed either using binary's folder or RELOCATION_DIR if specified.
# Mandatory parameters:
#  - "BINARY_PATH <binary path>" => Path of the binary to retrieve runtime path from
#  - "RPATH_OUTPUT <variable name>" => Variable name to write result to
# Optional parameters:
#  - "RELOCATION_DIR <binary relocation dir>" => If specified, absolute relocation directory for the binary (current binary's folder is used if not specified)
function(cu_get_binary_runtime_path)
	# Check for cmake minimum version
	cmake_minimum_required(VERSION 3.14)

	# Parse arguments
	cmake_parse_arguments(CUGBRP "" "BINARY_PATH;RPATH_OUTPUT;RELOCATION_DIR" "" ${ARGN})

	# Check required parameters validity
	if(NOT CUGBRP_BINARY_PATH)
		message(FATAL_ERROR "BINARY_PATH required")
	endif()
	if(NOT EXISTS "${CUGBRP_BINARY_PATH}")
		message(FATAL_ERROR "Specified binary does not exist: ${CUGBRP_BINARY_PATH}")
	endif()

	if(NOT CUGBRP_RPATH_OUTPUT)
		message(FATAL_ERROR "RPATH_OUTPUT required")
	endif()

	# Get target binary name and folder
	get_filename_component(BINARY_NAME ${CUGBRP_BINARY_PATH} NAME)
	get_filename_component(BINARY_FOLDER ${CUGBRP_BINARY_PATH} DIRECTORY)

	set(ABSOLUTE_BIN_DIR "${BINARY_FOLDER}")
	if(CUGBRP_RELOCATION_DIR)
		set(ABSOLUTE_BIN_DIR "${CUGBRP_RELOCATION_DIR}")
	endif()

	# Default to binary directory
	set(RPATH "${ABSOLUTE_BIN_DIR}")

	if(CMAKE_HOST_WIN32)
		# Use default

	elseif(CMAKE_HOST_APPLE)
		set(OTOOL_COMMAND "otool")

		# Extract binary information
		execute_process(COMMAND ${OTOOL_COMMAND} -l "${BINARY_NAME}" WORKING_DIRECTORY "${BINARY_FOLDER}" RESULT_VARIABLE CMD_RESULT OUTPUT_VARIABLE CMD_OUTPUT ERROR_VARIABLE CMD_OUTPUT)
		if(NOT ${CMD_RESULT} EQUAL 0)
			message(FATAL_ERROR "Failed to get binary rpath:\n## Command line => ${OTOOL_COMMAND} -l \"${BINARY_NAME}\"\n## Error Code => ${CMD_RESULT}\n## Output => ${CMD_OUTPUT}")
		endif()

		# We have to find LC_RPATH in the output
		string(REGEX MATCH "LC_RPATH[^\n]*\n.+cmdsize[^\n]*\n.+path[ ]+(.+) \\(" MATCH_RESULT "${CMD_OUTPUT}")
		if(CMAKE_MATCH_COUNT EQUAL 1)
			set(RPATH "${CMAKE_MATCH_1}")
			# Check if we have replacement to do
			string(REGEX MATCH "(@[^/]+)(.+)" REPLACEMENT_RESULT "${RPATH}")
			if(CMAKE_MATCH_COUNT EQUAL 2)
				# Check for supported replacement
				if("${CMAKE_MATCH_1}" STREQUAL "@executable_path")
					set(RPATH "${ABSOLUTE_BIN_DIR}${CMAKE_MATCH_2}")
				else()
					message(FATAL_ERROR "Unsupported replacement value: ${CMAKE_MATCH_1}")
				endif()
			endif()
			get_filename_component(RPATH "${RPATH}" ABSOLUTE BASE_DIR "${ABSOLUTE_BIN_DIR}")
		endif()

	else()
		set(READELF_COMMAND "readelf")

		# Extract binary information
		execute_process(COMMAND ${READELF_COMMAND} -d "${BINARY_NAME}" WORKING_DIRECTORY "${BINARY_FOLDER}" RESULT_VARIABLE CMD_RESULT OUTPUT_VARIABLE CMD_OUTPUT ERROR_VARIABLE CMD_OUTPUT)
		if(NOT ${CMD_RESULT} EQUAL 0)
			message(FATAL_ERROR "Failed to get binary rpath:\n## Command line => ${READELF_COMMAND} -d \"${BINARY_NAME}\"\n## Error Code => ${CMD_RESULT}\n## Output => ${CMD_OUTPUT}")
		endif()

		string(REGEX MATCH "\\(RUNPATH\\)[^[]+\\[([^]]+)\\]" MATCH_RESULT "${CMD_OUTPUT}")
		if(CMAKE_MATCH_COUNT EQUAL 1)
			# RUNPATH might contains multiple paths, ':' separated. Get the first one.
			string(REGEX MATCH "([^:]+)" MATCH_RESULT "${CMAKE_MATCH_1}")
			if(CMAKE_MATCH_COUNT EQUAL 1)
				get_filename_component(RPATH "${CMAKE_MATCH_1}" ABSOLUTE BASE_DIR "${ABSOLUTE_BIN_DIR}")
			endif()
		endif()
	endif()

	set(${CUGBRP_RPATH_OUTPUT} "${RPATH}" PARENT_SCOPE)

endfunction()

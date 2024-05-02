###############################################################################
### CMake script to retrieve the runtime path of a binary

# Avoid multi inclusion of this file (cannot use include_guard as multiple copies of this file are included from multiple places)
if(CU_GET_BINARY_RUNTIME_PATH_INCLUDED)
	return()
endif()
set(CU_GET_BINARY_RUNTIME_PATH_INCLUDED true)

##################################
# Internal functions
function(cu_private_get_binary_runpaths_macos INPUT_TEXT PATHS_OUTPUT)
	# Clear output variable
	set(${PATHS_OUTPUT} "")

	# Match all runpaths (that span multiple lines)
	string(REGEX MATCHALL "LC_RPATH[^\n]*\n[ \t]+cmdsize[^\n]*\n[ \t]+path[ ]+[^(]+ \\(" RUNPATHS_RESULT "${INPUT_TEXT}")
	# MATCHALL returns a list of all matches, we have to iterate over it (the list) to extract the actual runpaths
	if(RUNPATHS_RESULT)
		# For each found runpath entry, extract all subpaths
		foreach(RUNPATHS_WITH_CONTEXT ${RUNPATHS_RESULT})
			string(REGEX MATCH "path[ ]+([^ ]+)" RUNPATHS_RESULT "${RUNPATHS_WITH_CONTEXT}")
			# Expecting only one match
			if(CMAKE_MATCH_COUNT EQUAL 1)
				# Now we can extract all subpaths that are separated by ':'
				string(REGEX MATCHALL "([^:]+)" SUBPATHS_RESULT "${CMAKE_MATCH_1}")
				# For each subpath found, add it to the output list
				foreach(SUBPATH ${SUBPATHS_RESULT})
					# Add the subpath to the output list
					list(APPEND ${PATHS_OUTPUT} "${SUBPATH}")
				endforeach()
			endif()
		endforeach()
	endif()

	# Remove duplicates
	list(REMOVE_DUPLICATES ${PATHS_OUTPUT})

	# Return the result
	set(${PATHS_OUTPUT} ${${PATHS_OUTPUT}} PARENT_SCOPE)
endfunction()

function(cu_private_get_binary_runpaths_unix INPUT_TEXT PATHS_OUTPUT)
	# Clear output variable
	set(${PATHS_OUTPUT} "")

	# Match all runpaths (on unix systems, runpaths are stored in RUNPATH section and it seems we only have one RUNPATH section but just in case let's match all of them)
	string(REGEX MATCHALL "\\(RUNPATH\\)[^[]+\\[[^]]+\\]" RUNPATHS_RESULT "${INPUT_TEXT}")
	# MATCHALL returns a list of all matches, we have to iterate over it (the list) to extract the actual runpaths
	if(RUNPATHS_RESULT)
		# For each found runpath entry, extract all subpaths
		foreach(RUNPATHS_WITH_CONTEXT ${RUNPATHS_RESULT})
			string(REGEX MATCH "\\[([^]]+)\\]" RUNPATHS_RESULT "${RUNPATHS_WITH_CONTEXT}")
			# Expecting only one match
			if(CMAKE_MATCH_COUNT EQUAL 1)
				# Now we can extract all subpaths that are separated by ':'
				string(REGEX MATCHALL "([^:]+)" SUBPATHS_RESULT "${CMAKE_MATCH_1}")
				# For each subpath found, add it to the output list
				foreach(SUBPATH ${SUBPATHS_RESULT})
					# Add the subpath to the output list
					list(APPEND ${PATHS_OUTPUT} "${SUBPATH}")
				endforeach()
			endif()
		endforeach()
	endif()

	# Remove duplicates
	list(REMOVE_DUPLICATES ${PATHS_OUTPUT})

	# Return the result
	set(${PATHS_OUTPUT} ${${PATHS_OUTPUT}} PARENT_SCOPE)
endfunction()

function(cu_private_find_replacement_in_runpaths ABSOLUTE_BIN_DIR RUNPATHS MATCH_PATTERN MATCH_REPLACEMENT REPLACEMENT_OUTPUT)
	# Default to binary directory
	set(RPATH "${ABSOLUTE_BIN_DIR}")

	# Search all runpaths for a suitable replacement
	foreach(RUNPATH ${RUNPATHS})
		# Check if we have replacement to do
		string(REGEX MATCH "${MATCH_PATTERN}" REPLACEMENT_RESULT "${RUNPATH}")
		if(CMAKE_MATCH_COUNT EQUAL 2)
			# Check for supported replacement
			if("${CMAKE_MATCH_1}" STREQUAL "${MATCH_REPLACEMENT}")
				set(RPATH "${ABSOLUTE_BIN_DIR}${CMAKE_MATCH_2}")
				break()
			endif()
		endif()
		# Fallback to the last runpath (ie. always overwrite)
		get_filename_component(RPATH "${RUNPATH}" ABSOLUTE BASE_DIR "${ABSOLUTE_BIN_DIR}")
	endforeach()

	set(${REPLACEMENT_OUTPUT} "${RPATH}" PARENT_SCOPE)
endfunction()

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

		# Retrieve all runpaths
		set(RUNPATHS "")
		cu_private_get_binary_runpaths_macos("${CMD_OUTPUT}" RUNPATHS)

		# Find a suitable replacement
		cu_private_find_replacement_in_runpaths("${ABSOLUTE_BIN_DIR}" "${RUNPATHS}" "(^\\@[^/]+)(.+)" "@executable_path" RPATH)

	else()
		set(READELF_COMMAND "readelf")

		# Extract binary information
		execute_process(COMMAND ${READELF_COMMAND} -d "${BINARY_NAME}" WORKING_DIRECTORY "${BINARY_FOLDER}" RESULT_VARIABLE CMD_RESULT OUTPUT_VARIABLE CMD_OUTPUT ERROR_VARIABLE CMD_OUTPUT)
		if(NOT ${CMD_RESULT} EQUAL 0)
			message(FATAL_ERROR "Failed to get binary rpath:\n## Command line => ${READELF_COMMAND} -d \"${BINARY_NAME}\"\n## Error Code => ${CMD_RESULT}\n## Output => ${CMD_OUTPUT}")
		endif()

		# Retrieve all runpaths
		set(RUNPATHS "")
		cu_private_get_binary_runpaths_unix("${CMD_OUTPUT}" RUNPATHS)

		# Find a suitable replacement
		cu_private_find_replacement_in_runpaths("${ABSOLUTE_BIN_DIR}" "${RUNPATHS}" "(^\\$[^/]+)(.+)" "$ORIGIN" RPATH)

	endif()

	set(${CUGBRP_RPATH_OUTPUT} "${RPATH}" PARENT_SCOPE)

endfunction()

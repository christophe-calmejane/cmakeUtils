###############################################################################
### CMake script to retrieve the dynamic dependencies of a binary

# Avoid multi inclusion of this file (cannot use include_guard as multiple copies of this file are included from multiple places)
if(CU_GET_BINARY_DYNAMIC_DEPENDENCIES_INCLUDED)
	return()
endif()
set(CU_GET_BINARY_DYNAMIC_DEPENDENCIES_INCLUDED true)

########
# Get dynamic dependencies list for specified binary
# Mandatory parameters:
#  - "BINARY_PATH <binary path>" => Path of the binary to retrieve dependencies from
#  - "DEP_LIST_OUTPUT <variable name>" => Variable name to write result to
function(cu_get_binary_dynamic_dependencies)
	# Check for cmake minimum version
	cmake_minimum_required(VERSION 3.14)

	# Parse arguments
	cmake_parse_arguments(CUGBDD "" "BINARY_PATH;DEP_LIST_OUTPUT" "" ${ARGN})

	# Check required parameters validity
	if(NOT CUGBDD_BINARY_PATH)
		message(FATAL_ERROR "BINARY_PATH required")
	endif()
	if(NOT EXISTS "${CUGBDD_BINARY_PATH}")
		message(FATAL_ERROR "Specified binary does not exist: ${CUGBDD_BINARY_PATH}")
	endif()

	if(NOT CUGBDD_DEP_LIST_OUTPUT)
		message(FATAL_ERROR "DEP_LIST_OUTPUT required")
	endif()

	# Get target binary name and folder
	get_filename_component(BINARY_NAME ${CUGBDD_BINARY_PATH} NAME)
	get_filename_component(BINARY_FOLDER ${CUGBDD_BINARY_PATH} DIRECTORY)

	if(CMAKE_HOST_WIN32)
		set(DUMPBIN_COMMAND "dumpbin.exe")

		# Get binary dependencies
		execute_process(COMMAND ${DUMPBIN_COMMAND} /DEPENDENTS "${BINARY_NAME}" WORKING_DIRECTORY "${BINARY_FOLDER}" RESULT_VARIABLE CMD_RESULT OUTPUT_VARIABLE CMD_OUTPUT ERROR_VARIABLE CMD_OUTPUT)
		if(NOT ${CMD_RESULT} EQUAL 0)
			message(FATAL_ERROR "Failed to get binary dependencies:\n## Command line => ${DUMPBIN_COMMAND} /DEPENDENTS \"${BINARY_NAME}\"\n## Error Code => ${CMD_RESULT}\n## Output => ${CMD_OUTPUT}")
		endif()

		# Match with the leading 4 spaces so we ignore "Dump of file xxx.dll" that is outputed by dumpbin
		string(REGEX MATCHALL "    [^ .]+\\.[dD][lL][lL]" DEPENDENCIES_LIST "${CMD_OUTPUT}")
		foreach(DEPENDENCY ${DEPENDENCIES_LIST})
			# Remove the leading 4 spaces that we matched
			string(REGEX REPLACE "^    " "" DEPENDENCY "${DEPENDENCY}")
			# Append to list
			list(APPEND ${CUGBDD_DEP_LIST_OUTPUT} "${DEPENDENCY}")
		endforeach()

	elseif(CMAKE_HOST_APPLE)
		set(OTOOL_COMMAND "otool")

		# Get binary dependencies
		execute_process(COMMAND ${OTOOL_COMMAND} -L "${BINARY_NAME}" WORKING_DIRECTORY "${BINARY_FOLDER}" RESULT_VARIABLE CMD_RESULT OUTPUT_VARIABLE CMD_OUTPUT ERROR_VARIABLE CMD_OUTPUT)
		if(NOT ${CMD_RESULT} EQUAL 0)
			message(FATAL_ERROR "Failed to get binary dependencies:\n## Command line => ${OTOOL_COMMAND} -L \"${BINARY_NAME}\"\n## Error Code => ${CMD_RESULT}\n## Output => ${CMD_OUTPUT}")
		endif()

		# Since CMake regex does not support lookaround and capture groups do not return all results in a MATCHALL, we split the output result in lines, then match a single expression for each line
		string(REGEX MATCHALL "[^\n]+" SPLIT_LINES "${CMD_OUTPUT}")
		foreach(LINE ${SPLIT_LINES})
			string(REGEX MATCH "@rpath/([^\n]+\\.dylib)" MATCH_RESULT "${LINE}")
			if(CMAKE_MATCH_COUNT EQUAL 1)
				# Append to list
				list(APPEND ${CUGBDD_DEP_LIST_OUTPUT} "${CMAKE_MATCH_1}")
			endif()
		endforeach()

	else()
		set(READELF_COMMAND "readelf")

		# Get binary dependencies
		execute_process(COMMAND ${READELF_COMMAND} -d "${BINARY_NAME}" WORKING_DIRECTORY "${BINARY_FOLDER}" RESULT_VARIABLE CMD_RESULT OUTPUT_VARIABLE CMD_OUTPUT ERROR_VARIABLE CMD_OUTPUT)
		if(NOT ${CMD_RESULT} EQUAL 0)
			message(FATAL_ERROR "Failed to get binary dependencies:\n## Command line => ${READELF_COMMAND} -d \"${BINARY_NAME}\"\n## Error Code => ${CMD_RESULT}\n## Output => ${CMD_OUTPUT}")
		endif()

		# Since CMake regex does not support lookaround and capture groups do not return all results in a MATCHALL, we split the output result in lines, then match a single expression for each line
		string(REGEX MATCHALL "[^\n]+" SPLIT_LINES "${CMD_OUTPUT}")
		foreach(LINE ${SPLIT_LINES})
			string(REGEX MATCH "\\(NEEDED\\)[^[]+\\[([^]]+)\\]" MATCH_RESULT "${LINE}")
			if(CMAKE_MATCH_COUNT EQUAL 1)
				# Append to list
				list(APPEND ${CUGBDD_DEP_LIST_OUTPUT} "${CMAKE_MATCH_1}")
			endif()
		endforeach()

	endif()

	set(${CUGBDD_DEP_LIST_OUTPUT} ${${CUGBDD_DEP_LIST_OUTPUT}} PARENT_SCOPE)
endfunction()

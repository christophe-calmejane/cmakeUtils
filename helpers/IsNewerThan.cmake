###############################################################################
### CMake script comparing files returning if the first is newer than the second one
### Note: the if:IS_NEWER_THAN command returns TRUE is both files are identical, which might not always be desirable

cmake_minimum_required(VERSION 3.15)

# Avoid multi inclusion of this file
if(CU_IS_NEWER_THAN_INCLUDED)
	return()
endif()
set(CU_IS_NEWER_THAN_INCLUDED true)

########
# Checks if a file is newer than another one
# Returns TRUE if both files exist and if the first one is stricly newer than the second one
# If any of the files doesn't exist, TRUE is also returned.
function(cu_is_newer_than FIRST_FILE SECOND_FILE RESULT_VAR)
	# First, check if both files are identical
	execute_process(COMMAND "${CMAKE_COMMAND}" -E compare_files "${FIRST_FILE}" "${SECOND_FILE}" RESULT_VARIABLE CMD_RESULT OUTPUT_VARIABLE CMD_OUTPUT ERROR_VARIABLE CMD_OUTPUT)

	# If they are not
	if(NOT ${CMD_RESULT} EQUAL 0)
		# Check for IS_NEWER_THAN
		if("${FIRST_FILE}" IS_NEWER_THAN "${SECOND_FILE}")
			# message(STATUS "cu_is_newer_than(${FIRST_FILE} ${SECOND_FILE}) => TRUE")
			set(${RESULT_VAR} TRUE PARENT_SCOPE)
			return()
		endif()
	endif()

	# message(STATUS "cu_is_newer_than(${FIRST_FILE} ${SECOND_FILE}) => FALSE")
	set(${RESULT_VAR} FALSE PARENT_SCOPE)
endfunction()

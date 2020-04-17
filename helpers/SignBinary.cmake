###############################################################################
### CMake script handling code signing of the binary

cmake_minimum_required(VERSION 3.15)

# Avoid multi inclusion of this file
if(CU_SIGN_BINARY_INCLUDED)
	return()
endif()
set(CU_SIGN_BINARY_INCLUDED true)

########
# Code sign a binary
# Mandatory parameters:
#  - "BINARY_PATH <binary path>" => Path of the binary to sign
# Optional parameters:
#  - "SIGNTOOL_OPTIONS <windows signtool options>..." => list of options to pass to windows signtool utility (signing will be done on all runtime dependencies if this is specified)
#  - "SIGNTOOL_AGAIN_OPTIONS <windows signtool options>..." => list of options to pass to a secondary signtool call (to add another signature)
#  - "CODESIGN_OPTIONS <macOS codesign options>..." => list of options to pass to macOS codesign utility (signing will be done on all runtime dependencies if this is specified)
#  - "CODESIGN_IDENTITY <signing identity>" => code signing identity to be used by macOS codesign utility (autodetect will be used if not specified)
function(cu_sign_binary)
	# Parse arguments
	cmake_parse_arguments(SIGN "" "BINARY_PATH;CODESIGN_IDENTITY" "SIGNTOOL_OPTIONS;SIGNTOOL_AGAIN_OPTIONS;CODESIGN_OPTIONS" ${ARGN})

	# Check required parameters validity
	if(NOT SIGN_BINARY_PATH)
		message(FATAL_ERROR "BINARY_PATH required")
	endif()
	if(NOT EXISTS "${SIGN_BINARY_PATH}")
		message(FATAL_ERROR "Specified binary does not exist: ${SIGN_BINARY_PATH}")
	endif()

	message(" - Signing ${SIGN_BINARY_PATH}")
	if(CMAKE_HOST_WIN32)
		execute_process(COMMAND signtool sign ${SIGN_SIGNTOOL_OPTIONS} "${SIGN_BINARY_PATH}" RESULT_VARIABLE CMD_RESULT OUTPUT_VARIABLE CMD_OUTPUT ERROR_VARIABLE CMD_OUTPUT)
		if(NOT ${CMD_RESULT} EQUAL 0)
			# Expand options lists
			string(REPLACE ";" " " SIGNTOOL_OPTIONS "${SIGN_SIGNTOOL_OPTIONS}")
			message(FATAL_ERROR "Failed to sign:\n## Command line => signtool sign ${SIGNTOOL_OPTIONS} \"${SIGN_BINARY_PATH}\"\n## Error Code => ${CMD_RESULT}\n## Output => ${CMD_OUTPUT}")
		endif()
		if(SIGN_SIGNTOOL_AGAIN_OPTIONS)
			execute_process(COMMAND signtool sign ${SIGN_SIGNTOOL_AGAIN_OPTIONS} "${SIGN_BINARY_PATH}" RESULT_VARIABLE CMD_RESULT OUTPUT_VARIABLE CMD_OUTPUT ERROR_VARIABLE CMD_OUTPUT)
			if(NOT ${CMD_RESULT} EQUAL 0)
				# Expand options lists
				string(REPLACE ";" " " SIGNTOOL_AGAIN_OPTIONS "${SIGN_SIGNTOOL_AGAIN_OPTIONS}")
				message(FATAL_ERROR "Failed to sign:\n## Command line => signtool sign ${SIGNTOOL_AGAIN_OPTIONS} \"${SIGN_BINARY_PATH}\"\n## Error Code => ${CMD_RESULT}\n## Output => ${CMD_OUTPUT}")
			endif()
		endif()
	elseif(CMAKE_HOST_APPLE)
		set(IDENTITY "-")
		if(SIGN_CODESIGN_IDENTITY)
			set(IDENTITY "${SIGN_CODESIGN_IDENTITY}")
		endif()
		execute_process(COMMAND codesign -s "${IDENTITY}" ${SIGN_CODESIGN_OPTIONS} "${SIGN_BINARY_PATH}" RESULT_VARIABLE CMD_RESULT OUTPUT_VARIABLE CMD_OUTPUT ERROR_VARIABLE CMD_OUTPUT)
		if(NOT ${CMD_RESULT} EQUAL 0)
			# Expand options lists
			string(REPLACE ";" " " CODESIGN_OPTIONS "${SIGN_CODESIGN_OPTIONS}")
			message(FATAL_ERROR "Failed to sign:\n## Command line => codesign -s \"${IDENTITY}\" ${CODESIGN_OPTIONS} \"${SIGN_BINARY_PATH}\"\n## Error Code => ${CMD_RESULT}\n## Output => ${CMD_OUTPUT}")
		endif()
	endif()
endfunction()

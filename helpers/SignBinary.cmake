###############################################################################
### CMake script handling code signing of the binary

# Avoid multi inclusion of this file (cannot use include_guard as multiple copies of this file are included from multiple places)
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
	# Check for cmake minimum version
	cmake_minimum_required(VERSION 3.14)

	# Parse arguments
	cmake_parse_arguments(CUSB "" "BINARY_PATH;CODESIGN_IDENTITY" "SIGNTOOL_OPTIONS;SIGNTOOL_AGAIN_OPTIONS;CODESIGN_OPTIONS" ${ARGN})

	# Check required parameters validity
	if(NOT CUSB_BINARY_PATH)
		message(FATAL_ERROR "BINARY_PATH required")
	endif()
	if(NOT EXISTS "${CUSB_BINARY_PATH}")
		message(FATAL_ERROR "Specified binary does not exist: ${CUSB_BINARY_PATH}")
	endif()

	message(" - Signing ${CUSB_BINARY_PATH}")
	if(CMAKE_HOST_WIN32)
		execute_process(COMMAND signtool sign ${CUSB_SIGNTOOL_OPTIONS} "${CUSB_BINARY_PATH}" RESULT_VARIABLE CMD_RESULT OUTPUT_VARIABLE CMD_OUTPUT ERROR_VARIABLE CMD_OUTPUT)
		if(NOT ${CMD_RESULT} EQUAL 0)
			# Expand options lists
			string(REPLACE ";" " " SIGNTOOL_OPTIONS "${CUSB_SIGNTOOL_OPTIONS}")
			message(FATAL_ERROR "Failed to sign:\n## Command line => signtool sign ${SIGNTOOL_OPTIONS} \"${CUSB_BINARY_PATH}\"\n## Error Code => ${CMD_RESULT}\n## Output => ${CMD_OUTPUT}")
		endif()
		if(CUSB_SIGNTOOL_AGAIN_OPTIONS)
			execute_process(COMMAND signtool sign ${CUSB_SIGNTOOL_AGAIN_OPTIONS} "${CUSB_BINARY_PATH}" RESULT_VARIABLE CMD_RESULT OUTPUT_VARIABLE CMD_OUTPUT ERROR_VARIABLE CMD_OUTPUT)
			if(NOT ${CMD_RESULT} EQUAL 0)
				# Expand options lists
				string(REPLACE ";" " " SIGNTOOL_AGAIN_OPTIONS "${CUSB_SIGNTOOL_AGAIN_OPTIONS}")
				message(FATAL_ERROR "Failed to sign:\n## Command line => signtool sign ${SIGNTOOL_AGAIN_OPTIONS} \"${CUSB_BINARY_PATH}\"\n## Error Code => ${CMD_RESULT}\n## Output => ${CMD_OUTPUT}")
			endif()
		endif()
	elseif(CMAKE_HOST_APPLE)
		set(IDENTITY "-")
		if(CUSB_CODESIGN_IDENTITY)
			set(IDENTITY "${CUSB_CODESIGN_IDENTITY}")
		endif()
		execute_process(COMMAND codesign -s "${IDENTITY}" ${CUSB_CODESIGN_OPTIONS} "${CUSB_BINARY_PATH}" RESULT_VARIABLE CMD_RESULT OUTPUT_VARIABLE CMD_OUTPUT ERROR_VARIABLE CMD_OUTPUT)
		if(NOT ${CMD_RESULT} EQUAL 0)
			# Expand options lists
			string(REPLACE ";" " " CODESIGN_OPTIONS "${CUSB_CODESIGN_OPTIONS}")
			message(FATAL_ERROR "Failed to sign:\n## Command line => codesign -s \"${IDENTITY}\" ${CODESIGN_OPTIONS} \"${CUSB_BINARY_PATH}\"\n## Error Code => ${CMD_RESULT}\n## Output => ${CMD_OUTPUT}")
		endif()
	endif()
endfunction()

###############################################################################
### CMake script handling code signing of the binary

# Avoid multi inclusion of this file (cannot use include_guard as multiple copies of this file are included from multiple places)
if(CU_SIGN_BINARY_INCLUDED)
	return()
endif()
set(CU_SIGN_BINARY_INCLUDED true)

# Locations where macOS looks for the nested code of a bundle (relative to the content folder of the bundle)
set(CU_SIGN_BINARY_NESTED_CODE_LOCATIONS "Frameworks" "SharedFrameworks" "PlugIns" "Plug-ins" "XPCServices" "Helpers" "MacOS" "Library/Automator" "Library/Spotlight" "Library/LoginItems")
# Extensions of the nested bundles containing code (other bundle-like folders, such as dSYM, are data and are left untouched)
set(CU_SIGN_BINARY_CODE_BUNDLE_EXTENSIONS ".app" ".framework" ".xpc" ".appex" ".bundle" ".plugin" ".kext" ".systemextension")
# Magic numbers (as read from the first 4 bytes of the file) of thin and universal Mach-O files
set(CU_SIGN_BINARY_MACHO_MAGICS "feedface" "cefaedfe" "feedfacf" "cffaedfe" "cafebabe" "bebafeca" "cafebabf" "bfbafeca")

########
# Run codesign on a single path (macOS only)
# Mandatory parameters:
#  - "PATH <path>" => Path of the binary or bundle to sign
#  - "SIGN_COMMAND <signing command>" => signing command to use
#  - "IDENTITY <signing identity>" => code signing identity to use
# Optional parameters:
#  - "ENTITLEMENTS <entitlements file path>" => entitlements to embed in the signature
#  - "CODESIGN_OPTIONS <macOS codesign options>..." => list of options to pass to codesign
function(cu_private_codesign_path)
	cmake_parse_arguments(CUPCP "" "PATH;SIGN_COMMAND;IDENTITY;ENTITLEMENTS" "CODESIGN_OPTIONS" ${ARGN})

	set(ENTITLEMENTS_OPTIONS)
	if(CUPCP_ENTITLEMENTS)
		set(ENTITLEMENTS_OPTIONS --entitlements "${CUPCP_ENTITLEMENTS}")
	endif()

	execute_process(COMMAND ${CUPCP_SIGN_COMMAND} -s "${CUPCP_IDENTITY}" ${CUPCP_CODESIGN_OPTIONS} ${ENTITLEMENTS_OPTIONS} "${CUPCP_PATH}" RESULT_VARIABLE CMD_RESULT OUTPUT_VARIABLE CMD_OUTPUT ERROR_VARIABLE CMD_OUTPUT)
	if(NOT ${CMD_RESULT} EQUAL 0)
		# Expand options lists
		string(REPLACE ";" " " CODESIGN_OPTIONS "${CUPCP_CODESIGN_OPTIONS} ${ENTITLEMENTS_OPTIONS}")
		message(FATAL_ERROR "Failed to sign:\n## Command line => ${CUPCP_SIGN_COMMAND} -s \"${CUPCP_IDENTITY}\" ${CODESIGN_OPTIONS} \"${CUPCP_PATH}\"\n## Error Code => ${CMD_RESULT}\n## Output => ${CMD_OUTPUT}")
	endif()
endfunction()

########
# Sign the nested code found in a folder (and its sub-folders), nested bundles being signed inside-out (macOS only)
# Mandatory parameters:
#  - "FOLDER_PATH <path>" => Path of the folder to process
#  - "SIGN_COMMAND <signing command>" => signing command to use
#  - "IDENTITY <signing identity>" => code signing identity to use
# Optional parameters:
#  - "SKIP_PATH <path>" => Path of a file to leave untouched (the main executable of the parent bundle, which is signed along with the bundle)
#  - "CODESIGN_OPTIONS <macOS codesign options>..." => list of options to pass to codesign
function(cu_private_sign_nested_code_in_folder)
	cmake_parse_arguments(CUPSNCIF "" "FOLDER_PATH;SIGN_COMMAND;IDENTITY;SKIP_PATH" "CODESIGN_OPTIONS" ${ARGN})

	file(GLOB ENTRIES LIST_DIRECTORIES true "${CUPSNCIF_FOLDER_PATH}/*")
	foreach(ENTRY ${ENTRIES})
		# Symbolic links point to code that is signed through its real path
		if(IS_SYMLINK "${ENTRY}" OR "${ENTRY}" STREQUAL "${CUPSNCIF_SKIP_PATH}")
			continue()
		endif()

		if(IS_DIRECTORY "${ENTRY}")
			get_filename_component(ENTRY_EXTENSION "${ENTRY}" LAST_EXT)
			list(FIND CU_SIGN_BINARY_CODE_BUNDLE_EXTENSIONS "${ENTRY_EXTENSION}" EXTENSION_INDEX)
			if(NOT ${EXTENSION_INDEX} EQUAL -1)
				# Nested code bundle: sign its own nested code first, then the bundle itself
				cu_private_sign_nested_code(BUNDLE_PATH "${ENTRY}" SIGN_COMMAND ${CUPSNCIF_SIGN_COMMAND} IDENTITY "${CUPSNCIF_IDENTITY}" CODESIGN_OPTIONS ${CUPSNCIF_CODESIGN_OPTIONS})
				cu_private_codesign_path(PATH "${ENTRY}" SIGN_COMMAND ${CUPSNCIF_SIGN_COMMAND} IDENTITY "${CUPSNCIF_IDENTITY}" CODESIGN_OPTIONS ${CUPSNCIF_CODESIGN_OPTIONS})
			elseif(NOT IS_DIRECTORY "${ENTRY}/Contents" AND NOT IS_DIRECTORY "${ENTRY}/Versions")
				# Plain folder (not a data bundle): look for code inside it
				cu_private_sign_nested_code_in_folder(FOLDER_PATH "${ENTRY}" SIGN_COMMAND ${CUPSNCIF_SIGN_COMMAND} IDENTITY "${CUPSNCIF_IDENTITY}" CODESIGN_OPTIONS ${CUPSNCIF_CODESIGN_OPTIONS})
			endif()
		else()
			file(READ "${ENTRY}" FILE_MAGIC LIMIT 4 HEX)
			list(FIND CU_SIGN_BINARY_MACHO_MAGICS "${FILE_MAGIC}" MAGIC_INDEX)
			if(NOT ${MAGIC_INDEX} EQUAL -1)
				cu_private_codesign_path(PATH "${ENTRY}" SIGN_COMMAND ${CUPSNCIF_SIGN_COMMAND} IDENTITY "${CUPSNCIF_IDENTITY}" CODESIGN_OPTIONS ${CUPSNCIF_CODESIGN_OPTIONS})
			endif()
		endif()
	endforeach()
endfunction()

########
# Sign the nested code of a bundle (frameworks, plugins, helpers, ...), inside-out, so the bundle itself can then be signed without codesign's --deep option (macOS only)
# Nested code is signed without entitlements, as the entitlements of the bundle only apply to its main executable (codesign's --deep option would apply them to all nested code)
# Mandatory parameters:
#  - "BUNDLE_PATH <path>" => Path of the bundle
#  - "SIGN_COMMAND <signing command>" => signing command to use
#  - "IDENTITY <signing identity>" => code signing identity to use
# Optional parameters:
#  - "CODESIGN_OPTIONS <macOS codesign options>..." => list of options to pass to codesign
function(cu_private_sign_nested_code)
	cmake_parse_arguments(CUPSNC "" "BUNDLE_PATH;SIGN_COMMAND;IDENTITY" "CODESIGN_OPTIONS" ${ARGN})

	set(MAIN_EXECUTABLE_PATH "")
	if(IS_DIRECTORY "${CUPSNC_BUNDLE_PATH}/Contents")
		# Application-like bundle
		set(CONTENT_FOLDER "${CUPSNC_BUNDLE_PATH}/Contents")
		execute_process(COMMAND /usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "${CONTENT_FOLDER}/Info.plist" OUTPUT_VARIABLE MAIN_EXECUTABLE_NAME OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
		if(MAIN_EXECUTABLE_NAME)
			set(MAIN_EXECUTABLE_PATH "${CONTENT_FOLDER}/MacOS/${MAIN_EXECUTABLE_NAME}")
		endif()
	elseif(IS_DIRECTORY "${CUPSNC_BUNDLE_PATH}/Versions/Current")
		# Framework bundle
		set(CONTENT_FOLDER "${CUPSNC_BUNDLE_PATH}/Versions/Current")
	else()
		return()
	endif()

	foreach(LOCATION ${CU_SIGN_BINARY_NESTED_CODE_LOCATIONS})
		if(IS_DIRECTORY "${CONTENT_FOLDER}/${LOCATION}")
			cu_private_sign_nested_code_in_folder(FOLDER_PATH "${CONTENT_FOLDER}/${LOCATION}" SIGN_COMMAND ${CUPSNC_SIGN_COMMAND} IDENTITY "${CUPSNC_IDENTITY}" SKIP_PATH "${MAIN_EXECUTABLE_PATH}" CODESIGN_OPTIONS ${CUPSNC_CODESIGN_OPTIONS})
		endif()
	endforeach()
endfunction()

########
# Code sign a binary
# Mandatory parameters:
#  - "BINARY_PATH <binary path>" => Path of the binary to sign
#  - "SIGN_COMMAND <signing command>" => signing command to use
# Optional parameters:
#  - "SIGNTOOL_OPTIONS <windows signtool options>..." => list of options to pass to windows signtool utility (signing will be done on all runtime dependencies if this is specified)
#  - "SIGNTOOL_AGAIN_OPTIONS <windows signtool options>..." => list of options to pass to a secondary signtool call (to add another signature)
#  - "CODESIGN_OPTIONS <macOS codesign options>..." => list of options to pass to macOS codesign utility (signing will be done on all runtime dependencies if this is specified)
#  - "CODESIGN_IDENTITY <signing identity>" => code signing identity to be used by macOS codesign utility (autodetect will be used if not specified)
#  - "CODESIGN_ENTITLEMENTS <entitlements file path>" => entitlements to embed in the signature of the binary by macOS codesign utility (not applied to the nested code of a bundle)
# On macOS, when BINARY_PATH is a bundle, its nested code is signed first (inside-out) with the same identity and options.
function(cu_sign_binary)
	# Check for cmake minimum version
	cmake_minimum_required(VERSION 3.14)

	# Parse arguments
	cmake_parse_arguments(CUSB "" "BINARY_PATH;SIGN_COMMAND;CODESIGN_IDENTITY;CODESIGN_ENTITLEMENTS" "SIGNTOOL_OPTIONS;SIGNTOOL_AGAIN_OPTIONS;CODESIGN_OPTIONS" ${ARGN})

	# Check required parameters validity
	if(NOT CUSB_BINARY_PATH)
		message(FATAL_ERROR "BINARY_PATH required")
	endif()
	if(NOT EXISTS "${CUSB_BINARY_PATH}")
		message(FATAL_ERROR "Specified binary does not exist: ${CUSB_BINARY_PATH}")
	endif()
	if(NOT CUSB_SIGN_COMMAND)
		message(FATAL_ERROR "SIGN_COMMAND required")
	endif()

	message(" - Signing ${CUSB_BINARY_PATH}")
	if(CMAKE_HOST_WIN32)
		execute_process(COMMAND ${CUSB_SIGN_COMMAND} ${CUSB_SIGNTOOL_OPTIONS} "${CUSB_BINARY_PATH}" RESULT_VARIABLE CMD_RESULT OUTPUT_VARIABLE CMD_OUTPUT ERROR_VARIABLE CMD_OUTPUT)
		if(NOT ${CMD_RESULT} EQUAL 0)
			# Expand options lists
			string(REPLACE ";" " " SIGNTOOL_OPTIONS "${CUSB_SIGNTOOL_OPTIONS}")
			message(FATAL_ERROR "Failed to sign:\n## Command line => ${CUSB_SIGN_COMMAND} ${SIGNTOOL_OPTIONS} \"${CUSB_BINARY_PATH}\"\n## Error Code => ${CMD_RESULT}\n## Output => ${CMD_OUTPUT}")
		endif()
		if(CUSB_SIGNTOOL_AGAIN_OPTIONS)
			execute_process(COMMAND ${CUSB_SIGN_COMMAND} ${CUSB_SIGNTOOL_AGAIN_OPTIONS} "${CUSB_BINARY_PATH}" RESULT_VARIABLE CMD_RESULT OUTPUT_VARIABLE CMD_OUTPUT ERROR_VARIABLE CMD_OUTPUT)
			if(NOT ${CMD_RESULT} EQUAL 0)
				# Expand options lists
				string(REPLACE ";" " " SIGNTOOL_AGAIN_OPTIONS "${CUSB_SIGNTOOL_AGAIN_OPTIONS}")
				message(FATAL_ERROR "Failed to sign:\n## Command line => ${CUSB_SIGN_COMMAND} ${SIGNTOOL_AGAIN_OPTIONS} \"${CUSB_BINARY_PATH}\"\n## Error Code => ${CMD_RESULT}\n## Output => ${CMD_OUTPUT}")
			endif()
		endif()
	elseif(CMAKE_HOST_APPLE)
		set(IDENTITY "-")
		if(CUSB_CODESIGN_IDENTITY)
			set(IDENTITY "${CUSB_CODESIGN_IDENTITY}")
		endif()
		if(IS_DIRECTORY "${CUSB_BINARY_PATH}")
			cu_private_sign_nested_code(BUNDLE_PATH "${CUSB_BINARY_PATH}" SIGN_COMMAND ${CUSB_SIGN_COMMAND} IDENTITY "${IDENTITY}" CODESIGN_OPTIONS ${CUSB_CODESIGN_OPTIONS})
		endif()
		cu_private_codesign_path(PATH "${CUSB_BINARY_PATH}" SIGN_COMMAND ${CUSB_SIGN_COMMAND} IDENTITY "${IDENTITY}" ENTITLEMENTS "${CUSB_CODESIGN_ENTITLEMENTS}" CODESIGN_OPTIONS ${CUSB_CODESIGN_OPTIONS})
	endif()
endfunction()

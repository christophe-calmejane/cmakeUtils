###############################################################################
### CMake script handling deployment of the runtime dependencies of a binary

# Avoid multi inclusion of this file (cannot use include_guard as multiple copies of this file are included from multiple places)
if(CU_DEPLOY_BINARY_DEPENDENCIES_INCLUDED)
	return()
endif()
set(CU_DEPLOY_BINARY_DEPENDENCIES_INCLUDED true)

# Some global variables
set(CU_DEPLOY_BINARY_DEPENDENCIES_FOLDER "${CMAKE_CURRENT_LIST_DIR}")
include("${CU_DEPLOY_BINARY_DEPENDENCIES_FOLDER}/IsNewerThan.cmake")

# Due to a bug in some CMake versions, force CMP0057
cmake_policy(PUSH)
cmake_policy(SET CMP0057 NEW) # Support new IN_LIST if() operator

##################################
# Internal function
function(cu_private_get_binary_dependencies BINARY_PATH LIBRARY_DEPENDENCIES_OUTPUT)
	# Get target binary name and folder
	get_filename_component(BINARY_NAME ${BINARY_PATH} NAME)
	get_filename_component(BINARY_FOLDER ${BINARY_PATH} DIRECTORY)

	if(CMAKE_HOST_WIN32)
		set(DUMPBIN_COMMAND "dumpbin.exe")

		# Get binary dependencies
		execute_process(COMMAND ${DUMPBIN_COMMAND} /DEPENDENTS "${BINARY_NAME}" WORKING_DIRECTORY "${BINARY_FOLDER}" RESULT_VARIABLE CMD_RESULT OUTPUT_VARIABLE CMD_OUTPUT ERROR_VARIABLE CMD_OUTPUT)
		if(NOT ${CMD_RESULT} EQUAL 0)
			message(FATAL_ERROR "Failed to get binary dependencies:\n## Command line => ${DUMPBIN_COMMAND} /DEPENDENTS \"${BINARY_NAME}\"\n## Error Code => ${CMD_RESULT}\n## Output => ${CMD_OUTPUT}")
		endif()

		# Match with the leading 4 spaces so we ignore "Dump of file xxx.dll" that is outputed by dumpbin
		string(REGEX MATCHALL "    [^ .]+\\.[dD][lL][lL]" DEPENDENCIES_LIST ${CMD_OUTPUT})
		foreach(DEPENDENCY ${DEPENDENCIES_LIST})
			# Remove the leading 4 spaces that we matched
			string(REGEX REPLACE "^    " "" DEPENDENCY "${DEPENDENCY}")
			# Append to list
			list(APPEND ${LIBRARY_DEPENDENCIES_OUTPUT} "${DEPENDENCY}")
		endforeach()

	elseif(CMAKE_HOST_APPLE)
		set(OTOOL_COMMAND "otool")

		# Get binary dependencies
		execute_process(COMMAND ${OTOOL_COMMAND} -L "${BINARY_NAME}" WORKING_DIRECTORY "${BINARY_FOLDER}" RESULT_VARIABLE CMD_RESULT OUTPUT_VARIABLE CMD_OUTPUT ERROR_VARIABLE CMD_OUTPUT)
		if(NOT ${CMD_RESULT} EQUAL 0)
			message(FATAL_ERROR "Failed to get binary dependencies:\n## Command line => ${OTOOL_COMMAND} -L \"${BINARY_NAME}\"\n## Error Code => ${CMD_RESULT}\n## Output => ${CMD_OUTPUT}")
		endif()

		# Since CMake regex does not support lookaround and capture groups do not return all results in a MATCHALL, we split the output result in lines, then match a single expression for each line
		string(REGEX MATCHALL "[^\n]+" SPLIT_LINES ${CMD_OUTPUT})
		foreach(LINE ${SPLIT_LINES})
			string(REGEX MATCH "@rpath/([^\n]+\\.dylib)" MATCH_RESULT ${LINE})
			if(CMAKE_MATCH_COUNT EQUAL 1)
				# Append to list
				list(APPEND ${LIBRARY_DEPENDENCIES_OUTPUT} "${CMAKE_MATCH_1}")
			endif()
		endforeach()

	else()
		message(FATAL_ERROR "TODO")
	endif()

	set(${LIBRARY_DEPENDENCIES_OUTPUT} ${${LIBRARY_DEPENDENCIES_OUTPUT}} PARENT_SCOPE)
endfunction()

##################################
# Internal function
function(cu_private_get_binary_dependencies_to_copy BINARY_PATH DESTINATION_FOLDER)
	# Get target binary name and folder
	get_filename_component(BINARY_NAME "${BINARY_PATH}" NAME)
	get_filename_component(BINARY_FOLDER "${BINARY_PATH}" DIRECTORY)

	# Check if already visited
	if("${BINARY_NAME}" IN_LIST VISITED_DEPENDENCIES)
		# message(STATUS "Already visited dependency ${BINARY_NAME}")
		return()
	endif()
	
	# Add to visited dependencies
	list(APPEND VISITED_DEPENDENCIES "${BINARY_NAME}")
	
	# message(STATUS "Binary Name: ${BINARY_NAME}")
	# message(STATUS "Binary Folder: ${BINARY_FOLDER}")

	# Get binary dependencies
	cu_private_get_binary_dependencies("${BINARY_PATH}" DEPENDENCIES_LIST)

	if(CMAKE_HOST_WIN32)
		set(VCPKG_INSTALLED_RUNTIME_FOLDER "bin")
	elseif(CMAKE_HOST_APPLE)
		set(VCPKG_INSTALLED_RUNTIME_FOLDER "lib")
	else()
		message(FATAL_ERROR "TODO")
	endif()

	foreach(DEPENDENCY ${DEPENDENCIES_LIST})
		# First check if we can find this binary in destination folder
		if(EXISTS "${DESTINATION_FOLDER}/${DEPENDENCY}")
			set(DEPENDENCY_PATH "${DESTINATION_FOLDER}/${DEPENDENCY}")
			# message(STATUS "Process already deployed dependency ${DEPENDENCY}...")

		# Then check if we can find this binary in vcpkg installed directory
		elseif(EXISTS "${CUDRB_INSTALLED_DIR}/${VCPKG_INSTALLED_RUNTIME_FOLDER}/${DEPENDENCY}")
			set(DEPENDENCY_PATH "${CUDRB_INSTALLED_DIR}/${VCPKG_INSTALLED_RUNTIME_FOLDER}/${DEPENDENCY}")
			# Add to the list of files to copy
			if(NOT "${DEPENDENCY_PATH}" IN_LIST BINARY_DEPENDENCIES)
				list(APPEND BINARY_DEPENDENCIES "${DEPENDENCY_PATH}")
			endif()
			# message(STATUS "Process vcpkg dependency ${DEPENDENCY}...")
			
		# Else skip it
		else()
			# message(STATUS "Dependency ${DEPENDENCY} not found, skipping...")
			continue()
		endif()

		# Recursively process this binary
		cu_private_get_binary_dependencies_to_copy("${DEPENDENCY_PATH}" "${DESTINATION_FOLDER}")
	endforeach()

	set(VISITED_DEPENDENCIES ${VISITED_DEPENDENCIES} PARENT_SCOPE)
	set(BINARY_DEPENDENCIES ${BINARY_DEPENDENCIES} PARENT_SCOPE)
endfunction()

########
# Deploy all runtime dependencies a binary depends on
# Mandatory parameters:
#  - "BINARY_PATH <binary path>" => Path of the binary to deploy
#  - "INSTALLED_DIR <vcpkg installed directory>" => vcpkg "installed" root folder (right after TRIPLET, postfixing "debug" if the target is built in DEBUG)
#  - "TARGET_DIR <target copy directory>" => directory where to copy runtime dependencies
# Optional parameters:
#  - "COPIED_FILES_VAR <list of copied files>" => variable receiving the list of copied files (files are appended to this list variable, if it's specified)
function(cu_deploy_runtime_binary)
	# Check for cmake minimum version
	cmake_minimum_required(VERSION 3.15) # FOLLOW_SYMLINK_CHAIN added in cmake 3.15

	# Parse arguments
	cmake_parse_arguments(CUDRB "" "BINARY_PATH;INSTALLED_DIR;TARGET_DIR;COPIED_FILES_VAR" "" ${ARGN})

	# Check required parameters validity
	if(NOT CUDRB_BINARY_PATH)
		message(FATAL_ERROR "BINARY_PATH required")
	endif()
	if(NOT EXISTS "${CUDRB_BINARY_PATH}")
		message(FATAL_ERROR "Specified binary does not exist: ${CUDRB_BINARY_PATH}")
	endif()

	if(NOT CUDRB_INSTALLED_DIR)
		message(FATAL_ERROR "INSTALLED_DIR required")
	endif()
	if(NOT EXISTS "${CUDRB_INSTALLED_DIR}")
		message(FATAL_ERROR "Specified vcpkg installed directory does not exist: ${CUDRB_INSTALLED_DIR}")
	endif()

	if(NOT CUDRB_TARGET_DIR)
		message(FATAL_ERROR "TARGET_DIR required")
	endif()
	if(NOT EXISTS "${CUDRB_TARGET_DIR}")
		message(FATAL_ERROR "Specified target directory does not exist: ${CUDRB_TARGET_DIR}")
	endif()

	# Recursively get dependencies
	set(VISITED_DEPENDENCIES)
	set(BINARY_DEPENDENCIES)
	cu_private_get_binary_dependencies_to_copy("${CUDRB_BINARY_PATH}" "${CUDRB_TARGET_DIR}")

	foreach(DEP ${BINARY_DEPENDENCIES})
		# Build destination file full path
		get_filename_component(BINARY_NAME ${DEP} NAME)
		set(DEST_FILE_PATH "${CUDRB_TARGET_DIR}/${BINARY_NAME}")

		# Check if we need to copy the file
		cu_is_newer_than("${DEP}" "${DEST_FILE_PATH}" IS_NEWER_THAN_RESULT)
		if(${IS_NEWER_THAN_RESULT})
			# Copy the file
			message(" - Copying transitive dependency ${DEP} => ${CUDRB_TARGET_DIR}")
			file(COPY "${DEP}" DESTINATION "${CUDRB_TARGET_DIR}" FOLLOW_SYMLINK_CHAIN)

			# Add to the list of copied files
			if(CUDRB_COPIED_FILES_VAR)
				list(APPEND ${CUDRB_COPIED_FILES_VAR} "${DEST_FILE_PATH}")
			endif()
		endif()
	endforeach()

	if(CUDRB_COPIED_FILES_VAR)
		set(${CUDRB_COPIED_FILES_VAR} ${${CUDRB_COPIED_FILES_VAR}} PARENT_SCOPE)
	endif()
endfunction()

cmake_policy(POP)

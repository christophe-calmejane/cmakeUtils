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
include("${CU_DEPLOY_BINARY_DEPENDENCIES_FOLDER}/GetBinaryDynamicDependencies.cmake")

# Due to a bug in some CMake versions, force CMP0057
cmake_policy(PUSH)
cmake_policy(SET CMP0057 NEW) # Support new IN_LIST if() operator

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
	set(DEPENDENCIES_LIST "")
	cu_get_binary_dynamic_dependencies(BINARY_PATH "${BINARY_PATH}" DEP_LIST_OUTPUT DEPENDENCIES_LIST)

	foreach(DEPENDENCY ${DEPENDENCIES_LIST})
		set(IS_FOUND FALSE)
		# First check if we can find this binary in destination folder
		if(EXISTS "${DESTINATION_FOLDER}/${DEPENDENCY}")
			set(IS_FOUND TRUE)
			set(DEPENDENCY_PATH "${DESTINATION_FOLDER}/${DEPENDENCY}")
			# message(STATUS "Process already deployed dependency ${DEPENDENCY}...")

		else()
			# Then check if we can find this binary in any of the provided directories
			foreach(SEARCH_DIR ${CUDRB_SEARCH_DIRS})
				if(EXISTS "${SEARCH_DIR}/${DEPENDENCY}")
					set(IS_FOUND TRUE)
					set(DEPENDENCY_PATH "${SEARCH_DIR}/${DEPENDENCY}")
					# Add to the list of files to copy
					if(NOT "${DEPENDENCY_PATH}" IN_LIST BINARY_DEPENDENCIES)
						list(APPEND BINARY_DEPENDENCIES "${DEPENDENCY_PATH}")
					endif()
					# message(STATUS "Process dependency ${DEPENDENCY} from folder ${SEARCH_DIR}...")
				endif()
			endforeach()
		endif()

		if(${IS_FOUND})
			# Recursively process this binary
			cu_private_get_binary_dependencies_to_copy("${DEPENDENCY_PATH}" "${DESTINATION_FOLDER}")
		else()
			# message(STATUS "Dependency ${DEPENDENCY} not found, skipping...")
			continue()
		endif()
	endforeach()

	set(VISITED_DEPENDENCIES ${VISITED_DEPENDENCIES} PARENT_SCOPE)
	set(BINARY_DEPENDENCIES ${BINARY_DEPENDENCIES} PARENT_SCOPE)
endfunction()

########
# Deploy all runtime dependencies a binary depends on
# Mandatory parameters:
#  - "BINARY_PATH <binary path>" => Path of the binary to deploy
#  - "TARGET_DIR <target copy directory>" => directory where to copy runtime dependencies
# Optional parameters:
#  - "SEARCH_DIRS <folder> ..." => List of folders to search for dependencies in
#  - "COPIED_FILES_VAR <list of copied files>" => variable receiving the list of copied files (files are appended to this list variable, if it's specified)
function(cu_deploy_runtime_binary)
	# Check for cmake minimum version
	cmake_minimum_required(VERSION 3.15) # FOLLOW_SYMLINK_CHAIN added in cmake 3.15

	# Parse arguments
	cmake_parse_arguments(CUDRB "" "BINARY_PATH;TARGET_DIR;COPIED_FILES_VAR" "SEARCH_DIRS" ${ARGN})

	# Check required parameters validity
	if(NOT CUDRB_BINARY_PATH)
		message(FATAL_ERROR "BINARY_PATH required")
	endif()
	if(NOT EXISTS "${CUDRB_BINARY_PATH}")
		message(FATAL_ERROR "Specified binary does not exist: ${CUDRB_BINARY_PATH}")
	endif()

	if(CUDRB_SEARCH_DIRS)
		foreach(SEARCH_DIR ${CUDRB_SEARCH_DIRS})
			if(NOT EXISTS "${SEARCH_DIR}")
				message(FATAL_ERROR "Specified search directory does not exist: ${SEARCH_DIR}")
			endif()
		endforeach()
	endif()

	if(NOT CUDRB_TARGET_DIR)
		message(FATAL_ERROR "TARGET_DIR required")
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

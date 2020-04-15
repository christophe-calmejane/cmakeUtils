###############################################################################
### CMake script handling deployment of the runtime dependencies of a binary

# Avoid multi inclusion of this file
if(CU_DEPLOY_BINARY_DEPENDENCIES_INCLUDED)
	return()
endif()
set(CU_DEPLOY_BINARY_DEPENDENCIES_INCLUDED true)

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
		execute_process(COMMAND ${DUMPBIN_COMMAND} /DEPENDENTS ${BINARY_NAME} WORKING_DIRECTORY ${BINARY_FOLDER} RESULT_VARIABLE CMD_RESULT OUTPUT_VARIABLE CMD_OUTPUT ERROR_VARIABLE CMD_OUTPUT)
		if(NOT ${CMD_RESULT} EQUAL 0)
			message(FATAL_ERROR "Failed to get binary dependencies: ${CMD_RESULT}")
		endif()

		# Match with the leading 4 spaces so we ignore "Dump of file xxx.dll" that is outputed by dumpbin
		string(REGEX MATCHALL "    [^ .]+\\.[dD][lL][lL]" DEPENDENCIES_LIST ${CMD_OUTPUT})
		foreach(DEPENDENCY ${DEPENDENCIES_LIST})
			# Remove the leading 4 spaces that we matched
			string(REGEX REPLACE "^    " "" DEPENDENCY "${DEPENDENCY}")
			# Append to list
			list(APPEND ${LIBRARY_DEPENDENCIES_OUTPUT} "${DEPENDENCY}")
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
	get_filename_component(BINARY_NAME ${BINARY_PATH} NAME)
	get_filename_component(BINARY_FOLDER ${BINARY_PATH} DIRECTORY)

	# Check if already visited
	if(${BINARY_NAME} IN_LIST VISITED_DEPENDENCIES)
		message(STATUS "Already visited dependency ${BINARY_NAME}")
		return()
	endif()
	
	# Add to visited dependencies
	list(APPEND VISITED_DEPENDENCIES ${BINARY_NAME})
	
	# message(STATUS "Binary Name: ${BINARY_NAME}")
	# message(STATUS "Binary Folder: ${BINARY_FOLDER}")

	# Get binary dependencies
	cu_private_get_binary_dependencies("${BINARY_PATH}" DEPENDENCIES_LIST)

	foreach(DEPENDENCY ${DEPENDENCIES_LIST})
		# First check if we can find this binary in destination folder
		if(EXISTS "${DESTINATION_FOLDER}/${DEPENDENCY}")
			set(DEPENDENCY_PATH "${DESTINATION_FOLDER}/${DEPENDENCY}")
			# message(STATUS "Process already deployed dependency ${DEPENDENCY}...")

		# Then check if we can find this binary in vcpkg installed directory
		elseif(EXISTS "${DEPLOY_INSTALLED_DIR}/bin/${DEPENDENCY}")
			set(DEPENDENCY_PATH "${DEPLOY_INSTALLED_DIR}/bin/${DEPENDENCY}")
			# Add to the list of files to copy
			if(NOT ${DEPENDENCY} IN_LIST BINARY_DEPENDENCIES)
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
#  - BINARY_PATH <binary path>
#  - INSTALLED_DIR <vcpkg installed directory>
#  - TARGET_DIR <target copy directory>
function(cu_deploy_runtime_binary)
	# Parse arguments
	cmake_parse_arguments(DEPLOY "" "BINARY_PATH;INSTALLED_DIR;TARGET_DIR" "" ${ARGN})

	# Check required parameters validity
	if(NOT DEPLOY_BINARY_PATH)
		message(FATAL_ERROR "BINARY_PATH required")
	endif()
	if(NOT EXISTS "${DEPLOY_BINARY_PATH}")
		message(FATAL_ERROR "Specified binary does not exist: ${DEPLOY_BINARY_PATH}")
	endif()

	if(NOT DEPLOY_INSTALLED_DIR)
		message(FATAL_ERROR "INSTALLED_DIR required")
	endif()
	if(NOT EXISTS "${DEPLOY_INSTALLED_DIR}")
		message(FATAL_ERROR "Specified vcpkg installed directory does not exist: ${DEPLOY_INSTALLED_DIR}")
	endif()

	if(NOT DEPLOY_TARGET_DIR)
		message(FATAL_ERROR "TARGET_DIR required")
	endif()
	if(NOT EXISTS "${DEPLOY_TARGET_DIR}")
		message(FATAL_ERROR "Specified target directory does not exist: ${DEPLOY_TARGET_DIR}")
	endif()

	# Recursively get dependencies
	set(VISITED_DEPENDENCIES)
	set(BINARY_DEPENDENCIES)
	cu_private_get_binary_dependencies_to_copy("${DEPLOY_BINARY_PATH}" "${DEPLOY_TARGET_DIR}")

	foreach(DEP ${BINARY_DEPENDENCIES})
		message(" - Copying ${DEP} => ${DEPLOY_TARGET_DIR}")
		file(COPY "${DEP}" DESTINATION "${DEPLOY_TARGET_DIR}")
	endforeach()

endfunction()

cmake_policy(POP)

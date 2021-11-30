###############################################################################
### CMake script handling deployment of the runtime dependencies of a target

# Avoid multi inclusion of this file (cannot use include_guard as multiple copies of this file are included from multiple places)
if(CU_TARGET_SETUP_DEPLOY_INCLUDED)
	return()
endif()
set(CU_TARGET_SETUP_DEPLOY_INCLUDED true)

# Some global variables
set(CU_TARGET_SETUP_DEPLOY_FOLDER "${CMAKE_CURRENT_LIST_DIR}")

##################################
# Internal function
function(cu_private_target_list_link_libraries TARGET_NAME LIBRARY_DEPENDENCIES_OUTPUT QT_DEPENDENCIES_OUTPUT)
	# Check if already visited
	if(${TARGET_NAME} IN_LIST VISITED_DEPENDENCIES)
		return()
	endif()
	
	# Add to visited dependencies
	list(APPEND VISITED_DEPENDENCIES ${TARGET_NAME})
	
	# Skip interface libraries
	get_target_property(_TARGET_TYPE ${TARGET_NAME} TYPE)
	if(_TARGET_TYPE STREQUAL "INTERFACE_LIBRARY")
		return()
	endif()
	# Generate list of libraries on which the target depends
	list(APPEND _LIBRARIES "")
	get_target_property(_LINK_LIBRARIES ${TARGET_NAME} LINK_LIBRARIES)
	if(_LINK_LIBRARIES)
		list(APPEND _LIBRARIES ${_LINK_LIBRARIES})
	endif()
	get_target_property(_INTERFACE_LINK_LIBRARIES ${TARGET_NAME} INTERFACE_LINK_LIBRARIES)
	if(_INTERFACE_LINK_LIBRARIES)
		list(APPEND _LIBRARIES ${_INTERFACE_LINK_LIBRARIES})
	endif()
	if(_LIBRARIES)
		# Remove duplicates and the target itself
		list(REMOVE_DUPLICATES _LIBRARIES)
		list(REMOVE_ITEM _LIBRARIES ${TARGET_NAME})
		# Check dependencies
		foreach(_LIBRARY ${_LIBRARIES})
			if(${_LIBRARY} MATCHES "Qt5::")
				list(APPEND ${QT_DEPENDENCIES_OUTPUT} ${TARGET_NAME})
				continue()
			endif()
			if(TARGET ${_LIBRARY})
				get_target_property(_LIBRARY_TYPE ${_LIBRARY} TYPE)
				if(_LIBRARY_TYPE STREQUAL "SHARED_LIBRARY")
					list(APPEND ${LIBRARY_DEPENDENCIES_OUTPUT} ${_LIBRARY})
				endif()
				cu_private_target_list_link_libraries(${_LIBRARY} ${LIBRARY_DEPENDENCIES_OUTPUT} ${QT_DEPENDENCIES_OUTPUT})
			endif()
		endforeach()
	endif()
	set(${LIBRARY_DEPENDENCIES_OUTPUT} ${${LIBRARY_DEPENDENCIES_OUTPUT}} PARENT_SCOPE)
	set(${QT_DEPENDENCIES_OUTPUT} ${${QT_DEPENDENCIES_OUTPUT}} PARENT_SCOPE)
	set(VISITED_DEPENDENCIES ${VISITED_DEPENDENCIES} PARENT_SCOPE)
endfunction()

##################################
# Deploy all runtime dependencies the specified target depends on
# Optional parameters:
#  - "INSTALL" => flag instructing the script to also install-deploy the runtime dependencies
#  - "SIGN" => flag instructing the script to code sign the runtime dependencies
#  - "QML_DIR <path>" => override default QML_DIR folder
#  - "INSTALL_DESTINATION <relative path>" => Relative path that was given to the DESTINATION option of the install() rule for TARGET_NAME (defaults to 'bin')
#  - "SIGNTOOL_OPTIONS <windows signtool options>..." => list of options to pass to windows signtool utility (signing will be done on all runtime dependencies if this is specified)
#  - "SIGNTOOL_AGAIN_OPTIONS <windows signtool options>..." => list of options to pass to a secondary signtool call (to add another signature)
#  - "CODESIGN_OPTIONS <macOS codesign options>..." => list of options to pass to macOS codesign utility (signing will be done on all runtime dependencies if this is specified)
#  - "CODESIGN_IDENTITY <signing identity>" => code signing identity to be used by macOS codesign utility (autodetect will be used if not specified)
#  - "DEP_SEARCH_DIRS <path>..." => list of additional directories to search for dependencies
function(cu_deploy_runtime_target TARGET_NAME)
	# Check for cmake minimum version
	cmake_minimum_required(VERSION 3.14)

	set(VISITED_DEPENDENCIES)
	cu_private_target_list_link_libraries(${TARGET_NAME} _LIBRARY_DEPENDENCIES_OUTPUT _QT_DEPENDENCIES_OUTPUT)

	get_target_property(_IS_BUNDLE ${TARGET_NAME} MACOSX_BUNDLE)

	# We generate a cmake script that will contain all the commands
	set(DEPLOY_SCRIPT ${CMAKE_CURRENT_BINARY_DIR}/cu_deploy_runtime_$<CONFIG>_${TARGET_NAME}.cmake)

	cmake_parse_arguments(DEPLOY "INSTALL;SIGN" "QML_DIR;INSTALL_DESTINATION;CODESIGN_IDENTITY" "SIGNTOOL_OPTIONS;SIGNTOOL_AGAIN_OPTIONS;CODESIGN_OPTIONS;DEP_SEARCH_DIRS" ${ARGN})

	if (NOT DEPLOY_INSTALL_RELATIVE_PATH)
		set(DEPLOY_INSTALL_RELATIVE_PATH "bin")
	endif()

	# Init code for both easy-debug and install scripts
	string(CONCAT INIT_CODE
		"include(\"${CU_TARGET_SETUP_DEPLOY_FOLDER}/IsNewerThan.cmake\")\n"
		"include(\"${CU_TARGET_SETUP_DEPLOY_FOLDER}/DeployBinaryDependencies.cmake\")\n"
		"include(\"${CU_TARGET_SETUP_DEPLOY_FOLDER}/SignBinary.cmake\")\n"
		"include(\"${CU_TARGET_SETUP_DEPLOY_FOLDER}/GetBinaryRuntimePath.cmake\")\n"
		"set(BINARIES_TO_SIGN)\n"
		"set(COPIED_FILES)\n"
		"set(DEPENDENCIES_SEARCH_DIRS)\n"
		"set(DEPLOY_LOCK_FILE \"${CMAKE_BINARY_DIR}/deploy.lock\")\n"
		"file(LOCK \"\${DEPLOY_LOCK_FILE}\" GUARD PROCESS TIMEOUT 90 RESULT_VARIABLE lock_result)\n"
		"if(NOT \${lock_result} EQUAL 0)\n"
		"\tmessage(FATAL_ERROR \"Failed to get lock '\${DEPLOY_LOCK_FILE}' within time (\${lock_result}). Try to remove the file if previous build didn't complete correctly.\")\n"
		"endif()\n"
	)

	if(DEPLOY_DEP_SEARCH_DIRS)
		foreach(DEP_SEARCH_DIR ${DEPLOY_DEP_SEARCH_DIRS})
			string(APPEND INIT_CODE
				"list(APPEND DEPENDENCIES_SEARCH_DIRS \"${DEP_SEARCH_DIR}\")\n"
			)
		endforeach()
	endif()

	# Workaround for https://gitlab.kitware.com/cmake/cmake/-/issues/20938
	if (CMAKE_VERSION STRLESS "3.666") # TODO: Change version to the one that fixes the bug
		if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
			# Contrary to 'install', EFFECTIVE_PLATFORM_NAME is not set by cmake when the script is called, so use the same backup that's defined in install scripts
			string(APPEND INIT_CODE
				"if(NOT EFFECTIVE_PLATFORM_NAME)\n"
				"\tif(NOT \"\$ENV{EFFECTIVE_PLATFORM_NAME}\" STREQUAL \"\")\n"
				"\t\tset(EFFECTIVE_PLATFORM_NAME \"\$ENV{EFFECTIVE_PLATFORM_NAME}\")\n"
				"\tendif()\n"
				"\tif(NOT EFFECTIVE_PLATFORM_NAME)\n"
				"\t\tset(EFFECTIVE_PLATFORM_NAME -iphoneos)\n"
				"\tendif()\n"
				"endif()\n"
			)
		endif()
	endif()

	string(APPEND DEPLOY_SCRIPT_CONTENT
		"message(STATUS \"Deploying runtime dependencies for ${TARGET_NAME}...\")\n"
		"${INIT_CODE}"
		"cu_get_binary_runtime_path(BINARY_PATH \"$<TARGET_FILE:${TARGET_NAME}>\" RPATH_OUTPUT RUNTIME_FOLDER)\n"
	)

	if(DEPLOY_INSTALL)
		# WARNING: install(CODE) does not support multiple parameters, so we have to issue multiple commands
		install(CODE
			"\n${INIT_CODE}"
		)
		string(APPEND INSTALL_SCRIPT_CONTENT
			"if(NOT DEFINED CMAKE_INSTALL_PREFIX)\n"
			"\tset(CMAKE_INSTALL_PREFIX \"${CMAKE_INSTALL_PREFIX}\")\n"
			"endif()\n"
			"get_filename_component(INSTALL_FOLDER \"\${CMAKE_INSTALL_PREFIX}/${DEPLOY_INSTALL_RELATIVE_PATH}\" ABSOLUTE BASE_DIR \"${CMAKE_BINARY_DIR}\")\n"
			"cu_get_binary_runtime_path(BINARY_PATH \"$<TARGET_FILE:${TARGET_NAME}>\" RPATH_OUTPUT RUNTIME_FOLDER RELOCATION_DIR \"\${INSTALL_FOLDER}\")\n"
		)
		install(CODE
			"\n${INSTALL_SCRIPT_CONTENT}"
		)
	endif()

	# Handle non-Qt dependencies
	if(_LIBRARY_DEPENDENCIES_OUTPUT)
		list(REMOVE_DUPLICATES _LIBRARY_DEPENDENCIES_OUTPUT)
		# Process each runtime dependency
		foreach(_LIBRARY ${_LIBRARY_DEPENDENCIES_OUTPUT})
			# Copy dynamic library to the runtime folder (but only if file is newer, which includes if they are identical) based on RUNTIME_FOLDER variable that is different for easy-debug and install rules
			string(CONCAT COPY_TARGET_FILE_CODE
				"list(APPEND DEPENDENCIES_SEARCH_DIRS \"$<TARGET_FILE_DIR:${_LIBRARY}>\")\n"
				"cu_is_newer_than(\"$<TARGET_FILE:${_LIBRARY}>\" \"\${RUNTIME_FOLDER}/$<TARGET_FILE_NAME:${_LIBRARY}>\" IS_NEWER_THAN_RESULT)\n"
				"if(\${IS_NEWER_THAN_RESULT})\n"
				"\tmessage(\" - Copying target file $<TARGET_FILE:${_LIBRARY}> => \${RUNTIME_FOLDER}\")\n"
				"\tfile(COPY \"$<TARGET_FILE:${_LIBRARY}>\" DESTINATION \"\${RUNTIME_FOLDER}\")\n"
				"\tlist(APPEND BINARIES_TO_SIGN \"\${RUNTIME_FOLDER}/$<TARGET_FILE_NAME:${_LIBRARY}>\")\n"
				"endif()\n"
			)
			# Don't forget to copy the SONAME symlink if it exists (for platforms supporting it), no need to sign it as it's a symlink
			if(NOT CMAKE_SYSTEM_NAME STREQUAL "Windows")
				string(CONCAT COPY_TARGET_FILE_CODE
					${COPY_TARGET_FILE_CODE}
					"if(NOT \"$<TARGET_FILE_NAME:${_LIBRARY}>\" STREQUAL \"$<TARGET_SONAME_FILE_NAME:${_LIBRARY}>\")\n"
					"\tcu_is_newer_than(\"$<TARGET_SONAME_FILE:${_LIBRARY}>\" \"\${RUNTIME_FOLDER}/$<TARGET_SONAME_FILE_NAME:${_LIBRARY}>\" IS_NEWER_THAN_RESULT)\n"
					"\tif(\${IS_NEWER_THAN_RESULT})\n"
					"\t\tmessage(\" - Copying target file SONAME $<TARGET_SONAME_FILE:${_LIBRARY}> => \${RUNTIME_FOLDER}\")\n"
					"\t\tfile(COPY \"$<TARGET_SONAME_FILE:${_LIBRARY}>\" DESTINATION \"\${RUNTIME_FOLDER}\")\n"
					"\tendif()\n"
					"endif()\n"
				)
			endif()

			string(APPEND DEPLOY_SCRIPT_CONTENT
				"${COPY_TARGET_FILE_CODE}"
			)

			# If install deployment is requested
			if(DEPLOY_INSTALL)
				# Don't use the install rule for macOS bundles, as we want to copy the files directly in the bundle during compilation phase. The install rule of the bundle itself will copy the full bundle including all copied files in it
				if(NOT CMAKE_SYSTEM_NAME STREQUAL "Darwin" OR NOT _IS_BUNDLE)
					install(CODE
						"${COPY_TARGET_FILE_CODE}"
					)
				endif()
			endif()
		endforeach()
	endif()

	# Handle Qt dependencies
	if(_QT_DEPENDENCIES_OUTPUT)
		list(REMOVE_DUPLICATES _QT_DEPENDENCIES_OUTPUT)
		if(CMAKE_SYSTEM_NAME STREQUAL "Windows" OR CMAKE_SYSTEM_NAME STREQUAL "Darwin")
			if(NOT TARGET Qt5::qmake)
				message(FATAL_ERROR "Cannot find Qt5::qmake")
			endif()

			get_target_property(_QMAKE_LOCATION Qt5::qmake IMPORTED_LOCATION)
			get_filename_component(_DEPLOYQT_DIR ${_QMAKE_LOCATION} DIRECTORY)

			if(CMAKE_SYSTEM_NAME STREQUAL "Windows")
				file(TO_CMAKE_PATH "${_DEPLOYQT_DIR}/windeployqt" DEPLOY_QT_COMMAND)
			elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
				file(TO_CMAKE_PATH "${_DEPLOYQT_DIR}/macdeployqt" DEPLOY_QT_COMMAND)
			endif()

			if (NOT DEPLOY_QML_DIR)
				set(DEPLOY_QML_DIR ".")
			endif()

			if(CMAKE_SYSTEM_NAME STREQUAL "Windows")
				# We also need to run deploy on the target executable so add it at the end of the list
				list(REMOVE_ITEM _QT_DEPENDENCIES_OUTPUT ${TARGET_NAME})
				list(APPEND _QT_DEPENDENCIES_OUTPUT ${TARGET_NAME})

				# Each dependency may depend on specific Qt module so run deploy on each one
				foreach(_QT_DEPENDENCY ${_QT_DEPENDENCIES_OUTPUT})
					# Run deploy and in a specific directory
					string(APPEND DEPLOY_SCRIPT_CONTENT
						"execute_process(COMMAND \"${DEPLOY_QT_COMMAND}\" -verbose 0 --dir \"$<TARGET_FILE_DIR:${TARGET_NAME}>/_deployqt\" --no-patchqt -no-translations -no-system-d3d-compiler --no-compiler-runtime --no-webkit2 -no-angle --no-opengl-sw --qmldir \"${DEPLOY_QML_DIR}\" \"$<TARGET_FILE:${_QT_DEPENDENCY}>\")\n"
					)
				endforeach()

				# Copy the deployed content next to the target binary
				string(APPEND DEPLOY_SCRIPT_CONTENT
					"execute_process(COMMAND \"${CMAKE_COMMAND}\" -E copy_directory \"$<TARGET_FILE_DIR:${TARGET_NAME}>/_deployqt\" \"$<TARGET_FILE_DIR:${TARGET_NAME}>\")\n"
				)

				# Mark the deploy folder if required for install
				if(DEPLOY_INSTALL)
					install(DIRECTORY $<TARGET_FILE_DIR:${TARGET_NAME}>/_deployqt/ DESTINATION bin)
				endif()
			elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
				if(NOT _IS_BUNDLE)
					message(WARNING "Qt on macOS is only supported for BUNDLE applications (Convert ${TARGET_NAME} to a BUNDLE application)")
				else()
					STRING(REPLACE "\"" "" UNQUOTED_CODESIGN_IDENTITY ${DEPLOY_CODESIGN_IDENTITY})
					string(APPEND DEPLOY_SCRIPT_CONTENT
						"execute_process(COMMAND \"${DEPLOY_QT_COMMAND}\" \"$<TARGET_BUNDLE_DIR:${TARGET_NAME}>\" -verbose=0 -qmldir=${DEPLOY_QML_DIR} \"-codesign=${UNQUOTED_CODESIGN_IDENTITY}\")\n"
					)
				endif()
			endif()
		endif()
	endif()

	# Call deploy non-qt runtime (to handle transitive dependencies) for easy-debug
	string(APPEND DEPLOY_SCRIPT_CONTENT
		"list(REMOVE_DUPLICATES DEPENDENCIES_SEARCH_DIRS)\n"
		"cu_deploy_runtime_binary(BINARY_PATH \"$<TARGET_FILE:${TARGET_NAME}>\" SEARCH_DIRS \${DEPENDENCIES_SEARCH_DIRS} TARGET_DIR \"\${RUNTIME_FOLDER}\" COPIED_FILES_VAR COPIED_FILES)\n"
	)

	if(DEPLOY_INSTALL)
		# Don't use the install rule for macOS bundles, as we want to copy the files directly in the bundle during compilation phase. The install rule of the bundle itself will copy the full bundle including all copied files in it
		if(NOT CMAKE_SYSTEM_NAME STREQUAL "Darwin" OR NOT _IS_BUNDLE)
			# Call deploy non-qt runtime (to handle transitive dependencies) for install (not the same folder than easy-debug!!)
			install(CODE
				"list(REMOVE_DUPLICATES DEPENDENCIES_SEARCH_DIRS)"
			)
			install(CODE
				 "cu_deploy_runtime_binary(BINARY_PATH \"$<TARGET_FILE:${TARGET_NAME}>\" SEARCH_DIRS \${DEPENDENCIES_SEARCH_DIRS} TARGET_DIR \"\${RUNTIME_FOLDER}\" COPIED_FILES_VAR COPIED_FILES)"
			)
		endif()
	endif()

	# Done for deployment
	string(APPEND DEPLOY_SCRIPT_CONTENT
		"file(LOCK \"\${DEPLOY_LOCK_FILE}\" RELEASE)\n"
		"message(STATUS \"Done deploying ${TARGET_NAME}\")\n"
	)
	if(DEPLOY_INSTALL)
		install(CODE
			"file(LOCK \"\${DEPLOY_LOCK_FILE}\" RELEASE)"
		)
	endif()

	# If code signing is requested
	if(DEPLOY_SIGN)
		# Expand options lists
		string(REPLACE ";" " " SIGNTOOL_OPTIONS "${DEPLOY_SIGNTOOL_OPTIONS}")
		string(REPLACE ";" " " SIGNTOOL_AGAIN_OPTIONS "${DEPLOY_SIGNTOOL_AGAIN_OPTIONS}")
		string(REPLACE ";" " " CODESIGN_OPTIONS "${DEPLOY_CODESIGN_OPTIONS}")

		# Codesigning code for both easy-debug and install scripts
		string(CONCAT CODESIGNING_CODE
			"foreach(DEP \${BINARIES_TO_SIGN})\n"
			"	cu_sign_binary(BINARY_PATH \"\${DEP}\" SIGNTOOL_OPTIONS ${SIGNTOOL_OPTIONS} SIGNTOOL_AGAIN_OPTIONS ${SIGNTOOL_AGAIN_OPTIONS} CODESIGN_OPTIONS ${CODESIGN_OPTIONS} CODESIGN_IDENTITY ${DEPLOY_CODESIGN_IDENTITY})\n"
			"endforeach()\n"
			"foreach(DEP \${COPIED_FILES})\n"
			"	cu_sign_binary(BINARY_PATH \"\${DEP}\" SIGNTOOL_OPTIONS ${SIGNTOOL_OPTIONS} SIGNTOOL_AGAIN_OPTIONS ${SIGNTOOL_AGAIN_OPTIONS} CODESIGN_OPTIONS ${CODESIGN_OPTIONS} CODESIGN_IDENTITY ${DEPLOY_CODESIGN_IDENTITY})\n"
			"endforeach()\n"
		)

		string(APPEND DEPLOY_SCRIPT_CONTENT
			"message(STATUS \"Code signing runtime dependencies for ${TARGET_NAME}...\")\n"
			"${CODESIGNING_CODE}"
			"message(STATUS \"Done\")\n"
		)

		if(DEPLOY_INSTALL)
			install(CODE
				"${CODESIGNING_CODE}"
			)
			# Xcode Generator will use its own signature, so we need to re-sign during installation
			if("${CMAKE_GENERATOR}" STREQUAL "Xcode")
				if(${_IS_BUNDLE})
					set(resign_binary_path "$<TARGET_BUNDLE_DIR:${TARGET_NAME}>")
				else()
					set(resign_binary_path "$<TARGET_FILE:${TARGET_NAME}>")
				endif()
				string(APPEND INSTALL_RESIGN_CODE
					"message(STATUS \"Code re-signing ${TARGET_NAME}...\")\n"
					"cu_sign_binary(BINARY_PATH \"${resign_binary_path}\" SIGNTOOL_OPTIONS ${SIGNTOOL_OPTIONS} SIGNTOOL_AGAIN_OPTIONS ${SIGNTOOL_AGAIN_OPTIONS} CODESIGN_OPTIONS ${CODESIGN_OPTIONS} CODESIGN_IDENTITY ${DEPLOY_CODESIGN_IDENTITY})\n"
					"message(STATUS \"Done\")\n"
				)
				install(CODE
					"\n${INSTALL_RESIGN_CODE}"
				)
			endif()
		endif()
	endif()

	# Write to a cmake file
	file(GENERATE
		OUTPUT ${DEPLOY_SCRIPT}
		CONTENT ${DEPLOY_SCRIPT_CONTENT}
	)

	# Finally, run the deploy script as POST_BUILD command on the target
	add_custom_command(TARGET ${TARGET_NAME}
		POST_BUILD
		COMMAND ${CMAKE_COMMAND} -P ${DEPLOY_SCRIPT}
		VERBATIM
	)
endfunction()

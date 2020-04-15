###############################################################################
### CMake script handling deployment of the runtime dependencies of a target

# Avoid multi inclusion of this file
if(CU_TARGET_SETUP_DEPLOY_INCLUDED)
	return()
endif()
set(CU_TARGET_SETUP_DEPLOY_INCLUDED true)

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
# Mandatory parameters:
#  - VCPKG_INSTALLED_PATH <vcpkg installed folder>
# Optional parameters:
# - "INSTALL" flag, instructing the script to also install-deploy the runtime dependencies
# - "QML_DIR <path>" option, overriding default QML_DIR folder
function(cu_deploy_runtime_target TARGET_NAME)
	set(VISITED_DEPENDENCIES)
	cu_private_target_list_link_libraries(${TARGET_NAME} _LIBRARY_DEPENDENCIES_OUTPUT _QT_DEPENDENCIES_OUTPUT)

	# Nothing to deploy?
	if(NOT _LIBRARY_DEPENDENCIES_OUTPUT AND NOT _QT_DEPENDENCIES_OUTPUT)
		return()
	endif()

	get_target_property(_IS_BUNDLE ${TARGET_NAME} MACOSX_BUNDLE)

	# We generate a cmake script that will contain all the commands
	set(DEPLOY_SCRIPT ${CMAKE_CURRENT_BINARY_DIR}/$<CONFIG>/cu_deploy_runtime_${TARGET_NAME}.cmake)

	string(APPEND DEPLOY_SCRIPT_CONTENT
		"message(STATUS \"Deploying runtime dependencies for ${TARGET_NAME}...\")\n"
	)

	cmake_parse_arguments(DEPLOY "INSTALL" "QML_DIR;VCPKG_INSTALLED_PATH" "" ${ARGN})

	# Check required parameters validity
	if(NOT DEPLOY_VCPKG_INSTALLED_PATH)
		message(FATAL_ERROR "VCPKG_INSTALLED_PATH required")
	endif()

	# Compute runtime libraries destination folder
	get_filename_component(INSTALL_BASE_FOLDER "${CMAKE_INSTALL_PREFIX}" ABSOLUTE BASE_DIR "${CMAKE_BINARY_DIR}")
	if(CMAKE_HOST_WIN32)
		# For windows, we copy in the same folder than the binary
		set(RUNTIME_LIBRARIES_DEST_FOLDER "$<TARGET_FILE_DIR:${TARGET_NAME}>")
		# And install in the bin folder
		set(RUNTIME_LIBRARIES_INST_FOLDER "${INSTALL_BASE_FOLDER}/bin")
	else()
		if(APPLE AND _IS_BUNDLE)
			# For macOS bundle, we want to copy the file directly inside the bundle
			set(RUNTIME_LIBRARIES_DEST_FOLDER "$<TARGET_BUNDLE_CONTENT_DIR:${TARGET_NAME}>/Frameworks/")
			# We don't want to install, as we'll copy the whole bundle
		else()
			# For macOS non-bundle and linux, we copy in the lib folder
			set(RUNTIME_LIBRARIES_DEST_FOLDER "$<TARGET_FILE_DIR:${TARGET_NAME}>/../lib")
			# And install in the lib folder
			set(RUNTIME_LIBRARIES_INST_FOLDER "${INSTALL_BASE_FOLDER}/lib")
		endif()
	endif()

	if(DEPLOY_INSTALL)
		install(CODE
			"include(\"${CU_TARGET_SETUP_DEPLOY_FOLDER}/DeployBinaryDependencies.cmake\")"
		)
	endif()

	# Handle non-Qt dependencies
	if(_LIBRARY_DEPENDENCIES_OUTPUT)
		list(REMOVE_DUPLICATES _LIBRARY_DEPENDENCIES_OUTPUT)
		# Process each runtime dependency
		foreach(_LIBRARY ${_LIBRARY_DEPENDENCIES_OUTPUT})
			# If install deployement is requested
			if(DEPLOY_INSTALL)
				if(CMAKE_HOST_WIN32)
					# Classic install
					install(
						FILES $<TARGET_FILE:${_LIBRARY}>
						DESTINATION bin
					)
					# Runtime dependencies install
					install(CODE
						"cu_deploy_runtime_binary(BINARY_PATH \"$<TARGET_FILE:${TARGET_NAME}>\" INSTALLED_DIR \"${DEPLOY_VCPKG_INSTALLED_PATH}$<$<CONFIG:Debug>:/debug>\" TARGET_DIR \"${RUNTIME_LIBRARIES_INST_FOLDER}\")"
					)
				# Don't use the install rule for macOS bundles, as we want to copy the files directly in the bundle during compilation phase. The install rule of the bundle itself will copy the full bundle including all copied files in it
				elseif(NOT _IS_BUNDLE)
					install(
						FILES $<TARGET_FILE:${_LIBRARY}> $<TARGET_SONAME_FILE:${_LIBRARY}>
						DESTINATION lib
					)
				endif()
			endif()
			# Copy shared library to the output build folder for easy debug
			if(CMAKE_HOST_WIN32)
				# For windows, we copy in the same folder than the binary
				string(APPEND DEPLOY_SCRIPT_CONTENT
					"message(\" - Copying $<TARGET_FILE:${_LIBRARY}> => ${RUNTIME_LIBRARIES_DEST_FOLDER}\")\n"
					"file(COPY \"$<TARGET_FILE:${_LIBRARY}>\" DESTINATION \"$<TARGET_FILE_DIR:${TARGET_NAME}>\")\n"
				)
			else()
				# Copy dynamic library and don't forget to copy the SONAME symlink if it exists
				string(APPEND DEPLOY_SCRIPT_CONTENT
					"message(\" - Copying $<TARGET_FILE:${_LIBRARY}> => ${RUNTIME_LIBRARIES_DEST_FOLDER}\")\n"
					"file(COPY \"$<TARGET_FILE:${_LIBRARY}>\" DESTINATION \"${RUNTIME_LIBRARIES_DEST_FOLDER}\")\n"
					"if(NOT \"$<TARGET_FILE_NAME:${_LIBRARY}>\" STREQUAL \"$<TARGET_SONAME_FILE_NAME:${_LIBRARY}>\")\n"
					"\tmessage(\" - Copying SONAME $<TARGET_SONAME_FILE:${_LIBRARY}> => ${RUNTIME_LIBRARIES_DEST_FOLDER}\")\n"
					"\tfile(COPY \"$<TARGET_SONAME_FILE:${_LIBRARY}>\" DESTINATION \"${RUNTIME_LIBRARIES_DEST_FOLDER}\")\n"
					"endif()\n"
				)
			endif()
		endforeach()
	endif()

	# Handle Qt dependencies
	if(_QT_DEPENDENCIES_OUTPUT)
		list(REMOVE_DUPLICATES _QT_DEPENDENCIES_OUTPUT)
		if(CMAKE_HOST_WIN32 OR APPLE)
			if(NOT TARGET Qt5::qmake)
				message(FATAL_ERROR "Cannot find Qt5::qmake")
			endif()

			get_target_property(_QMAKE_LOCATION Qt5::qmake IMPORTED_LOCATION)
			get_filename_component(_DEPLOYQT_DIR ${_QMAKE_LOCATION} DIRECTORY)

			if(CMAKE_HOST_WIN32)
				file(TO_CMAKE_PATH "${_DEPLOYQT_DIR}/windeployqt" DEPLOY_QT_COMMAND)
			elseif(APPLE)
				file(TO_CMAKE_PATH "${_DEPLOYQT_DIR}/macdeployqt" DEPLOY_QT_COMMAND)
			endif()

			if (NOT DEPLOY_QML_DIR)
				set(DEPLOY_QML_DIR ".")
			endif()

			if(CMAKE_HOST_WIN32)
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
			elseif(APPLE)
				if(NOT _IS_BUNDLE)
				message(WARNING "Qt on macOS is only supported for BUNDLE applications (Convert ${TARGET_NAME} to a BUNDLE application)")
				else()
					string(APPEND DEPLOY_SCRIPT_CONTENT
						"execute_process(COMMAND \"${DEPLOY_QT_COMMAND}\" \"$<TARGET_BUNDLE_DIR:${TARGET_NAME}>\" -verbose=0 -qmldir=${DEPLOY_QML_DIR} \"-codesign=${LA_TEAM_IDENTIFIER}\")\n"
					)
				endif()
			endif()
		endif()
	endif()

	# Setup call for binary deploy script
	string(APPEND DEPLOY_SCRIPT_CONTENT
		"include(\"${CU_TARGET_SETUP_DEPLOY_FOLDER}/DeployBinaryDependencies.cmake\")\n"
		"cu_deploy_runtime_binary(BINARY_PATH \"$<TARGET_FILE:${TARGET_NAME}>\" INSTALLED_DIR \"${DEPLOY_VCPKG_INSTALLED_PATH}$<$<CONFIG:Debug>:/debug>\" TARGET_DIR \"${RUNTIME_LIBRARIES_DEST_FOLDER}\")\n"
	)

	string(APPEND DEPLOY_SCRIPT_CONTENT
		"message(STATUS \"Done\")\n"
	)

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

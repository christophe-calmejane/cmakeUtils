###############################################################################
### CMake script to generate a C# target

# Avoid multi inclusion of this file (cannot use include_guard as multiple copies of this file are included from multiple places)
if(CU_GENERATE_CSHARP_TARGET_INCLUDED)
	return()
endif()
set(CU_GENERATE_CSHARP_TARGET_INCLUDED true)

set(CU_GENERATE_CSHARP_TARGET_FOLDER "${CMAKE_CURRENT_LIST_DIR}")

########
# Generate C# target
# Mandatory parameters:
#  - "TARGET_NAME <target name>" => Name of the target. A custom target named "<TARGET_NAME>-csharp" will be created to build the project but the binary will be named "<TARGET_NAME>"
# Optional parameters:
#  - "CSPROJ_TEMPLATE_PATH <path to the csproj template to use>" => Path to the csproj template to use (default: ProjectTemplate.csproj.in)
#  - "CSPROJ_FILE_NAME <csproj file name>" => Name of the csproj file to generate (default: TARGET_NAME)
#  - "SLN_FILE_NAME <sln file name>" => Name of the sln file to generate (default: TARGET_NAME)
#  - "ADDITIONAL_DEPENDENCIES <list of additional dependencies>" => List of additional dependencies to add to the custom target
function(cu_generate_csharp_target)
	cmake_parse_arguments(CUGCST "" "TARGET_NAME;CSPROJ_TEMPLATE_PATH;CSPROJ_FILE_NAME;SLN_FILE_NAME" "ADDITIONAL_DEPENDENCIES" ${ARGN})

	# Check required parameters validity
	if(NOT CUGCST_TARGET_NAME)
		message(FATAL_ERROR "TARGET_NAME required")
	endif()

	# Default values
	set(CSPROJ_FILE_NAME ${CUGCST_TARGET_NAME})
	set(SLN_FILE_NAME ${CUGCST_TARGET_NAME})
	set(CSPROJ_TEMPLATE_PATH "${CU_GENERATE_CSHARP_TARGET_FOLDER}/supportFiles/ProjectTemplate.csproj.in")

	# Override default values
	if(CUGCST_CSPROJ_FILE_NAME)
		set(CSPROJ_FILE_NAME ${CUGCST_CSPROJ_FILE_NAME})
	endif()
	if(CUGCST_SLN_FILE_NAME)
		set(SLN_FILE_NAME ${CUGCST_SLN_FILE_NAME})
	endif()
	if(CUGCST_CSPROJ_TEMPLATE_PATH)
		set(CSPROJ_TEMPLATE_PATH ${CUGCST_CSPROJ_TEMPLATE_PATH})
	endif()
	# Check if the template file exists
	if(NOT EXISTS ${CSPROJ_TEMPLATE_PATH})
		message(FATAL_ERROR "Specified csproj template file does not exist: ${CSPROJ_TEMPLATE_PATH}")
	endif()

	# Print message
	message(STATUS "Generating C# target ${CUGCST_TARGET_NAME}")

	# Configure csproj file (to expand variables)
	configure_file(
		"${CSPROJ_TEMPLATE_PATH}"
		"${CMAKE_CURRENT_BINARY_DIR}/${CSPROJ_FILE_NAME}.csproj.template"
	)

	# Generate csproj file (to use generator expressions)
	file(GENERATE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/${CSPROJ_FILE_NAME}.csproj" INPUT "${CMAKE_CURRENT_BINARY_DIR}/${CSPROJ_FILE_NAME}.csproj.template")

	# Generate the sln file and add the project to it (we need to use a custom command because the csproj file is generated during the build)
	add_custom_command(
		OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/${SLN_FILE_NAME}.sln"
		COMMAND ${CMAKE_COMMAND} -E rm -f "${CMAKE_CURRENT_BINARY_DIR}/${SLN_FILE_NAME}.sln"
		COMMAND dotnet new sln --name ${SLN_FILE_NAME}
		COMMAND dotnet sln add "${CMAKE_CURRENT_BINARY_DIR}/${CSPROJ_FILE_NAME}.csproj"
		WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
		DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/${CSPROJ_FILE_NAME}.csproj" ${CUGCST_ADDITIONAL_DEPENDENCIES}
	)

	# Add a custom target to generate the sln file
	add_custom_target(
		${SLN_FILE_NAME}Sln ALL
		DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/${SLN_FILE_NAME}.sln"
	)

	# Add a custom target to build the project
	add_custom_target(
		${CUGCST_TARGET_NAME}-csharp ALL
		COMMAND dotnet publish --property:PublishDir=. -c ${CMAKE_BUILD_TYPE}
		WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
		DEPENDS ${SLN_FILE_NAME}Sln
	)
endfunction()

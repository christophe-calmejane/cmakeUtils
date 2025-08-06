###############################################################################
### CMake script to generate a C# target

# Avoid multi inclusion of this file (cannot use include_guard as multiple copies of this file are included from multiple places)
if(CU_GENERATE_CSHARP_TARGET_INCLUDED)
	return()
endif()
set(CU_GENERATE_CSHARP_TARGET_INCLUDED true)

set(CU_GENERATE_CSHARP_TARGET_FOLDER "${CMAKE_CURRENT_LIST_DIR}")

##################################
# Internal function
function(cu_private_get_target_soname_file_name_generator_expression TARGET_NAME)
	set(CS_TARGET_FILE_NAME "")
	if(CMAKE_SYSTEM_NAME STREQUAL "Windows")
		# On windows, use TARGET_FILE_NAME
		set(CS_TARGET_FILE_NAME "$<TARGET_FILE_NAME:${TARGET_NAME}>")
	else()
		# For non-windows targets that use SONAME, we want to use the soname file (which is a symbolink link to the LINKER file, but it will be copied by following the link)
		set(CS_TARGET_FILE_NAME "$<TARGET_SONAME_FILE_NAME:${TARGET_NAME}>")
		# If someday csproj files support copying symbolink links, we'll have to copy the 3 files (without following the links): TARGET_FILE_NAME, TARGET_LINKER_FILE_NAME and TARGET_SONAME_FILE_NAME
	endif()
	# Return the CS_TARGET_FILE_NAME to the caller
	set(CS_TARGET_FILE_NAME "${CS_TARGET_FILE_NAME}" PARENT_SCOPE)
endfunction()

##################################
# Internal function
function(cu_private_get_target_file_name_generator_expression TARGET_NAME)
	set(CS_TARGET_FILE_NAME "")
	if(CMAKE_SYSTEM_NAME STREQUAL "Windows")
		# On windows, use TARGET_FILE_NAME
		set(CS_TARGET_FILE_NAME "$<TARGET_FILE_NAME:${TARGET_NAME}>")
	else()
		# For non-windows targets that use SONAME, we want to use the linker file (which is a symbolink link to the SONAME file, but it will be copied by following the link)
		set(CS_TARGET_FILE_NAME "$<TARGET_LINKER_FILE_NAME:${TARGET_NAME}>")
		# If someday csproj files support copying symbolink links, we'll have to copy the 3 files (without following the links): TARGET_FILE_NAME, TARGET_LINKER_FILE_NAME and TARGET_SONAME_FILE_NAME
	endif()
	# Return the CS_TARGET_FILE_NAME to the caller
	set(CS_TARGET_FILE_NAME "${CS_TARGET_FILE_NAME}" PARENT_SCOPE)
endfunction()

##################################
# Add a C# target dependency to CU_CSHARP_ADDITIONAL_COMPILE_ITEMS and CU_CSHARP_ADDITIONAL_CONTENT_ITEMS variables
# Mandatory parameters:
#  - "TARGET_NAME" => Name of the C# target
function(cu_generate_csharp_target_add_csharp_dependency TARGET_NAME)
	# Check TARGET_NAME exists
	if(NOT TARGET ${TARGET_NAME})
		message(FATAL_ERROR "Target ${TARGET_NAME} does not exist")
	endif()

	cu_private_get_target_file_name_generator_expression("${TARGET_NAME}")
	string(APPEND CU_CSHARP_ADDITIONAL_COMPILE_ITEMS "      <Compile Include=\"$<TARGET_FILE_DIR:${TARGET_NAME}>/SWIG_${TARGET_NAME}/csharp.files/**/*.cs\" />\n")
	string(APPEND CU_CSHARP_ADDITIONAL_CONTENT_ITEMS "      <Content Include=\"$<TARGET_FILE:${TARGET_NAME}>\" Link=\"${CS_TARGET_FILE_NAME}\"><CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory></Content>\n")

	set(VISITED_DEPENDENCIES)
	cu_private_target_list_link_libraries("${TARGET_NAME}" "${TARGET_NAME}" _LIBRARY_DEPENDENCIES_OUTPUT _QT_DEPENDENCIES_OUTPUT)
	if(_LIBRARY_DEPENDENCIES_OUTPUT)
		list(REMOVE_DUPLICATES _LIBRARY_DEPENDENCIES_OUTPUT)
		foreach(_LIBRARY ${_LIBRARY_DEPENDENCIES_OUTPUT})
			# Check if the library is a target
			if(TARGET ${_LIBRARY})
			cu_private_get_target_soname_file_name_generator_expression("${_LIBRARY}")
				string(APPEND CU_CSHARP_ADDITIONAL_CONTENT_ITEMS "      <Content Include=\"$<TARGET_FILE:${_LIBRARY}>\" Link=\"${CS_TARGET_FILE_NAME}\"><CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory></Content>\n")
			endif()
		endforeach()
	endif()
	string(APPEND CU_CSHARP_ADDITIONAL_CONTENT_ITEMS "\n")

	# Return CU_CSHARP_ADDITIONAL_COMPILE_ITEMS and CU_CSHARP_ADDITIONAL_CONTENT_ITEMS to the caller
	set(CU_CSHARP_ADDITIONAL_COMPILE_ITEMS "${CU_CSHARP_ADDITIONAL_COMPILE_ITEMS}" PARENT_SCOPE)
	set(CU_CSHARP_ADDITIONAL_CONTENT_ITEMS "${CU_CSHARP_ADDITIONAL_CONTENT_ITEMS}" PARENT_SCOPE)
endfunction()

##################################
# Add a Nuget dependency to CU_CSHARP_ADDITIONAL_CONTENT variables
# Mandatory parameters:
#  - "NUGET_NAME" => Name of the NuGet package
#  - "NUGET_VERSION" => Version of the NuGet package
function(cu_generate_csharp_target_add_nuget_dependency NUGET_NAME NUGET_VERSION)
	# Check NUGET_NAME and NUGET_VERSION are set
	if(NOT NUGET_NAME)
		message(FATAL_ERROR "NUGET_NAME required")
	endif()
	if(NOT NUGET_VERSION)
		message(FATAL_ERROR "NUGET_VERSION required")
	endif()

	string(APPEND CU_CSHARP_ADDITIONAL_CONTENT
		"  <ItemGroup Condition=\"'$(RuntimeIdentifier)' == 'osx-arm64' or '$(RuntimeIdentifier)' == 'osx-x64'\">\n"
		"    <PackageReference Include=\"${NUGET_NAME}-osx\" Version=\"${NUGET_VERSION}\" />\n"
		"  </ItemGroup>\n"
		"  <ItemGroup Condition=\"'$(RuntimeIdentifier)' == 'win-x64'\">\n"
		"    <PackageReference Include=\"${NUGET_NAME}-win-x64\" Version=\"${NUGET_VERSION}\" />\n"
		"  </ItemGroup>\n"
	)

	# Return CU_CSHARP_ADDITIONAL_COMPILE_ITEMS to the caller
	set(CU_CSHARP_ADDITIONAL_CONTENT "${CU_CSHARP_ADDITIONAL_CONTENT}" PARENT_SCOPE)
endfunction()

##################################
# Generate C# target
# Mandatory parameters:
#  - "TARGET_NAME <target name>" => Name of the target. A custom target named "<TARGET_NAME>-csharp" will be created to build the project but the binary will be named "<TARGET_NAME>"
# Optional parameters:
#  - "CSPROJ_TEMPLATE_PATH <path to the csproj template to use>" => Path to the csproj template to use (default: ProjectTemplate.csproj.in)
#  - "CSPROJ_FILE_NAME <csproj file name>" => Name of the csproj file to generate (default: TARGET_NAME)
#  - "SLN_FILE_NAME <sln file name>" => Name of the sln file to generate (default: TARGET_NAME)
#  - "ADDITIONAL_DEPENDENCIES <list of additional dependencies>" => List of additional dependencies to add to the custom target
#  - "NO_WARNING_AS_ERROR" => Do not add the 'TreatWarningsAsErrors' property to the csproj file (Default: add it)
function(cu_generate_csharp_target)
	cmake_parse_arguments(CUGCST "NO_WARNING_AS_ERROR" "TARGET_NAME;CSPROJ_TEMPLATE_PATH;CSPROJ_FILE_NAME;SLN_FILE_NAME" "ADDITIONAL_DEPENDENCIES" ${ARGN})

	# Check required parameters validity
	if(NOT CUGCST_TARGET_NAME)
		message(FATAL_ERROR "TARGET_NAME required")
	endif()

	# Default values
	set(CSPROJ_FILE_NAME ${CUGCST_TARGET_NAME})
	set(SLN_FILE_NAME ${CUGCST_TARGET_NAME})
	set(CSPROJ_TEMPLATE_PATH "${CU_GENERATE_CSHARP_TARGET_FOLDER}/supportFiles/ProjectTemplate.csproj.in")
	set(CSPROJ_TREAT_WARNINGS_AS_ERRORS "true")

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
	if(CUGCST_NO_WARNING_AS_ERROR)
		set(CSPROJ_TREAT_WARNINGS_AS_ERRORS "false")
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

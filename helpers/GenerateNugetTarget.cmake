###############################################################################
### CMake script to generate a C# nuget target

# Avoid multi inclusion of this file (cannot use include_guard as multiple copies of this file are included from multiple places)
if(CU_GENERATE_CSHARP_NUGET_TARGET_INCLUDED)
	return()
endif()
set(CU_GENERATE_CSHARP_NUGET_TARGET_INCLUDED true)

set(CU_GENERATE_CSHARP_NUGET_TARGET_FOLDER "${CMAKE_CURRENT_LIST_DIR}")

#######################################################################
# Internal function
macro(cu_private_add_runtime_content_item ITEM_PATH OUTPUT_STRING)
	string(APPEND ${OUTPUT_STRING} "    <Content Include=\"${ITEM_PATH}\">\n      <Pack>true</Pack>\n      <PackagePath>runtimes/${CU_DOTNET_RUNTIME}/native</PackagePath>\n    </Content>\n")
endmacro()


########
# Generate C# nuget target
# Mandatory parameters:
#  - "TARGET_NAME <target name>" => Name of the target. A custom target named "<TARGET_NAME>-csharp" will be created to build the project but the binary will be named "<TARGET_NAME>"
# Optional parameters:
#  - "CSPROJ_TEMPLATE_PATH <path to the csproj template to use>" => Path to the csproj template to use (default: NugetTemplate.csproj.in)
#  - "CSPROJ_FILE_NAME <csproj file name>" => Name of the csproj file to generate (default: TARGET_NAME)
#  - "CS_SOURCE_FOLDERS <list of source folders>" => List of source folders to compile (default: empty)
#  - "NUGET_SOURCE_URL <nuget source url>" => Nuget source url to use (default: https://api.nuget.org/v3/index.json)
#  - "NUGET_API_KEY <nuget api key>" => Nuget api key to use (default: empty)
function(cu_generate_csharp_nuget_target)
	# Check for cmake minimum version
	cmake_minimum_required(VERSION 3.27) # TARGET_LINKER_FILE added in cmake 3.27

	cmake_parse_arguments(CUGCSNT "" "TARGET_NAME;CSPROJ_TEMPLATE_PATH;CSPROJ_FILE_NAME;NUGET_SOURCE_URL;NUGET_API_KEY" "CS_SOURCE_FOLDERS" ${ARGN})

	# Check required parameters validity
	if(NOT CUGCSNT_TARGET_NAME)
		message(FATAL_ERROR "TARGET_NAME required")
	endif()

	# Default values
	set(CSPROJ_FILE_NAME ${CUGCSNT_TARGET_NAME})
	set(CSPROJ_TEMPLATE_PATH "${CU_GENERATE_CSHARP_NUGET_TARGET_FOLDER}/supportFiles/NugetTemplate.csproj.in")
	set(NUGET_SOURCE_URL "https://api.nuget.org/v3/index.json")
	set(NUGET_API_KEY "")

	# Override default values
	if(CUGCSNT_CSPROJ_FILE_NAME)
		set(CSPROJ_FILE_NAME ${CUGCSNT_CSPROJ_FILE_NAME})
	endif()
	if(CUGCSNT_CSPROJ_TEMPLATE_PATH)
		set(CSPROJ_TEMPLATE_PATH ${CUGCSNT_CSPROJ_TEMPLATE_PATH})
	endif()
	if(CUGCSNT_NUGET_SOURCE_URL)
		set(NUGET_SOURCE_URL ${CUGCSNT_NUGET_SOURCE_URL})
	endif()
	if(CUGCSNT_NUGET_API_KEY)
		set(NUGET_API_KEY -k ${CUGCSNT_NUGET_API_KEY})
	endif()
	# Check if the template file exists
	if(NOT EXISTS ${CSPROJ_TEMPLATE_PATH})
		message(FATAL_ERROR "Specified csproj template file does not exist: ${CSPROJ_TEMPLATE_PATH}")
	endif()

	# Generate the list of source folders to compile
	set(CSPROJ_COMPILE_ITEMS "")
	foreach(CS_SOURCE_FOLDER ${CUGCSNT_CS_SOURCE_FOLDERS})
		string(APPEND CSPROJ_COMPILE_ITEMS "    <Compile Include=\"${CS_SOURCE_FOLDER}/**/*.cs\" />\n")
	endforeach()
	
	# Generate the list of runtime content items
	set(CSPROJ_RUNTIME_ITEMS "")
	# On windows, use TARGET_FILE to get the DLL file
	if(CMAKE_SYSTEM_NAME STREQUAL "Windows")
		cu_private_add_runtime_content_item("$<TARGET_FILE:${CUGCSNT_TARGET_NAME}>" CSPROJ_RUNTIME_ITEMS)
	else()
		# For non-windows targets that use SONAME, we want to use the linker file (which is a symbolink link to the SONAME file, but it will be copied by following the link)
		cu_private_add_runtime_content_item("$<TARGET_LINKER_FILE:${CUGCSNT_TARGET_NAME}>" CSPROJ_RUNTIME_ITEMS)
		# If someday csproj files support copying symbolink links, we'll have to copy the 3 files (without following the links): TARGET_FILE, TARGET_LINKER_FILE and TARGET_SONAME_FILE
	endif()

	# Configure csproj file (to expand variables)
	configure_file(
		"${CSPROJ_TEMPLATE_PATH}"
		"${CMAKE_CURRENT_BINARY_DIR}/${CSPROJ_FILE_NAME}.csproj.template"
	)

	# Generate csproj file (to use generator expressions)
	file(GENERATE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/${CSPROJ_FILE_NAME}-nuget/${CSPROJ_FILE_NAME}.csproj" INPUT "${CMAKE_CURRENT_BINARY_DIR}/${CSPROJ_FILE_NAME}.csproj.template")

	# Print message
	message(STATUS "Generating nuget pack target for ${CUGCSNT_TARGET_NAME}")

	# Add a custom target to pack the nuget
	add_custom_target(
		${CUGCSNT_TARGET_NAME}-nuget-pack ALL
		COMMAND dotnet pack "${CMAKE_CURRENT_BINARY_DIR}/${CSPROJ_FILE_NAME}-nuget/${CSPROJ_FILE_NAME}.csproj"
		WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
		DEPENDS ${CUGCSNT_TARGET_NAME}
	)

	# Add a custom target to push the nuget
	add_custom_target(
		${CUGCSNT_TARGET_NAME}-nuget-push # ALL
		COMMAND dotnet nuget push -s ${NUGET_SOURCE_URL} ${NUGET_API_KEY} "${CMAKE_CURRENT_BINARY_DIR}/${CSPROJ_FILE_NAME}-nuget/bin/Release/${PROJECT_NAME}.${CU_PROJECT_FRIENDLY_VERSION}.nupkg"
		WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
		DEPENDS ${CUGCSNT_TARGET_NAME}-nuget-pack
	)
endfunction()

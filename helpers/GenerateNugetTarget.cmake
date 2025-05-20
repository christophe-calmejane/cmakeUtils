###############################################################################
### CMake script to generate a C# nuget target

# Avoid multi inclusion of this file (cannot use include_guard as multiple copies of this file are included from multiple places)
if(CU_GENERATE_CSHARP_NUGET_TARGET_INCLUDED)
	return()
endif()
set(CU_GENERATE_CSHARP_NUGET_TARGET_INCLUDED true)

# Some global variables
set(CU_GENERATE_CSHARP_NUGET_TARGET_FOLDER "${CMAKE_CURRENT_LIST_DIR}")

########
# Generate C# nuget target
# Mandatory parameters:
#  - "TARGET_NAME <target name>" => Name of the target. A custom target named "<TARGET_NAME>-csharp" will be created to build the project but the binary will be named "<TARGET_NAME>"
# Optional parameters:
#  - "CSPROJ_TEMPLATE_PATH <path to the csproj template to use>" => Path to the csproj template to use (default: NugetTemplate.csproj.in)
#  - "CSPROJ_FILE_NAME <csproj file name>" => Name of the csproj file to generate (default: TARGET_NAME)
#  - "CS_SOURCE_FOLDERS <list of source folders>" => List of source folders to compile (default: empty)
#  - "CS_PACKAGE_DEPENDENCIES <list of dependencies>" => List of package dependencies to add to the csproj file (default: empty). A dependency is in this format: "<PackageName>:<Version>"
#  - "NUGET_PACK_TARGET_DEPENDENCIES <list of dependencies>" => List of cmake targets to be built before the nuget pack target (default: empty)
#  - "NUGET_SOURCE_URL <nuget source url>" => Nuget source url to use (default: https://api.nuget.org/v3/index.json)
#  - "NUGET_API_KEY <nuget api key>" => Nuget api key to use (default: empty)
#  - "CONFIGURATION <configuration>" => Configuration to use (default: ${CMAKE_BUILD_TYPE})
#  - "PACKAGE_NAME <package name>" => Name of the package (default: ${PROJECT_NAME})
#  - "PACKAGE_VERSION <package version>" => Version of the package (default: ${CU_PROJECT_FRIENDLY_VERSION})
function(cu_generate_csharp_nuget_target)
	# Check for cmake minimum version
	cmake_minimum_required(VERSION 3.27) # TARGET_LINKER_FILE added in cmake 3.27

	cmake_parse_arguments(CUGCSNT "" "TARGET_NAME;CSPROJ_TEMPLATE_PATH;CSPROJ_FILE_NAME;NUGET_SOURCE_URL;NUGET_API_KEY;CONFIGURATION;PACKAGE_NAME;PACKAGE_VERSION" "CS_SOURCE_FOLDERS;CS_PACKAGE_DEPENDENCIES;NUGET_PACK_TARGET_DEPENDENCIES" ${ARGN})

	# Check required parameters validity
	if(NOT CUGCSNT_TARGET_NAME)
		message(FATAL_ERROR "TARGET_NAME required")
	endif()

	# Default values
	set(CSPROJ_FILE_NAME ${CUGCSNT_TARGET_NAME})
	set(CSPROJ_TEMPLATE_PATH "${CU_GENERATE_CSHARP_NUGET_TARGET_FOLDER}/supportFiles/NugetTemplate.csproj.in")
	set(NUGET_SOURCE_URL "https://api.nuget.org/v3/index.json")
	set(NUGET_API_KEY "")
	if(DEFINED CMAKE_BUILD_TYPE)
		set(CONFIGURATION ${CMAKE_BUILD_TYPE})
	else()
		set(CONFIGURATION "Release")
	endif()
	set(PACKAGE_NAME ${PROJECT_NAME})
	set(PACKAGE_VERSION ${CU_PROJECT_FRIENDLY_VERSION})

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
	if(CUGCSNT_CONFIGURATION)
		set(CONFIGURATION ${CUGCSNT_CONFIGURATION})
	endif()
	if(CUGCSNT_PACKAGE_NAME)
		set(PACKAGE_NAME ${CUGCSNT_PACKAGE_NAME})
	endif()
	if(CUGCSNT_PACKAGE_VERSION)
		set(PACKAGE_VERSION ${CUGCSNT_PACKAGE_VERSION})
	endif()

	# Check if the template file exists
	if(NOT EXISTS ${CSPROJ_TEMPLATE_PATH})
		message(FATAL_ERROR "Specified csproj template file does not exist: ${CSPROJ_TEMPLATE_PATH}")
	endif()

	# Build the PACKAGE_ID variable based on PACKAGE_NAME and CU_DOTNET_RID_NUGET
	set(PACKAGE_ID "${PACKAGE_NAME}-${CU_DOTNET_RID_NUGET}")

	# Nuget package name
	set(NUGET_PACKAGE_NAME "${PACKAGE_ID}.${PACKAGE_VERSION}.nupkg")

	# Generate the list of source folders to compile
	set(CSPROJ_COMPILE_ITEMS "")
	foreach(CS_SOURCE_FOLDER ${CUGCSNT_CS_SOURCE_FOLDERS})
		string(APPEND CSPROJ_COMPILE_ITEMS "    <Compile Include=\"${CS_SOURCE_FOLDER}/**/*.cs\" />\n")
	endforeach()
	
	# Generate the list of reference items
	set(CSPROJ_REFERENCE_ITEMS "")
	foreach(CS_DEPENDENCY ${CUGCSNT_CS_PACKAGE_DEPENDENCIES})
		string(REPLACE ":" ";" CS_DEPENDENCY_LIST ${CS_DEPENDENCY})
		# Check list size is 2
		list(LENGTH CS_DEPENDENCY_LIST CS_DEPENDENCY_LIST_SIZE)
		if(NOT CS_DEPENDENCY_LIST_SIZE EQUAL 2)
			message(FATAL_ERROR "Invalid dependency format (Expected: <PackageName>:<Version>): '${CS_DEPENDENCY}'")
		endif()
		list(GET CS_DEPENDENCY_LIST 0 CS_DEPENDENCY_NAME)
		list(GET CS_DEPENDENCY_LIST 1 CS_DEPENDENCY_VERSION)
		string(APPEND CSPROJ_REFERENCE_ITEMS "    <PackageReference Include=\"${CS_DEPENDENCY_NAME}\" Version=\"${CS_DEPENDENCY_VERSION}\" />\n")
	endforeach()

	# Configure csproj file (to expand variables)
	set(CS_NUGET_FOLDER "${CMAKE_CURRENT_BINARY_DIR}/${CSPROJ_FILE_NAME}-nuget")
	set(CS_NUGET_NATIVES_FOLDER "${CS_NUGET_FOLDER}/native_dependencies")
	set(CSPROJ_TEMP_PATH "${CS_NUGET_FOLDER}/${CSPROJ_FILE_NAME}.csproj.temp")
	set(CSPROJ_FINAL_PATH "${CS_NUGET_FOLDER}/${CSPROJ_FILE_NAME}.csproj")

	# Configure csproj file from template into a temporary file (to expand variables)
	configure_file(${CSPROJ_TEMPLATE_PATH} ${CSPROJ_TEMP_PATH} @ONLY)

	# We need to generate the csproj file after the build step of the C# target because we need to inspect the target dependencies, so let's create a script that will be run after the target is built
	string(APPEND GENERATE_CSPROJ_SCRIPT_CONTENT "## Script to generate the csproj file\n")

	# Generate the list of runtime content items
	set(CSPROJ_RUNTIME_ITEMS "")
	set(CS_TARGET_PATH "")
	set(CS_REAL_TARGET_PATH "")
	if(CMAKE_SYSTEM_NAME STREQUAL "Windows")
		# On windows, use TARGET_FILE to get the DLL file
		set(CS_TARGET_PATH "$<TARGET_FILE:${CUGCSNT_TARGET_NAME}>")
		set(CS_REAL_TARGET_PATH "$<TARGET_FILE:${CUGCSNT_TARGET_NAME}>")
	else()
		# For non-windows targets that use SONAME, we want to use the linker file (which is a symbolink link to the SONAME file, but it will be copied by following the link)
		set(CS_TARGET_PATH "$<TARGET_LINKER_FILE:${CUGCSNT_TARGET_NAME}>")
		set(CS_REAL_TARGET_PATH "$<TARGET_SONAME_FILE:${CUGCSNT_TARGET_NAME}>")
		# If someday csproj files support copying symbolink links, we'll have to copy the 3 files (without following the links): TARGET_FILE, TARGET_LINKER_FILE and TARGET_SONAME_FILE
	endif()

	get_property(depSearchDirsDebug GLOBAL PROPERTY CU_DEPLOY_RUNTIME_SEARCH_DIRS_DEBUG)
	get_property(depSearchDirsOptimized GLOBAL PROPERTY CU_DEPLOY_RUNTIME_SEARCH_DIRS_OPTIMIZED)

	# Define the header of the script
	string(APPEND GENERATE_CSPROJ_SCRIPT_CONTENT
		"## Get the list of dependencies for the target\n"
		"include(\"${CU_GENERATE_CSHARP_NUGET_TARGET_FOLDER}/DeployBinaryDependencies.cmake\")\n"
		"\n"
		"macro(add_runtime_content_item ITEM_PATH OUTPUT_STRING)\n"
		"\tstring(APPEND \${OUTPUT_STRING} \"    <Content Include=\\\"\${ITEM_PATH}\\\">\\n      <Pack>true</Pack>\\n      <PackagePath>runtimes/${CU_DOTNET_RID_NUGET}/native</PackagePath>\\n    </Content>\\n\")\n"
		"endmacro()\n"
		"\n"
	)
	# Add current binary folder to the search directories
	string(APPEND GENERATE_CSPROJ_SCRIPT_CONTENT
		"list(APPEND DEPENDENCIES_SEARCH_DIRS \"${CMAKE_CURRENT_BINARY_DIR}\")\n"
	)
	# Add the search directories (for debug configuration)
	foreach(DEP_SEARCH_DIR ${depSearchDirsDebug})
		string(APPEND GENERATE_CSPROJ_SCRIPT_CONTENT
			"if(\"$<CONFIG>\" MATCHES \"^([Dd][Ee][Bb][Uu][Gg])$\")\n"
			"\tlist(APPEND DEPENDENCIES_SEARCH_DIRS \"${DEP_SEARCH_DIR}\")\n"
			"endif()\n"
		)
	endforeach()
	# Add the search directories (for non-debug configuration)
	foreach(DEP_SEARCH_DIR ${depSearchDirsOptimized})
		string(APPEND GENERATE_CSPROJ_SCRIPT_CONTENT
			"if(NOT \"$<CONFIG>\" MATCHES \"^([Dd][Ee][Bb][Uu][Gg])$\")\n"
			"\tlist(APPEND DEPENDENCIES_SEARCH_DIRS \"${DEP_SEARCH_DIR}\")\n"
			"endif()\n"
		)
	endforeach()
	# Add the rest of the script
	string(APPEND GENERATE_CSPROJ_SCRIPT_CONTENT
		"# Wipe native dependencies folder\n"
		"file(REMOVE_RECURSE \"${CS_NUGET_NATIVES_FOLDER}\")\n"
		"# Deploy runtime dependencies\n"
		"set(COPIED_FILES)\n"
		"cu_deploy_runtime_binary(BINARY_PATH \"${CS_REAL_TARGET_PATH}\" TARGET_DIR \"${CS_NUGET_NATIVES_FOLDER}\" SEARCH_DIRS \${DEPENDENCIES_SEARCH_DIRS} TARGET_DIR \"\${RUNTIME_FOLDER}\" COPIED_FILES_VAR COPIED_FILES)\n"
		"# Add all copied files to the csproj file\n"
		"set(CSPROJ_RUNTIME_ITEMS \"\")\n"
		"# Add target itself in runtime items\n"
		"add_runtime_content_item(\"${CS_TARGET_PATH}\" CSPROJ_RUNTIME_ITEMS)\n"
		"# Add each copied file to the runtime items\n"
		"foreach(COPIED_FILE \${COPIED_FILES})\n"
		"\tadd_runtime_content_item(\"\${COPIED_FILE}\" CSPROJ_RUNTIME_ITEMS)\n"
		"endforeach()\n"
		"# Configure csproj file (to expand variables again)\n"
		"configure_file(\"${CSPROJ_TEMP_PATH}\" \"${CSPROJ_FINAL_PATH}\")\n"
	)

	# Write the script to a file
	set(GENERATE_CSPROJ_SCRIPT "${CS_NUGET_FOLDER}/generateCSProjet.cmake")
	file(GENERATE
		OUTPUT ${GENERATE_CSPROJ_SCRIPT}
		CONTENT ${GENERATE_CSPROJ_SCRIPT_CONTENT}
		CONDITION $<CONFIG:${CONFIGURATION}>
	)

	# Print message
	message(STATUS "Generating nuget pack target for ${CUGCSNT_TARGET_NAME}")

	# Add a custom target to generate the csproj file
	add_custom_target(
		${CUGCSNT_TARGET_NAME}-generate-csproj
		COMMAND ${CMAKE_COMMAND} -P ${GENERATE_CSPROJ_SCRIPT}
		WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
		DEPENDS ${CUGCSNT_TARGET_NAME}
	)

	# Generate the list of dependencies
	set(NUGET_PACK_TARGET_DEPENDENCIES "${CUGCSNT_TARGET_NAME}-generate-csproj")
	foreach(TARGET_DEPENDENCY ${CUGCSNT_NUGET_PACK_TARGET_DEPENDENCIES})
		list(APPEND NUGET_PACK_TARGET_DEPENDENCIES ${TARGET_DEPENDENCY})
	endforeach()

	# Add a custom target to pack the nuget
	add_custom_target(
		${CUGCSNT_TARGET_NAME}-nuget-pack
		COMMAND dotnet pack "${CSPROJ_FINAL_PATH}" -c ${CONFIGURATION}
		WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
		BYPRODUCTS "${CS_NUGET_FOLDER}/bin/${CONFIGURATION}/${NUGET_PACKAGE_NAME}"
		DEPENDS ${NUGET_PACK_TARGET_DEPENDENCIES}
	)

	# Add a custom target to push the nuget
	add_custom_target(
		${CUGCSNT_TARGET_NAME}-nuget-push
		COMMAND dotnet nuget push --interactive -s ${NUGET_SOURCE_URL} ${NUGET_API_KEY} "${CS_NUGET_FOLDER}/bin/${CONFIGURATION}/${NUGET_PACKAGE_NAME}" --skip-duplicate
		WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
		DEPENDS ${CUGCSNT_TARGET_NAME}-nuget-pack
	)
endfunction()

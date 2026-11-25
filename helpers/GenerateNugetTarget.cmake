###############################################################################
### CMake script to generate native and C# NuGet targets

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
#  - "TARGET_NAME <target name>" => Native target to package. Creates "<TARGET_NAME>-generate-csproj", "<TARGET_NAME>-nuget-pack" and "<TARGET_NAME>-nuget-push".
# Optional parameters:
#  - "CSPROJ_TEMPLATE_PATH <path to the csproj template to use>" => Path to the csproj template to use (default: NugetTemplate.csproj.in)
#  - "CSPROJ_FILE_NAME <csproj file name>" => Name of the csproj file to generate (default: TARGET_NAME)
#  - "CS_SOURCE_FOLDERS <list of source folders>" => List of source folders to compile (default: empty)
#  - "CS_PACKAGE_DEPENDENCIES <list of dependencies>" => List of package dependencies to add to the csproj file (default: empty). A dependency is in this format: "<PackageName>:<Version>"
#  - "NUGET_PACK_TARGET_DEPENDENCIES <list of dependencies>" => List of cmake targets to be built before the nuget pack target (default: empty)
#  - "NUGET_SOURCE_URL <nuget source url>" => Nuget source url to use (default: https://api.nuget.org/v3/index.json)
#  - "NUGET_API_KEY <nuget api key>" => Nuget api key to use (default: empty)
#  - "PACKAGE_NAME <package name>" => Name of the package (default: ${PROJECT_NAME})
#  - "PACKAGE_VERSION <package version>" => Version of the package (default: ${CU_PROJECT_FRIENDLY_VERSION})
#  - "NATIVE_ONLY" => Package native files without a managed assembly or framework dependencies.
#  - "RUNTIME_SUBDIRECTORY <relative directory>" => Directory below runtimes/<RID>/native for the binary and its dependencies (default: empty).
#  - "RUNTIME_FILES <source> <destination directory> ..." => Additional files and their directories relative to runtimes/<RID>/native (use "." for the root; generator expressions supported).
# TODO: Add a new parameter to add more search directories for dependencies (to be added to DEPENDENCIES_SEARCH_DIRS)
function(cu_generate_csharp_nuget_target)
	# Check for cmake minimum version
	cmake_minimum_required(VERSION 3.27) # TARGET_LINKER_FILE added in cmake 3.27

	cmake_parse_arguments(CUGCSNT "NATIVE_ONLY" "TARGET_NAME;CSPROJ_TEMPLATE_PATH;CSPROJ_FILE_NAME;NUGET_SOURCE_URL;NUGET_API_KEY;PACKAGE_NAME;PACKAGE_VERSION;RUNTIME_SUBDIRECTORY" "CS_SOURCE_FOLDERS;CS_PACKAGE_DEPENDENCIES;NUGET_PACK_TARGET_DEPENDENCIES;RUNTIME_FILES" ${ARGN})

	# Check required parameters validity
	if(NOT CUGCSNT_TARGET_NAME)
		message(FATAL_ERROR "TARGET_NAME required")
	endif()
	list(LENGTH CUGCSNT_RUNTIME_FILES runtimeFilesLength)
	math(EXPR runtimeFilesRemainder "${runtimeFilesLength} % 2")
	if(NOT runtimeFilesRemainder EQUAL 0)
		message(FATAL_ERROR "RUNTIME_FILES requires pairs of <source> <destination directory>")
	endif()

	# Default values
	set(CSPROJ_FILE_NAME ${CUGCSNT_TARGET_NAME})
	set(CSPROJ_TEMPLATE_PATH "${CU_GENERATE_CSHARP_NUGET_TARGET_FOLDER}/supportFiles/NugetTemplate.csproj.in")
	set(NUGET_SOURCE_URL "https://api.nuget.org/v3/index.json")
	set(NUGET_API_KEY "")
	set(PACKAGE_NAME ${PROJECT_NAME})
	set(PACKAGE_VERSION ${CU_PROJECT_FRIENDLY_VERSION})
	set(CSPROJ_NATIVE_PROPERTIES "")
	if(CUGCSNT_NATIVE_ONLY)
		set(CSPROJ_NATIVE_PROPERTIES "    <IncludeBuildOutput>false</IncludeBuildOutput>\n    <SuppressDependenciesWhenPacking>true</SuppressDependenciesWhenPacking>")
	endif()
	set(RUNTIME_PACKAGE_PATH "runtimes/${CU_DOTNET_RID_NUGET}/native")
	if(CUGCSNT_RUNTIME_SUBDIRECTORY)
		string(APPEND RUNTIME_PACKAGE_PATH "/${CUGCSNT_RUNTIME_SUBDIRECTORY}")
	endif()

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
	set(PACKAGE_ID "${PACKAGE_NAME}$<$<CONFIG:Debug>:-debug>-${CU_DOTNET_RID_NUGET}")

	# Nuget package name
	set(NUGET_PACKAGE_NAME "${PACKAGE_ID}.${PACKAGE_VERSION}.nupkg")

	# Generate the list of source folders to compile
	set(CSPROJ_COMPILE_ITEMS "")
	foreach(CS_SOURCE_FOLDER ${CUGCSNT_CS_SOURCE_FOLDERS})
		string(APPEND CSPROJ_COMPILE_ITEMS "    <Compile Include=\"${CS_SOURCE_FOLDER}/**/*.cs\" />\n")
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
	get_target_property(targetType ${CUGCSNT_TARGET_NAME} TYPE)
	if(CMAKE_SYSTEM_NAME STREQUAL "Windows" OR targetType STREQUAL "EXECUTABLE" OR targetType STREQUAL "MODULE_LIBRARY")
		# Executables and MODULE libraries have no linker/SONAME artifacts; Windows libraries use their DLL.
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
		"macro(add_runtime_content_item ITEM_PATH PACKAGE_PATH OUTPUT_STRING)\n"
		"\tif(NOT EXISTS \"\${ITEM_PATH}\")\n"
		"\t\tmessage(FATAL_ERROR \"NuGet runtime file does not exist: \${ITEM_PATH}\")\n"
		"\tendif()\n"
		"\tstring(APPEND \${OUTPUT_STRING} \"    <Content Include=\\\"\${ITEM_PATH}\\\">\\n      <Pack>true</Pack>\\n      <PackagePath>\${PACKAGE_PATH}/</PackagePath>\\n    </Content>\\n\")\n"
		"endmacro()\n"
		"\n"
	)
	# Add output folder of the target to the search directories
	string(APPEND GENERATE_CSPROJ_SCRIPT_CONTENT
		"# Add output folder of the target to the search directories\n"
		"list(APPEND DEPENDENCIES_SEARCH_DIRS \"$<TARGET_FILE_DIR:${CUGCSNT_TARGET_NAME}>\")\n"
	)
	# Add the search directories (for debug configuration), skipping the ones that do not exist (e.g. no 'bin' folder with a static vcpkg triplet)
	foreach(DEP_SEARCH_DIR ${depSearchDirsDebug})
		string(APPEND GENERATE_CSPROJ_SCRIPT_CONTENT
			"if(\"$<CONFIG>\" MATCHES \"^([Dd][Ee][Bb][Uu][Gg])$\" AND EXISTS \"${DEP_SEARCH_DIR}\")\n"
			"\tlist(APPEND DEPENDENCIES_SEARCH_DIRS \"${DEP_SEARCH_DIR}\")\n"
			"endif()\n"
		)
	endforeach()
	# Add the search directories (for non-debug configuration), skipping the ones that do not exist
	foreach(DEP_SEARCH_DIR ${depSearchDirsOptimized})
		string(APPEND GENERATE_CSPROJ_SCRIPT_CONTENT
			"if(NOT \"$<CONFIG>\" MATCHES \"^([Dd][Ee][Bb][Uu][Gg])$\" AND EXISTS \"${DEP_SEARCH_DIR}\")\n"
			"\tlist(APPEND DEPENDENCIES_SEARCH_DIRS \"${DEP_SEARCH_DIR}\")\n"
			"endif()\n"
		)
	endforeach()
	# Add the rest of the script
	get_property(cuTargets GLOBAL PROPERTY CU_SHARED_LIBRARY_TARGETS_LIST)
	string(REPLACE ";" "\\;" ESCAPED_CS_PACKAGE_DEPENDENCIES "${CUGCSNT_CS_PACKAGE_DEPENDENCIES}")
	string(REPLACE ";" "\\;" ESCAPED_cuTargets "${cuTargets}")
	string(APPEND GENERATE_CSPROJ_SCRIPT_CONTENT
		"# Define some CMake variables/properties that won't exist anymore during cu_deploy_runtime_binary call from a script file\n"
		"set(CMAKE_SHARED_LIBRARY_PREFIX \"${CMAKE_SHARED_LIBRARY_PREFIX}\")\n" # Required only if passing FAIL_ON_MISSING_TARGET_DEPENDENCY to cu_deploy_runtime_binary
		"set(CMAKE_SHARED_LIBRARY_SUFFIX \"${CMAKE_SHARED_LIBRARY_SUFFIX}\")\n" # Required only if passing FAIL_ON_MISSING_TARGET_DEPENDENCY to cu_deploy_runtime_binary
		"set(CU_SHARED_LIBRARY_TARGETS_LIST ${ESCAPED_cuTargets})\n" # Required only if passing FAIL_ON_MISSING_TARGET_DEPENDENCY to cu_deploy_runtime_binary
		"# Wipe native dependencies folder\n"
		"file(REMOVE_RECURSE \"${CS_NUGET_NATIVES_FOLDER}\")\n"
		"# Deploy runtime dependencies\n"
		"set(COPIED_FILES)\n"
		"cu_deploy_runtime_binary(BINARY_PATH \"${CS_REAL_TARGET_PATH}\" TARGET_DIR \"${CS_NUGET_NATIVES_FOLDER}\" SEARCH_DIRS \${DEPENDENCIES_SEARCH_DIRS} COPIED_FILES_VAR COPIED_FILES)\n"
		"# Add all copied files to the csproj file\n"
		"set(CSPROJ_RUNTIME_ITEMS \"\")\n"
		"# Add target itself in runtime items\n"
		"add_runtime_content_item(\"${CS_TARGET_PATH}\" \"${RUNTIME_PACKAGE_PATH}\" CSPROJ_RUNTIME_ITEMS)\n"
		"# Add each copied file to the runtime items\n"
		"foreach(COPIED_FILE \${COPIED_FILES})\n"
		"\tadd_runtime_content_item(\"\${COPIED_FILE}\" \"${RUNTIME_PACKAGE_PATH}\" CSPROJ_RUNTIME_ITEMS)\n"
		"endforeach()\n"
	)
	if(runtimeFilesLength GREATER 0)
		math(EXPR lastRuntimeFileIndex "${runtimeFilesLength} - 1")
		foreach(index RANGE 0 ${lastRuntimeFileIndex} 2)
			math(EXPR destinationIndex "${index} + 1")
			list(GET CUGCSNT_RUNTIME_FILES ${index} source)
			list(GET CUGCSNT_RUNTIME_FILES ${destinationIndex} destination)
			set(destinationPath "runtimes/${CU_DOTNET_RID_NUGET}/native")
			if(NOT destination STREQUAL ".")
				string(APPEND destinationPath "/${destination}")
			endif()
			string(APPEND GENERATE_CSPROJ_SCRIPT_CONTENT
				"add_runtime_content_item(\"${source}\" \"${destinationPath}\" CSPROJ_RUNTIME_ITEMS)\n"
			)
		endforeach()
	endif()
	string(APPEND GENERATE_CSPROJ_SCRIPT_CONTENT
		"# Generate the list of reference items\n"
		"set(CSPROJ_REFERENCE_ITEMS \"\")\n"
		"set(CS_PACKAGE_DEPENDENCIES ${ESCAPED_CS_PACKAGE_DEPENDENCIES})\n"
		"foreach(CS_DEPENDENCY \${CS_PACKAGE_DEPENDENCIES})\n"
		"\tstring(REPLACE \":\" \"\;\" CS_DEPENDENCY_LIST \${CS_DEPENDENCY})\n"
		"\t# Check list size is 2\n"
		"\tlist(LENGTH CS_DEPENDENCY_LIST CS_DEPENDENCY_LIST_SIZE)\n"
		"\tif(NOT CS_DEPENDENCY_LIST_SIZE EQUAL 2)\n"
		"\t\tmessage(FATAL_ERROR \"Invalid dependency format (Expected: <PackageName>:<Version>): '\${CS_DEPENDENCY}'\")\n"
		"\tendif()\n"
		"\tlist(GET CS_DEPENDENCY_LIST 0 CS_DEPENDENCY_NAME)\n"
		"\tlist(GET CS_DEPENDENCY_LIST 1 CS_DEPENDENCY_VERSION)\n"
		"\t# Append CU_DOTNET_RID_NUGET to the dependency name\n"
		"\tstring(APPEND CS_DEPENDENCY_NAME \"$<$<CONFIG:Debug>:-debug>-${CU_DOTNET_RID_NUGET}\")\n"
		"\tstring(APPEND CSPROJ_REFERENCE_ITEMS \"    <PackageReference Include=\\\"\${CS_DEPENDENCY_NAME}\\\" Version=\\\"\${CS_DEPENDENCY_VERSION}\\\" />\n\")\n"
		"endforeach()\n"
		"# Define PACKAGE_ID variable\n"
		"set(PACKAGE_ID \"${PACKAGE_ID}\")\n"
		"# Configure csproj file (to expand variables again)\n"
		"configure_file(\"${CSPROJ_TEMP_PATH}\" \"${CSPROJ_FINAL_PATH}\")\n"
	)

	# Write the script to a file
	set(GENERATE_CSPROJ_SCRIPT "${CS_NUGET_FOLDER}/generateCSProjet-$<CONFIG>.cmake")
	file(GENERATE
		OUTPUT ${GENERATE_CSPROJ_SCRIPT}
		CONTENT ${GENERATE_CSPROJ_SCRIPT_CONTENT}
	)

	# Print message
	message(STATUS "Generating nuget pack target for ${CUGCSNT_TARGET_NAME}")

	# Add a custom target to generate the csproj file
	add_custom_target(
		${CUGCSNT_TARGET_NAME}-generate-csproj
		COMMAND ${CMAKE_COMMAND} -P ${GENERATE_CSPROJ_SCRIPT}
		WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
		DEPENDS ${CUGCSNT_TARGET_NAME} ${CUGCSNT_NUGET_PACK_TARGET_DEPENDENCIES}
		VERBATIM
	)

	# Generate the list of dependencies
	set(NUGET_PACK_TARGET_DEPENDENCIES "${CUGCSNT_TARGET_NAME}-generate-csproj")
	foreach(TARGET_DEPENDENCY ${CUGCSNT_NUGET_PACK_TARGET_DEPENDENCIES})
		list(APPEND NUGET_PACK_TARGET_DEPENDENCIES ${TARGET_DEPENDENCY})
	endforeach()

	# Add a custom target to pack the nuget
	set(CS_NUPKG_OUTPUT_FOLDER "${CS_NUGET_FOLDER}/bin/$<CONFIG>")
	add_custom_target(
		${CUGCSNT_TARGET_NAME}-nuget-pack
		COMMAND dotnet restore "${CSPROJ_FINAL_PATH}" --ignore-failed-sources
		COMMAND dotnet pack "${CSPROJ_FINAL_PATH}" --no-restore -c $<CONFIG> -o "${CS_NUPKG_OUTPUT_FOLDER}"
		WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
		BYPRODUCTS "${CS_NUPKG_OUTPUT_FOLDER}/${NUGET_PACKAGE_NAME}"
		DEPENDS ${NUGET_PACK_TARGET_DEPENDENCIES}
		VERBATIM
	)

	# Add a custom target to push the nuget
	add_custom_target(
		${CUGCSNT_TARGET_NAME}-nuget-push
		COMMAND dotnet nuget push --interactive -s ${NUGET_SOURCE_URL} ${NUGET_API_KEY} "${CS_NUPKG_OUTPUT_FOLDER}/${NUGET_PACKAGE_NAME}" --skip-duplicate
		WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
		DEPENDS ${CUGCSNT_TARGET_NAME}-nuget-pack
		VERBATIM
	)
endfunction()

########
# Generate a native NuGet package for an executable, MODULE or SHARED library.
# Accepts the same parameters as cu_generate_csharp_nuget_target, without requiring C# sources.
# Creates <TARGET_NAME>-generate-csproj, <TARGET_NAME>-nuget-pack and <TARGET_NAME>-nuget-push.
function(cu_generate_native_nuget_target)
	cu_generate_csharp_nuget_target(NATIVE_ONLY ${ARGN})
endfunction()

########
# Generate a native NuGet package for a plugin (MODULE library) discovered by its host through a manifest file.
# The package content mirrors a host plugins directory, below runtimes/<RID>/native:
#  - "<PLUGINS_FOLDER>/<manifest file>"
#  - "<PLUGINS_FOLDER>/<TARGET_NAME>/<plugin binary and its runtime dependencies>" (the manifest must reference the binary relative to itself, ie. "<TARGET_NAME>/<binary file name>")
# Mandatory parameters:
#  - "TARGET_NAME <target name>" => Plugin target to package. Creates "<TARGET_NAME>-generate-csproj", "<TARGET_NAME>-nuget-pack" and "<TARGET_NAME>-nuget-push".
#  - "MANIFEST <manifest path>" => Path to the plugin manifest file (generator expressions supported).
# Optional parameters:
#  - "PLUGINS_FOLDER <relative directory>" => Directory below runtimes/<RID>/native acting as the host plugins directory (default: plugins).
#  - Any other parameter of cu_generate_native_nuget_target, except RUNTIME_SUBDIRECTORY.
function(cu_generate_plugin_nuget_target)
	cmake_parse_arguments(CUGPNT "" "TARGET_NAME;MANIFEST;PLUGINS_FOLDER;RUNTIME_SUBDIRECTORY" "RUNTIME_FILES" ${ARGN})

	# Check required parameters validity
	if(NOT CUGPNT_TARGET_NAME)
		message(FATAL_ERROR "TARGET_NAME required")
	endif()
	if(NOT CUGPNT_MANIFEST)
		message(FATAL_ERROR "MANIFEST required")
	endif()
	if(CUGPNT_RUNTIME_SUBDIRECTORY)
		message(FATAL_ERROR "RUNTIME_SUBDIRECTORY is not supported, the plugin binary is always packaged in <PLUGINS_FOLDER>/<TARGET_NAME>")
	endif()

	# Default values
	set(pluginsFolder "plugins")
	if(CUGPNT_PLUGINS_FOLDER)
		set(pluginsFolder "${CUGPNT_PLUGINS_FOLDER}")
	endif()

	cu_generate_native_nuget_target(
		TARGET_NAME ${CUGPNT_TARGET_NAME}
		RUNTIME_SUBDIRECTORY "${pluginsFolder}/${CUGPNT_TARGET_NAME}"
		RUNTIME_FILES "${CUGPNT_MANIFEST}" "${pluginsFolder}" ${CUGPNT_RUNTIME_FILES}
		${CUGPNT_UNPARSED_ARGUMENTS}
	)
endfunction()

###############################################################################
### CPack settings for installer
# Mandatory:
#  - cu_setup_project_version_variables() must have been called
#  - CU_INSTALL_LICENSE_FILE_PATH -> Set to the path of the license file to use
#  - CU_INSTALL_ICO_FILE_PATH -> Set to the path of the windows ico file to use
#  - CU_INSTALL_NSIS_WELCOME_FILE_PATH -> Set to the path of the NSIS welcome image to use
#  - CU_INSTALL_PRODUCTBUILD_BACKGROUND_FILE_PATH -> Set to the path of the PRODUCTBUILD background image to use (might be relative if CPACK_PRODUCTBUILD_RESOURCES_DIR is used)
# Optional:
#  - USE_IFW_GENERATOR -> Use IFW os-independent installer for all platforms
#  - USE_DRAGDROP_GENERATOR -> Use d&d on macOS instead of ProductBuild
#  - CU_INSTALL_NSIS_HEADER_FILE_PATH -> Set to the path of the NSIS header image to use (Must be 150x57)
#  - CU_INSTALL_MAIN_EXECUTABLE_NAME -> Set to the name of the main executable to use (defaults to "${PROJECT_NAME}")
# Delegate macros called:
#  - configure_NSIS_extra_commands()
#  - configure_NSIS_extra_components()
#  - configure_PRODUCTBUILD_extra_commands()
#  - configure_PRODUCTBUILD_extra_components()
#  - configure_IFW_extra_commands()
#  - configure_IFW_extra_components()
#  - configure_DragNDrop_extra_commands()

# Avoid multi inclusion of this file
if(CU_CMAKE_INSTALLER_SETTINGS_INCLUDED)
	message("WARNING: CPackConfig already included")
	return()
endif()
set(CU_CMAKE_INSTALLER_SETTINGS_INCLUDED true)

set(CU_CPACK_FOLDER "${CMAKE_CURRENT_LIST_DIR}")

###############################################################################
### Installer usefull macros

###
# Configures the IFW installer
macro(configure_ifw_installer)
	# Sanity checks
	if(NOT DEFINED CU_INSTALL_ICO_FILE_PATH)
		message(FATAL_ERROR "CU_INSTALL_ICO_FILE_PATH must be defined before including CPackConfig.cmake")
	endif()

	if(NOT EXISTS "${CU_INSTALL_ICO_FILE_PATH}")
		message(FATAL_ERROR "Speficied ico file in CU_INSTALL_ICO_FILE_PATH does not exist: ${CU_INSTALL_ICO_FILE_PATH}")
	endif()

	if(NOT WIN32 AND NOT APPLE)
		message(FATAL_ERROR "IFW configuration not yet supported for linux")
	endif()

	# Common settings
	set(CPACK_GENERATOR IFW)
	set(CPACK_IFW_PACKAGE_WIZARD_STYLE "Modern")
	set(CPACK_IFW_PACKAGE_ALLOW_NON_ASCII_CHARACTERS ON)
	set(CPACK_IFW_PACKAGE_ALLOW_SPACE_IN_PATH ON)
	set(CPACK_IFW_PRODUCT_URL "${CU_COMPANY_URL}")
	#set(CPACK_IFW_VERBOSE ON)

	# OS Specific defines
	if(WIN32)
		# Transform / to \ in paths
		string(REPLACE "/" "\\\\" ICO_PATH "${CU_INSTALL_ICO_FILE_PATH}")
		string(REPLACE "/" "\\\\" CPACK_PACKAGE_INSTALL_DIRECTORY "${CPACK_PACKAGE_INSTALL_DIRECTORY}")

		set(CPACK_IFW_PACKAGE_ICON "${ICO_PATH}")
	endif()

	# Add extra commands
	configure_IFW_extra_commands()

	# Include CPack and CPackIFW so we can call cpack_add_component and cpack_ifw_configure_component
	include(CPack REQUIRED)
	include(CPackIFW REQUIRED)

	# Setup the main component
	cpack_add_component(${CMAKE_INSTALL_DEFAULT_COMPONENT_NAME} DISPLAY_NAME "${PROJECT_NAME}" DESCRIPTION "Installs ${PROJECT_NAME}." REQUIRED)
	cpack_ifw_configure_component(${CMAKE_INSTALL_DEFAULT_COMPONENT_NAME} SCRIPT "${CU_CPACK_FOLDER}/ifw/mainComponent.qs" LICENSES "EULA" "${CU_INSTALL_LICENSE_FILE_PATH}" SORTING_PRIORITY 100)

	# Add extra components
	configure_IFW_extra_components()

endmacro()

###
# Adds a file association with an installed binary
# Example: add_installer_file_association("cubin" "MyProg.cubin" "CU Binary File" "bin/MyRes.dll,2" "bin/MyProg.exe")
# This will add the extension ".cubin" to the system, showing the 2nd icon from the binary found in installed path/bin/MyRes.dll, and run the binary found in installed path/bin/MyProg.exe with the file as parameter
function(add_installer_file_association EXTENSION_NAME EXTENSION_CLASS EXTENSION_DESCRIPTION INSTALLED_RELATIVE_ICON_PATH INSTALLED_RELATIVE_BINARY_PATH)

	string(REPLACE "/" "\\\\" RELATIVE_ICON_PATH "${INSTALLED_RELATIVE_ICON_PATH}")
	string(REPLACE "/" "\\\\" RELATIVE_BINARY_PATH "${INSTALLED_RELATIVE_BINARY_PATH}")

	# Add extra install commands
	set(CPACK_NSIS_EXTRA_INSTALL_COMMANDS "${CPACK_NSIS_EXTRA_INSTALL_COMMANDS}\n\
		; Associate the files for ${EXTENSION_CLASS}\n\
		WriteRegStr HKLM \\\"Software\\\\Classes\\\\${EXTENSION_CLASS}\\\" \\\"\\\" \\\"${EXTENSION_DESCRIPTION}\\\"\n\
		WriteRegStr HKLM \\\"Software\\\\Classes\\\\${EXTENSION_CLASS}\\\\DefaultIcon\\\" \\\"\\\" \\\"$INSTDIR\\\\${RELATIVE_ICON_PATH}\\\"\n\
		WriteRegStr HKLM \\\"Software\\\\Classes\\\\${EXTENSION_CLASS}\\\\shell\\\\open\\\" \\\"FriendlyAppName\\\" \\\"${CU_NAME_AND_VERSION}\\\"\n\
		WriteRegStr HKLM \\\"Software\\\\Classes\\\\${EXTENSION_CLASS}\\\\shell\\\\open\\\\command\\\" \\\"\\\" '\\\"$INSTDIR\\\\${RELATIVE_BINARY_PATH}\\\" \\\"%1\\\"'\n\
		WriteRegStr HKLM \\\"Software\\\\Classes\\\\.${EXTENSION_NAME}\\\" \\\"\\\" \\\"${EXTENSION_CLASS}\\\"\n\
		WriteRegStr HKLM \\\"Software\\\\Classes\\\\.${EXTENSION_NAME}\\\\OpenWithProgIds\\\" \\\"${EXTENSION_CLASS}\\\" \\\"\\\"\n"
	PARENT_SCOPE)

	# Add extra uninstall commands
	set(CPACK_NSIS_EXTRA_UNINSTALL_COMMANDS "${CPACK_NSIS_EXTRA_UNINSTALL_COMMANDS}\n\
		; Dissociate the files from ${EXTENSION_CLASS}\n\
		DeleteRegKey HKLM \\\"Software\\\\Classes\\\\${EXTENSION_CLASS}\\\"\n"
	PARENT_SCOPE)
endfunction()

###
# Remove an existing file association
# Example: add_installer_file_unassociation("cubin" "CU Binary File")
# Usefull to remove the association of a binary that was installed by a previous version of the installer
function(add_installer_file_unassociation EXTENSION_NAME EXTENSION_CLASS)

  # Add extra install commands
	set(CPACK_NSIS_EXTRA_INSTALL_COMMANDS "${CPACK_NSIS_EXTRA_INSTALL_COMMANDS}\n\
		; Dissociate the files from ${EXTENSION_CLASS}\n\
		DeleteRegKey HKLM \\\"Software\\\\Classes\\\\${EXTENSION_CLASS}\\\"\n"
	PARENT_SCOPE)
endfunction()

###
# Force a refresh of the icon cache
function(add_installer_refresh_associations)
	# Add extra install commands
	set(CPACK_NSIS_EXTRA_INSTALL_COMMANDS "${CPACK_NSIS_EXTRA_INSTALL_COMMANDS}\n\
		; Refresh the file associations\n\
		!ifdef SHCNE_ASSOCCHANGED\n\
		!undef SHCNE_ASSOCCHANGED\n\
		!endif\n\
		!define SHCNE_ASSOCCHANGED 0x08000000\n\
		!ifdef SHCNF_IDLIST\n\
		!undef SHCNF_IDLIST\n\
		!endif\n\
		!define SHCNF_IDLIST 0\n\
		!ifdef SHCNF_FLUSH\n\
		!undef SHCNF_FLUSH\n\
		!endif\n\
		!define SHCNF_FLUSH 0x1000\n\
		System::Call \\\"shell32::SHChangeNotify(i,i,i,i) v(\\\${SHCNE_ASSOCCHANGED},\\\${SHCNF_IDLIST}|\\\${SHCNF_FLUSH},0,0)\\\"\n"
	PARENT_SCOPE)
	# Add extra uninstall commands
	set(CPACK_NSIS_EXTRA_UNINSTALL_COMMANDS "${CPACK_NSIS_EXTRA_UNINSTALL_COMMANDS}\n\
		; Refresh the file associations\n\
		!ifdef SHCNE_ASSOCCHANGED\n\
		!undef SHCNE_ASSOCCHANGED\n\
		!endif\n\
		!define SHCNE_ASSOCCHANGED 0x08000000\n\
		!ifdef SHCNF_IDLIST\n\
		!undef SHCNF_IDLIST\n\
		!endif\n\
		!define SHCNF_IDLIST 0\n\
		!ifdef SHCNF_FLUSH\n\
		!undef SHCNF_FLUSH\n\
		!endif\n\
		!define SHCNF_FLUSH 0x1000\n\
		System::Call \\\"shell32::SHChangeNotify(i,i,i,i) v(\\\${SHCNE_ASSOCCHANGED},\\\${SHCNF_IDLIST}|\\\${SHCNF_FLUSH},0,0)\\\"\n"
	PARENT_SCOPE)
endfunction()

###############################################################################
### Start of CPack settings

# Sanity checks
if(NOT DEFINED CU_PROJECT_FRIENDLY_VERSION)
	message(FATAL_ERROR "cu_setup_project_version_variables() must be called with your main project version, before including CPackConfig.cmake")
endif()

if(NOT DEFINED CU_INSTALL_LICENSE_FILE_PATH)
	message(FATAL_ERROR "CU_INSTALL_LICENSE_FILE_PATH must be defined before including CPackConfig.cmake")
endif()

if(NOT EXISTS "${CU_INSTALL_LICENSE_FILE_PATH}")
	message(FATAL_ERROR "Specified license file in CU_INSTALL_LICENSE_FILE_PATH does not exist: ${CU_INSTALL_LICENSE_FILE_PATH}")
endif()

if("${CMAKE_INSTALL_DEFAULT_COMPONENT_NAME}" MATCHES " ")
	message(FATAL_ERROR "CMAKE_INSTALL_DEFAULT_COMPONENT_NAME must not contain spaces (defaults to PROJECT_NAME), manually set it before including CPackConfig.cmake")
endif()

# License file
set(CPACK_RESOURCE_FILE_LICENSE "${CU_INSTALL_LICENSE_FILE_PATH}")

# Add the required system libraries
set(CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS_SKIP ON)
include(InstallRequiredSystemLibraries)

# Define variables that include the Marketing version
if(CU_PROJECT_MARKETING_VERSION STREQUAL "")
	set(CU_NAME_AND_VERSION "${PROJECT_NAME}")
	set(CU_INSTALL_DISPLAY_NAME "${PROJECT_NAME} ${CU_PROJECT_FRIENDLY_VERSION}")
	set(CU_DOT_VERSION "")
else()
	set(CU_NAME_AND_VERSION "${PROJECT_NAME} ${CU_PROJECT_MARKETING_VERSION}")
	set(CU_INSTALL_DISPLAY_NAME "${PROJECT_NAME} ${CU_PROJECT_MARKETING_VERSION}")
	set(CU_DOT_VERSION ".${CU_PROJECT_MARKETING_VERSION}")
endif()

# Define the package filename
if(CU_INSTALLER_NAME)
	set(PACKAGE_FILE_NAME "${CU_INSTALLER_NAME}")
else()
	set(PACKAGE_FILE_NAME "${PROJECT_NAME}_Installer_${CU_PROJECT_FRIENDLY_VERSION}")
	string(REPLACE " " "_" PACKAGE_FILE_NAME "${PACKAGE_FILE_NAME}")
endif()

# Define Install Key
if(CU_INSTALL_KEY)
	set(PACKAGE_INSTALL_KEY "${CU_INSTALL_KEY}")
else()
	set(PACKAGE_INSTALL_KEY "${PROJECT_NAME}")
endif()

# Define the main binary name
if(CU_INSTALL_MAIN_EXECUTABLE_NAME)
	set(PACKAGE_MAIN_EXECUTABLE_NAME "${CU_INSTALL_MAIN_EXECUTABLE_NAME}")
else()
	set(PACKAGE_MAIN_EXECUTABLE_NAME "${PROJECT_NAME}")
endif()

# Compute Install Version in the form 0xXXYYZZWW
math(EXPR CU_PROJECT_INSTALL_VERSION "0" OUTPUT_FORMAT HEXADECIMAL)
# Start with the first 3 digits
foreach(index RANGE 0 2)
	list(GET CU_PROJECT_VERSION_SPLIT ${index} LOOP_VERSION)
	if(LOOP_VERSION GREATER 255)
		message(FATAL_ERROR "Version number ${LOOP_VERSION} is too large (max 255)")
	endif()
	math(EXPR CU_PROJECT_INSTALL_VERSION "${CU_PROJECT_INSTALL_VERSION} + (${LOOP_VERSION} << (8 * (3 - ${index})))" OUTPUT_FORMAT HEXADECIMAL)
endforeach()
# If the last digit is 0 (meaning release version), force it to greatest possible value
if(${CU_PROJECT_VERSION_BETA} STREQUAL "0")
	math(EXPR CU_PROJECT_INSTALL_VERSION "${CU_PROJECT_INSTALL_VERSION} + 0xFF" OUTPUT_FORMAT HEXADECIMAL)
else()
	if(CU_PROJECT_VERSION_BETA GREATER 255)
		message(FATAL_ERROR "Version number ${CU_PROJECT_VERSION_BETA} is too large (max 255)")
	endif()
	math(EXPR CU_PROJECT_INSTALL_VERSION "${CU_PROJECT_INSTALL_VERSION} + ${CU_PROJECT_VERSION_BETA}" OUTPUT_FORMAT HEXADECIMAL)
endif()

# Basic settings
set(CPACK_PACKAGE_NAME "${CU_NAME_AND_VERSION}")
set(CPACK_PACKAGE_VENDOR "${CU_COMPANY_NAME}")
set(CPACK_PACKAGE_VERSION "${CU_PROJECT_FRIENDLY_VERSION}")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "${CU_PROJECT_FULL_NAME}")
set(CPACK_PACKAGE_INSTALL_DIRECTORY "${CPACK_PACKAGE_VENDOR}/${PACKAGE_INSTALL_KEY}")
set(CPACK_PACKAGE_FILE_NAME "${PACKAGE_FILE_NAME}")

# Advanced settings
set(CPACK_PACKAGE_EXECUTABLES "${PROJECT_NAME};${CU_NAME_AND_VERSION}")
set(CPACK_PACKAGE_INSTALL_REGISTRY_KEY "${PACKAGE_INSTALL_KEY}")
set(CPACK_CREATE_DESKTOP_LINKS "${PROJECT_NAME}")

if(USE_IFW_GENERATOR)

	configure_ifw_installer()

else()

	# Platform-specific options
	if(WIN32)

		# Sanity checks
		if(NOT DEFINED CU_INSTALL_ICO_FILE_PATH)
			message(FATAL_ERROR "CU_INSTALL_ICO_FILE_PATH must be defined before including CPackConfig.cmake")
		endif()

		if(NOT EXISTS "${CU_INSTALL_ICO_FILE_PATH}")
			message(FATAL_ERROR "Speficied ico file in CU_INSTALL_ICO_FILE_PATH does not exist: ${CU_INSTALL_ICO_FILE_PATH}")
		endif()

		if(NOT DEFINED CU_INSTALL_NSIS_WELCOME_FILE_PATH)
			message(FATAL_ERROR "CU_INSTALL_NSIS_WELCOME_FILE_PATH must be defined before including CPackConfig.cmake")
		endif()

		if(NOT EXISTS "${CU_INSTALL_NSIS_WELCOME_FILE_PATH}")
			message(FATAL_ERROR "Speficied ico file in CU_INSTALL_NSIS_WELCOME_FILE_PATH does not exist: ${CU_INSTALL_NSIS_WELCOME_FILE_PATH}")
		endif()

		set(CPACK_GENERATOR NSIS)

		# Set CMake module path to our own nsis template so it's used during generation
		set(CMAKE_MODULE_PATH ${CU_CPACK_FOLDER}/nsis ${CMAKE_MODULE_PATH})

		# Configure file with custom definitions for NSIS.
		configure_file(
			${CU_CPACK_FOLDER}/nsis/NSIS.definitions.nsh.in
			${CU_TOP_LEVEL_BINARY_DIR}/NSIS.definitions.nsh
		)

		# NSIS settings
		string(REPLACE "/" "\\\\" ICO_PATH "${CU_INSTALL_ICO_FILE_PATH}")
		string(REPLACE "/" "\\\\" WELCOME_BMP "${CU_INSTALL_NSIS_WELCOME_FILE_PATH}")
		if(DEFINED CU_INSTALL_NSIS_HEADER_FILE_PATH AND EXISTS "${CU_INSTALL_NSIS_HEADER_FILE_PATH}")
			string(REPLACE "/" "\\\\" CPACK_PACKAGE_ICON "${CU_INSTALL_NSIS_HEADER_FILE_PATH}")
		endif()

		# Transform / to \ in paths
		string(REPLACE "/" "\\\\" CPACK_PACKAGE_INSTALL_DIRECTORY "${CPACK_PACKAGE_INSTALL_DIRECTORY}")

		# Common settings
		set(CPACK_NSIS_COMPRESSOR "/SOLID LZMA")
		set(CPACK_NSIS_ENABLE_UNINSTALL_BEFORE_INSTALL ON)
		set(CPACK_NSIS_PACKAGE_NAME "${CPACK_PACKAGE_NAME}") # Name to be shown in the title bar of the installer
		set(CPACK_NSIS_DISPLAY_NAME "${CU_INSTALL_DISPLAY_NAME}") # Name to be shown in Windows Add/Remove Program control panel
		set(CPACK_NSIS_INSTALLED_ICON_NAME "bin/${PACKAGE_MAIN_EXECUTABLE_NAME}.exe") # Icon to be shown in Windows Add/Remove Program control panel
		set(CPACK_NSIS_HELP_LINK "${CU_COMPANY_URL}")
		set(CPACK_NSIS_URL_INFO_ABOUT "${CU_COMPANY_URL}")
		set(CPACK_NSIS_CONTACT "${CU_PROJECT_CONTACT}")

		# Visuals during installation and uninstallation
		set(CPACK_NSIS_INSTALLER_MUI_ICON_CODE "\
			!define MUI_ICON \\\"${ICO_PATH}\\\"\n\
			!define MUI_UNICON \\\"${ICO_PATH}\\\"\n\
			!define MUI_WELCOMEFINISHPAGE_BITMAP \\\"${WELCOME_BMP}\\\"\n\
			!define MUI_UNWELCOMEFINISHPAGE_BITMAP \\\"${WELCOME_BMP}\\\"\n\
			!define MUI_WELCOMEFINISHPAGE_BITMAP_NOSTRETCH\n\
			!define MUI_UNWELCOMEFINISHPAGE_BITMAP_NOSTRETCH\n\
			!define MUI_WELCOMEPAGE_TITLE_3LINES\n\
			!define MUI_HEADERIMAGE_RIGHT\n\
			!define MUI_STARTMENUPAGE_DEFAULTFOLDER \\\"${PACKAGE_INSTALL_KEY}\\\"\n\
			BrandingText \\\"${CPACK_PACKAGE_VENDOR} ${PROJECT_NAME}\\\"\n\
		")

		# Add shortcuts during install
		set(CPACK_NSIS_CREATE_ICONS_EXTRA "\
			CreateShortCut \\\"$DESKTOP\\\\${CU_NAME_AND_VERSION}.lnk\\\" \\\"$INSTDIR\\\\bin\\\\${PACKAGE_MAIN_EXECUTABLE_NAME}.exe\\\" \\\"\\\""
		)

		# Remove shortcuts during uninstall
		set(CPACK_NSIS_DELETE_ICONS_EXTRA "\
			Delete \\\"$DESKTOP\\\\${CU_NAME_AND_VERSION}.lnk\\\""
		)

		# Add a finish page to run the program
		set(CPACK_NSIS_MUI_FINISHPAGE_RUN "${PACKAGE_MAIN_EXECUTABLE_NAME}.exe")

		# Add extra commands
		configure_NSIS_extra_commands()

		# Include CPack so we can call cpack_add_component
		include(CPack REQUIRED)

		# Setup components
		cpack_add_component(${CMAKE_INSTALL_DEFAULT_COMPONENT_NAME} DISPLAY_NAME "${PROJECT_NAME}" DESCRIPTION "Installs ${PROJECT_NAME}." REQUIRED)

		# Add extra components
		configure_NSIS_extra_components()

	elseif(APPLE)

		if(NOT USE_DRAGDROP_GENERATOR)

			# Sanity checks
			if(NOT DEFINED CU_INSTALL_PRODUCTBUILD_BACKGROUND_FILE_PATH)
				message(FATAL_ERROR "CU_INSTALL_PRODUCTBUILD_BACKGROUND_FILE_PATH must be defined before including CPackConfig.cmake")
			endif()

			set(CPACK_GENERATOR productbuild)

			# Set CMake module path to our own cpack template so it's used during generation
			set(CMAKE_MODULE_PATH ${CU_CPACK_FOLDER}/productbuild ${CMAKE_MODULE_PATH})

			set(CPACK_PRODUCTBUILD_BACKGROUND "${CU_INSTALL_PRODUCTBUILD_BACKGROUND_FILE_PATH}")
			set(CPACK_PRODUCTBUILD_BACKGROUND_ALIGNMENT "bottomleft")
			set(CPACK_PRODUCTBUILD_BACKGROUND_SCALING "proportional")
			set(CPACK_PRODUCTBUILD_BACKGROUND_MIME_TYPE "image/png")
			set(CPACK_PRODUCTBUILD_BACKGROUND_DARKAQUA "background.png")
			set(CPACK_PRODUCTBUILD_BACKGROUND_DARKAQUA_ALIGNMENT "bottomleft")
			set(CPACK_PRODUCTBUILD_BACKGROUND_DARKAQUA_SCALING "proportional")
			set(CPACK_PRODUCTBUILD_BACKGROUND_DARKAQUA_MIME_TYPE "image/png")
			set(CPACK_PRODUCTBUILD_IDENTITY_NAME "${CU_INSTALLER_SIGNING_IDENTITY}")
			set(CPACK_PKGBUILD_IDENTITY_NAME "${CU_INSTALLER_SIGNING_IDENTITY}")

			string(REGEX REPLACE "([][+.*()^])" "\\\\\\1" ESCAPED_IDENTITY "${CU_INSTALLER_SIGNING_IDENTITY}")

			# Define some variables required for configure_file and custom_command
			set(CU_PACKAGE_BASE_ID "${CU_COMPANY_DOMAIN}.${CU_PROJECT_COMPANYNAME}.${CPACK_PACKAGE_NAME}")
			set(MAIN_COMPONENT_ID "${CU_PACKAGE_BASE_ID}.${CMAKE_INSTALL_DEFAULT_COMPONENT_NAME}")
			set(MAIN_COMPONENT_UNINSTALLER_ID "${MAIN_COMPONENT_ID}.uninstaller")
			set(MAIN_COMPONENT_UNINSTALLER_PKG_ID "${MAIN_COMPONENT_ID}.uninstaller.pkg")
			set(APP_SUPPORT_FOLDER "/Library/Application Support/${CU_PROJECT_COMPANYNAME}/${CPACK_PACKAGE_NAME}")

			# Create uninstall package
			set(UNINSTALL_PROJECT_GENERATED_PKG "${CMAKE_BINARY_DIR}/uninstaller.pkg")
			configure_file("${CU_CPACK_FOLDER}/productbuild/uninstaller/postinstall.in"	"${CMAKE_BINARY_DIR}/uninstaller/install-scripts/postinstall" @ONLY)
			add_custom_command(OUTPUT "${UNINSTALL_PROJECT_GENERATED_PKG}"
				COMMAND pkgbuild
					--identifier ${MAIN_COMPONENT_UNINSTALLER_PKG_ID}
					--version 1.0
					--nopayload
					--sign ${ESCAPED_IDENTITY}
					--scripts "${CMAKE_BINARY_DIR}/uninstaller/install-scripts/"
					"${UNINSTALL_PROJECT_GENERATED_PKG}"
				DEPENDS
					"${CU_CPACK_FOLDER}/productbuild/uninstaller/postinstall.in"
					"${CMAKE_BINARY_DIR}/uninstaller/install-scripts/postinstall"
			)
			set(UNINSTALL_PROJECT_GENERATED_PRODUCT "${CMAKE_BINARY_DIR}/Uninstall ${CPACK_PACKAGE_NAME}.pkg")
			configure_file("${CU_CPACK_FOLDER}/productbuild/uninstaller/install-distribution.xml.in" "${CMAKE_BINARY_DIR}/uninstaller/install-distribution.xml" @ONLY)
			add_custom_command(OUTPUT "${UNINSTALL_PROJECT_GENERATED_PRODUCT}"
				COMMAND productbuild
					--identifier ${MAIN_COMPONENT_UNINSTALLER_ID}.product
					--version 1.0
					--sign ${ESCAPED_IDENTITY}
					--distribution "${CMAKE_BINARY_DIR}/uninstaller/install-distribution.xml"
					--package-path "${CMAKE_BINARY_DIR}"
					${UNINSTALL_PROJECT_GENERATED_PRODUCT}
				DEPENDS
					"${CU_CPACK_FOLDER}/productbuild/uninstaller/install-distribution.xml.in"
					"${CMAKE_BINARY_DIR}/uninstaller/install-distribution.xml"
					${UNINSTALL_PROJECT_GENERATED_PKG}
			)
			add_custom_target(uninstall_pkg ALL DEPENDS "${UNINSTALL_PROJECT_GENERATED_PRODUCT}")
			install(PROGRAMS "${UNINSTALL_PROJECT_GENERATED_PRODUCT}" DESTINATION "${MACOS_INSTALL_FOLDER}")

			# Add extra commands
			configure_PRODUCTBUILD_extra_commands()

			# Include CPack so we can call cpack_add_component
			include(CPack REQUIRED)

			# Setup components
			cpack_add_component(${CMAKE_INSTALL_DEFAULT_COMPONENT_NAME} DISPLAY_NAME "${PROJECT_NAME}" DESCRIPTION "Installs ${PROJECT_NAME}." REQUIRED)

			# Add extra components
			configure_PRODUCTBUILD_extra_components()

		else()

			find_file(CPACK_PACKAGE_ICON VolumeIcon.icns PATHS dragndrop NO_DEFAULT_PATH)
			set(CPACK_GENERATOR DragNDrop)
			set(CPACK_DMG_FORMAT UDBZ)
			find_file(CPACK_DMG_DS_STORE DS_Store PATHS dragndrop NO_DEFAULT_PATH)

			# Add extra commands
			configure_DragNDrop_extra_commands()

			include(CPack REQUIRED)

		endif()

	endif()

endif()

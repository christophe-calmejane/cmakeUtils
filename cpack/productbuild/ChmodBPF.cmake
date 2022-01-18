# ChmodBPF

# Avoid multi inclusion of this file (cannot use include_guard as multiple copies of this file are included from multiple places)
if(CU_CHMODBPF_INCLUDED)
	return()
endif()
set(CU_CHMODBPF_INCLUDED true)

# Some variables
set(CU_CHMODBPF_DIR ${CMAKE_CURRENT_LIST_DIR})
set(CHMODBPF_NAME "ChmodBPF")
set(CU_CHMODBPF_PKG_SRC_DIR ${CU_CHMODBPF_DIR}/${CHMODBPF_NAME})
set(CU_CHMODBPF_PKG_OUT_DIR ${CMAKE_BINARY_DIR}/${CHMODBPF_NAME})

macro(cu_chmodbpf_extra_commands)
	string(TOUPPER "${CHMODBPF_NAME}" CHMODBPF_NAME_UPPER)
	set(CPACK_POSTFLIGHT_${CHMODBPF_NAME_UPPER}_SCRIPT "${CU_CHMODBPF_PKG_OUT_DIR}/auto-install.sh")
endmacro()

macro(cu_chmodbpf_add_component)
	# Define some variables required for configure_file and custom_command
	set(CHMODBPF_ID "${CU_COMPANY_DOMAIN}.${CU_PROJECT_COMPANYNAME}.${CPACK_PACKAGE_NAME}.${CHMODBPF_NAME}")
	set(CHMODBPF_PKG_ID "${CHMODBPF_ID}.pkg")
	set(CHMODBPF_UNINSTALLER_ID "${CHMODBPF_ID}.uninstaller")
	set(CHMODBPF_UNINSTALLER_PKG_ID "${CHMODBPF_ID}.uninstaller.pkg")
	set(LAUNCH_DAEMON_CHMODBPF_PLIST "/Library/LaunchDaemons/${CHMODBPF_ID}.plist")
	set(APP_SUPPORT_FOLDER "/Library/Application Support/${CU_PROJECT_COMPANYNAME}/${CPACK_PACKAGE_NAME}")
	set(APP_SUPPORT_CHMODBPF_FOLDER "${APP_SUPPORT_FOLDER}/${CHMODBPF_NAME}")
	set(APP_SUPPORT_CHMODBPF_SCRIPT "${APP_SUPPORT_CHMODBPF_FOLDER}/${CHMODBPF_NAME}")

	# Create ChmodBPF install package
	set(INSTALL_CHMODBPF_GENERATED_PKG "${CMAKE_BINARY_DIR}/install.${CHMODBPF_NAME}.pkg")
	configure_file("${CU_CHMODBPF_PKG_SRC_DIR}/install-scripts/postinstall.in" "${CU_CHMODBPF_PKG_OUT_DIR}/install-scripts/postinstall" @ONLY)
	configure_file("${CU_CHMODBPF_PKG_SRC_DIR}/${CHMODBPF_NAME}.plist.in" "${CU_CHMODBPF_PKG_OUT_DIR}/root${LAUNCH_DAEMON_CHMODBPF_PLIST}" @ONLY)
	configure_file("${CU_CHMODBPF_PKG_SRC_DIR}/${CHMODBPF_NAME}" "${CU_CHMODBPF_PKG_OUT_DIR}/root${APP_SUPPORT_CHMODBPF_SCRIPT}" COPYONLY)
	add_custom_command(OUTPUT "${INSTALL_CHMODBPF_GENERATED_PKG}"
		COMMAND find
			"${CU_CHMODBPF_PKG_OUT_DIR}/root"
			-type d
			-exec chmod 755 "{}" +
		COMMAND chmod 644
			"${CU_CHMODBPF_PKG_OUT_DIR}/root${LAUNCH_DAEMON_CHMODBPF_PLIST}"
		COMMAND chmod 755
			"${CU_CHMODBPF_PKG_OUT_DIR}/root${APP_SUPPORT_CHMODBPF_SCRIPT}"
		COMMAND pkgbuild
			--identifier ${CHMODBPF_PKG_ID}
			--version 1.1
			--preserve-xattr
			--root "${CU_CHMODBPF_PKG_OUT_DIR}/root"
			--sign ${ESCAPED_IDENTITY}
			--scripts "${CU_CHMODBPF_PKG_OUT_DIR}/install-scripts"
			${INSTALL_CHMODBPF_GENERATED_PKG}
		DEPENDS
			"${CU_CHMODBPF_PKG_OUT_DIR}/root${APP_SUPPORT_CHMODBPF_SCRIPT}"
			"${CU_CHMODBPF_PKG_OUT_DIR}/root${LAUNCH_DAEMON_CHMODBPF_PLIST}"
			"${CU_CHMODBPF_PKG_OUT_DIR}/install-scripts/postinstall"
	)
	set(INSTALL_CHMODBPF_GENERATED_PRODUCT "${CMAKE_BINARY_DIR}/Install ${CHMODBPF_NAME}.pkg")
	configure_file("${CU_CHMODBPF_PKG_SRC_DIR}/install-distribution.xml.in" "${CU_CHMODBPF_PKG_OUT_DIR}/install-distribution.xml" @ONLY)
	add_custom_command(OUTPUT "${INSTALL_CHMODBPF_GENERATED_PRODUCT}"
		COMMAND productbuild
		--identifier ${CHMODBPF_ID}.product
		--version 1.1
		--sign ${ESCAPED_IDENTITY}
		--distribution "${CU_CHMODBPF_PKG_OUT_DIR}/install-distribution.xml"
		--package-path "${CMAKE_BINARY_DIR}"
		${INSTALL_CHMODBPF_GENERATED_PRODUCT}
	DEPENDS
		"${CU_CHMODBPF_PKG_OUT_DIR}/install-distribution.xml"
		${INSTALL_CHMODBPF_GENERATED_PKG}
	)
	add_custom_target(install_chmodbpf_pkg ALL DEPENDS "${INSTALL_CHMODBPF_GENERATED_PRODUCT}")
	install(PROGRAMS "${INSTALL_CHMODBPF_GENERATED_PRODUCT}" DESTINATION "${MACOS_INSTALL_FOLDER}/${CHMODBPF_NAME}" CONFIGURATIONS Release COMPONENT ${CHMODBPF_NAME})

	# Create ChmodBPF uninstall package
	set(UNINSTALL_CHMODBPF_GENERATED_PKG "${CMAKE_BINARY_DIR}/uninstall.${CHMODBPF_NAME}.pkg")
	configure_file("${CU_CHMODBPF_PKG_SRC_DIR}/uninstall-scripts/postinstall.in" "${CU_CHMODBPF_PKG_OUT_DIR}/uninstall-scripts/postinstall" @ONLY)
	add_custom_command(OUTPUT "${UNINSTALL_CHMODBPF_GENERATED_PKG}"
		COMMAND pkgbuild
			--identifier ${CHMODBPF_UNINSTALLER_PKG_ID}
			--version 1.1
			--nopayload
			--sign ${ESCAPED_IDENTITY}
			--scripts "${CU_CHMODBPF_PKG_OUT_DIR}/uninstall-scripts"
			${UNINSTALL_CHMODBPF_GENERATED_PKG}
		DEPENDS
			"${CU_CHMODBPF_PKG_OUT_DIR}/uninstall-scripts/postinstall"
	)
	set(UNINSTALL_CHMODBPF_GENERATED_PRODUCT "${CMAKE_BINARY_DIR}/Uninstall ${CHMODBPF_NAME}.pkg")
	configure_file("${CU_CHMODBPF_PKG_SRC_DIR}/uninstall-distribution.xml.in" "${CU_CHMODBPF_PKG_OUT_DIR}/uninstall-distribution.xml" @ONLY)
	add_custom_command(OUTPUT "${UNINSTALL_CHMODBPF_GENERATED_PRODUCT}"
		COMMAND productbuild
		--identifier ${CHMODBPF_UNINSTALLER_ID}.product
		--version 1.1
		--sign ${ESCAPED_IDENTITY}
		--distribution "${CU_CHMODBPF_PKG_OUT_DIR}/uninstall-distribution.xml"
		--package-path "${CMAKE_BINARY_DIR}"
		${UNINSTALL_CHMODBPF_GENERATED_PRODUCT}
	DEPENDS
		"${CU_CHMODBPF_PKG_OUT_DIR}/uninstall-distribution.xml"
		${UNINSTALL_CHMODBPF_GENERATED_PKG}
	)
	add_custom_target(uninstall_chmodbpf_pkg ALL DEPENDS "${UNINSTALL_CHMODBPF_GENERATED_PRODUCT}")
	install(PROGRAMS "${UNINSTALL_CHMODBPF_GENERATED_PRODUCT}" DESTINATION "${MACOS_INSTALL_FOLDER}/${CHMODBPF_NAME}" CONFIGURATIONS Release COMPONENT ${CHMODBPF_NAME})

	# Add a CPack component for the ChmodBPF packages
	cpack_add_component(${CHMODBPF_NAME} DISPLAY_NAME "Chmod BPF" DESCRIPTION "This package will install the ChmodBPF launch daemon, create the access_bpf group, and add you to that group.")

	# Configure other files required by cu_chmodbpf_extra_commands
	configure_file("${CU_CHMODBPF_PKG_SRC_DIR}/auto-install.sh.in" "${CU_CHMODBPF_PKG_OUT_DIR}/auto-install.sh" @ONLY)
	# configure_file("${CU_CHMODBPF_PKG_SRC_DIR}/auto-uninstall.sh.in" "${CU_CHMODBPF_PKG_OUT_DIR}/auto-uninstall.sh" @ONLY) # Currently not being used. Designed to be called by the uninstaller, but requires some modifications in the uninstall script to call this one somehow.
endmacro()

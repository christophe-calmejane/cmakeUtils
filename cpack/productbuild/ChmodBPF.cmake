# ChmodBPF

# Avoid multi inclusion of this file (cannot use include_guard as multiple copies of this file are included from multiple places)
if(CU_CHMODBPF_INCLUDED)
	return()
endif()
set(CU_CHMODBPF_INCLUDED true)

function(cu_chmodbpf_add_component)
	# Some variables
	set(CHMODBPF_NAME "ChmodBPF")
	set(CU_CHMODBPF_PKG_SRC_DIR ${CMAKE_CURRENT_FUNCTION_LIST_DIR}/${CHMODBPF_NAME})
	set(CU_CHMODBPF_PKG_OUT_DIR ${CMAKE_BINARY_DIR}/${CHMODBPF_NAME})
	
	# Build ChmodBPF PKG tree
	configure_file("${CU_CHMODBPF_PKG_SRC_DIR}/install-distribution.xml.in" "${CU_CHMODBPF_PKG_OUT_DIR}/install-distribution.xml")
	configure_file("${CU_CHMODBPF_PKG_SRC_DIR}/uninstall-distribution.xml.in" "${CU_CHMODBPF_PKG_OUT_DIR}/uninstall-distribution.xml")
	configure_file("${CU_CHMODBPF_PKG_SRC_DIR}/install-scripts/postinstall.in" "${CU_CHMODBPF_PKG_OUT_DIR}/install-scripts/postinstall")
	configure_file("${CU_CHMODBPF_PKG_SRC_DIR}/uninstall-scripts/postinstall.in" "${CU_CHMODBPF_PKG_OUT_DIR}/uninstall-scripts/postinstall")
	configure_file("${CU_CHMODBPF_PKG_SRC_DIR}/${CHMODBPF_NAME}.plist.in" "${CU_CHMODBPF_PKG_OUT_DIR}/root/Library/LaunchDaemons/${CU_COMPANY_DOMAIN}.${CU_PROJECT_COMPANYNAME}.${CMAKE_INSTALL_DEFAULT_COMPONENT_NAME}.${CHMODBPF_NAME}.plist")
	configure_file("${CU_CHMODBPF_PKG_SRC_DIR}/${CHMODBPF_NAME}" "${CU_CHMODBPF_PKG_OUT_DIR}/root/Library/Application Support/${CU_PROJECT_COMPANYNAME}/${PROJECT_NAME}/${CHMODBPF_NAME}/${CHMODBPF_NAME}" COPYONLY)

	# Create ChmodBPF install package
	set(INSTALL_CHMODBPF_GENERATED_PKG "${CMAKE_BINARY_DIR}/install.${CHMODBPF_NAME}.pkg")
	add_custom_command(OUTPUT "${INSTALL_CHMODBPF_GENERATED_PKG}"
		COMMAND find
			"${CU_CHMODBPF_PKG_OUT_DIR}/root"
			-type d
			-exec chmod 755 "{}" +
		COMMAND chmod 644
			"${CU_CHMODBPF_PKG_OUT_DIR}/root/Library/LaunchDaemons/${CU_COMPANY_DOMAIN}.${CU_PROJECT_COMPANYNAME}.${CMAKE_INSTALL_DEFAULT_COMPONENT_NAME}.${CHMODBPF_NAME}.plist"
		COMMAND chmod 755
			"${CU_CHMODBPF_PKG_OUT_DIR}/root/Library/Application Support/${CU_PROJECT_COMPANYNAME}/${PROJECT_NAME}/${CHMODBPF_NAME}/${CHMODBPF_NAME}"
		COMMAND pkgbuild
			--identifier ${CU_COMPANY_DOMAIN}.${CU_PROJECT_COMPANYNAME}.${CMAKE_INSTALL_DEFAULT_COMPONENT_NAME}.${CHMODBPF_NAME}.pkg
			--version 1.1
			--preserve-xattr
			--root "${CU_CHMODBPF_PKG_OUT_DIR}/root"
			--sign ${ESCAPED_IDENTITY}
			--scripts "${CU_CHMODBPF_PKG_OUT_DIR}/install-scripts"
			${INSTALL_CHMODBPF_GENERATED_PKG}
		DEPENDS
			"${CU_CHMODBPF_PKG_OUT_DIR}/root/Library/Application Support/${CU_PROJECT_COMPANYNAME}/${PROJECT_NAME}/${CHMODBPF_NAME}/${CHMODBPF_NAME}"
			"${CU_CHMODBPF_PKG_OUT_DIR}/root/Library/LaunchDaemons/${CU_COMPANY_DOMAIN}.${CU_PROJECT_COMPANYNAME}.${CMAKE_INSTALL_DEFAULT_COMPONENT_NAME}.${CHMODBPF_NAME}.plist"
			"${CU_CHMODBPF_PKG_OUT_DIR}/install-scripts/postinstall"
	)
	set(INSTALL_CHMODBPF_GENERATED_PRODUCT "${CMAKE_BINARY_DIR}/Install ${CHMODBPF_NAME}.pkg")
	add_custom_command(OUTPUT "${INSTALL_CHMODBPF_GENERATED_PRODUCT}"
		COMMAND productbuild
		--identifier ${CU_COMPANY_DOMAIN}.${CU_PROJECT_COMPANYNAME}.${CMAKE_INSTALL_DEFAULT_COMPONENT_NAME}.${CHMODBPF_NAME}.product
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
	install(PROGRAMS "${INSTALL_CHMODBPF_GENERATED_PRODUCT}" DESTINATION "${MACOS_INSTALL_FOLDER}" CONFIGURATIONS Release)

	# Create ChmodBPF uninstall package
	set(UNINSTALL_CHMODBPF_GENERATED_PKG "${CMAKE_BINARY_DIR}/uninstall.${CHMODBPF_NAME}.pkg")
	add_custom_command(OUTPUT "${UNINSTALL_CHMODBPF_GENERATED_PKG}"
		COMMAND pkgbuild
			--identifier ${CU_COMPANY_DOMAIN}.${CU_PROJECT_COMPANYNAME}.${CMAKE_INSTALL_DEFAULT_COMPONENT_NAME}.${CHMODBPF_NAME}.pkg
			--version 1.1
			--nopayload
			--sign ${ESCAPED_IDENTITY}
			--scripts "${CU_CHMODBPF_PKG_OUT_DIR}/uninstall-scripts"
			${UNINSTALL_CHMODBPF_GENERATED_PKG}
		DEPENDS
			"${CU_CHMODBPF_PKG_OUT_DIR}/uninstall-scripts/postinstall"
	)
	set(UNINSTALL_CHMODBPF_GENERATED_PRODUCT "${CMAKE_BINARY_DIR}/Uninstall ${CHMODBPF_NAME}.pkg")
	add_custom_command(OUTPUT "${UNINSTALL_CHMODBPF_GENERATED_PRODUCT}"
		COMMAND productbuild
		--identifier ${CU_COMPANY_DOMAIN}.${CU_PROJECT_COMPANYNAME}.${CMAKE_INSTALL_DEFAULT_COMPONENT_NAME}.${CHMODBPF_NAME}.product
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
	install(PROGRAMS "${UNINSTALL_CHMODBPF_GENERATED_PRODUCT}" DESTINATION "${MACOS_INSTALL_FOLDER}" CONFIGURATIONS Release)

endfunction()

# ChmodBPF

# Avoid multi inclusion of this file (cannot use include_guard as multiple copies of this file are included from multiple places)
if(CU_CHMODBPF_INCLUDED)
	return()
endif()
set(CU_CHMODBPF_INCLUDED true)

function(cu_chmodbpf_add_component)
	# Some variables
	set(CHMODBPF_NAME "ChmodBPF")
	set(CU_CHMODBPF_PKG_SRC_DIR ${CMAKE_CURRENT_LIST_DIR}/${CHMODBPF_NAME})
	set(CU_CHMODBPF_PKG_OUT_DIR ${CMAKE_BINARY_DIR}/${CHMODBPF_NAME})
	
	# Build ChmodBPF PKG tree
	configure_file("${CU_CHMODBPF_PKG_SRC_DIR}/install-distribution.xml.in" "${CU_CHMODBPF_PKG_OUT_DIR}/install-distribution.xml")
	configure_file("${CU_CHMODBPF_PKG_SRC_DIR}/uninstall-distribution.xml.in" "${CU_CHMODBPF_PKG_OUT_DIR}/uninstall-distribution.xml")
	configure_file("${CU_CHMODBPF_PKG_SRC_DIR}/install-scripts/postinstall.in" "${CU_CHMODBPF_PKG_OUT_DIR}/install-scripts/postinstall" -t 755)
	configure_file("${CU_CHMODBPF_PKG_SRC_DIR}/uninstall-scripts/postinstall.in" "${CU_CHMODBPF_PKG_OUT_DIR}/uninstall-scripts/postinstall" -t 755)
	configure_file("${CU_CHMODBPF_PKG_SRC_DIR}/${CHMODBPF_NAME}.plist.in" "${CU_CHMODBPF_PKG_OUT_DIR}/root/Library/LaunchDaemons/${CU_COMPANY_DOMAIN}.${CU_PROJECT_COMPANYNAME}.${CMAKE_INSTALL_DEFAULT_COMPONENT_NAME}.${CHMODBPF_NAME}.plist")
	configure_file("${CU_CHMODBPF_PKG_SRC_DIR}/${CHMODBPF_NAME}" "${CU_CHMODBPF_PKG_OUT_DIR}/root/Library/Application Support/@PROJECT_NAME@/${CHMODBPF_NAME}/${CHMODBPF_NAME}" -t 755 COPY_ONLY)


endfunction()

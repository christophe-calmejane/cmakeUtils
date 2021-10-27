if(NOT CU_PROJECT_FULL_NAME)
	set(CU_PROJECT_FULL_NAME "${PROJECT_NAME}")
	message(STATUS "CU_PROJECT_FULL_NAME not set, using default value: ${PROJECT_NAME}")
endif()
if(NOT CU_COMPANY_NAME)
	message(FATAL_ERROR "Required variable CU_COMPANY_NAME not defined before including ProjectProperties.cmake")
endif()
if(NOT CU_COMPANY_DOMAIN)
	set(CU_COMPANY_DOMAIN "com")
	message(STATUS "CU_COMPANY_DOMAIN not set, using default value: ${CU_COMPANY_DOMAIN}")
endif()
string(TOLOWER "${CU_COMPANY_NAME}.${CU_COMPANY_DOMAIN}" CU_DOMAIN_NAME)
string(TOLOWER "${CU_COMPANY_DOMAIN}.${CU_COMPANY_NAME}" CU_REVERSE_DOMAIN_NAME)
if(NOT CU_COMPANY_URL)
	set(CU_COMPANY_URL "https://www.${CU_DOMAIN_NAME}" CU_COMPANY_URL)
	message(STATUS "CU_COMPANY_URL not set, using default value: ${CU_COMPANY_URL}")
endif()
if(NOT CU_PROJECT_URLABOUTINFO)
	set(CU_PROJECT_URLABOUTINFO "${CU_COMPANY_URL}")
	message(STATUS "CU_PROJECT_URLABOUTINFO not set, using default value: ${CU_PROJECT_URLABOUTINFO}")
endif()
if(NOT CU_PROJECT_CONTACT)
	string(TOLOWER "${PROJECT_NAME}@${CU_COMPANY_NAME}.com" CU_PROJECT_CONTACT)
	message(STATUS "CU_PROJECT_CONTACT not set, using default value: ${CU_PROJECT_CONTACT}")
endif()
if(NOT CU_PROJECT_PRODUCTDESCRIPTION)
	message(FATAL_ERROR "Required variable CU_PROJECT_PRODUCTDESCRIPTION not defined before including ProjectProperties.cmake")
endif()
if(NOT CU_PROJECT_STARTING_YEAR)
	message(FATAL_ERROR "Required variable CU_PROJECT_STARTING_YEAR not defined before including ProjectProperties.cmake")
endif()
if(NOT CU_COPYRIGHT_HOLDER)
	set(CU_COPYRIGHT_HOLDER "${CU_COMPANY_NAME}")
	message(STATUS "CU_COPYRIGHT_HOLDER not set, using default value: ${CU_COMPANY_NAME}")
endif()

if(CMAKE_HOST_APPLE)
	if(ENABLE_CODE_SIGNING)
		if("${CMAKE_GENERATOR}" STREQUAL "Xcode" AND NOT CU_TEAM_IDENTIFIER)
			message(FATAL_ERROR "Required variable (CU_TEAM_IDENTIFIER) not defined before including ProjectProperties.cmake")
		endif()
		if(NOT CU_BINARY_SIGNING_IDENTITY)
			message(FATAL_ERROR "Required variable (CU_BINARY_SIGNING_IDENTITY) not defined before including ProjectProperties.cmake")
		endif()
		if(NOT CU_INSTALLER_SIGNING_IDENTITY)
			message(FATAL_ERROR "Required variable (CU_INSTALLER_SIGNING_IDENTITY) not defined before including ProjectProperties.cmake")
		endif()
	endif()
endif()

if(WIN32)
	if(ENABLE_CODE_SIGNING AND NOT CU_SIGNTOOL_OPTIONS)
		message(FATAL_ERROR "Required variable (CU_SIGNTOOL_OPTIONS) not defined before including ProjectProperties.cmake")
	endif()
	find_program(DOT_PROGRAM "dot")
	if(NOT DOT_PROGRAM)
		message(STATUS "Graphviz's 'dot' not found in the path. Make sure it's installed and in the path if you want class graph in Doxygen. Download it from http://www.graphviz.org/")
		set(HAVE_DOT "NO")
	else()
		set(HAVE_DOT "YES")
	endif()
else()
	set(HAVE_DOT "NO")
endif()

set(CU_PROJECT_COMPANYNAME "${CU_COMPANY_NAME}")
set(CU_PROJECT_LEGALCOPYRIGHT "(c) ${CU_COPYRIGHT_HOLDER}")
string(TIMESTAMP CU_YEAR %Y)
if(${CU_YEAR} STREQUAL ${CU_PROJECT_STARTING_YEAR})
	set(CU_PROJECT_READABLE_COPYRIGHT "Copyright ${CU_YEAR}, ${CU_COPYRIGHT_HOLDER}")
else()
	set(CU_PROJECT_READABLE_COPYRIGHT "Copyright ${CU_PROJECT_STARTING_YEAR}-${CU_YEAR}, ${CU_COPYRIGHT_HOLDER}")
endif()

###############################################################################
### CMake script for easy setup of gRPC

# Avoid multi inclusion of this file (cannot use include_guard as multiple copies of this file are included from multiple places)
if(CU_GENERATE_GRPC_FILES_INCLUDED)
	return()
endif()
set(CU_GENERATE_GRPC_FILES_INCLUDED true)

########
# Generate gRPC files
# Mandatory parameters:
#  - "OUTPUT_SOURCE_FILES <variable name>" => variable name to store the list of generated source files
#  - "OUTPUT_HEADER_FILES <variable name>" => variable name to store the list of generated header files
#  - "PROTO_FILE <.proto file>" => path of the .proto file to compile
function(cu_generate_grpc_files OUTPUT_SOURCE_FILES OUTPUT_HEADER_FILES PROTO_FILE)
	get_filename_component(PROTO_FILE_ABS "${PROTO_FILE}" ABSOLUTE)
	get_filename_component(PROTO_FILE_FOLDER "${PROTO_FILE_ABS}" DIRECTORY)
	get_filename_component(PROTO_FILE_NAME "${PROTO_FILE_ABS}" NAME_WLE)

	set(GENERATED_BASE_FILE_PATH "${CMAKE_CURRENT_BINARY_DIR}/${PROTO_FILE_NAME}")
	set(GENERATED_SOURCE_FILES "${GENERATED_BASE_FILE_PATH}.pb.cc" "${GENERATED_BASE_FILE_PATH}.grpc.pb.cc")
	set(GENERATED_HEADER_FILES "${GENERATED_BASE_FILE_PATH}.pb.h" "${GENERATED_BASE_FILE_PATH}.grpc.pb.h")

	add_custom_command(
		OUTPUT ${GENERATED_SOURCE_FILES} ${GENERATED_HEADER_FILES}
		COMMAND protobuf::protoc
		ARGS --grpc_out "${CMAKE_CURRENT_BINARY_DIR}" --cpp_out "${CMAKE_CURRENT_BINARY_DIR}" -I "${PROTO_FILE_FOLDER}" --plugin=protoc-gen-grpc=$<TARGET_FILE:gRPC::grpc_cpp_plugin> "${PROTO_FILE_ABS}"
		DEPENDS ${PROTO_FILE_ABS} protobuf::protoc
		COMMENT "Running protocol buffer compiler on ${PROTO_FILE}"
		VERBATIM
	)
	set_source_files_properties(${GENERATED_SOURCE_FILES} ${GENERATED_HEADER_FILES} PROPERTIES GENERATED TRUE)

	# Reduce warning level for generated files (required due to the high number of warnings in generated files)
	if(CMAKE_CXX_COMPILER_ID MATCHES "Clang") # Clang and AppleClang
		set_source_files_properties(${GENERATED_SOURCE_FILES} PROPERTIES COMPILE_FLAGS "-W -Wno-everything")
	elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
		set_source_files_properties(${GENERATED_SOURCE_FILES} PROPERTIES COMPILE_FLAGS "-W -Wno-unused-variable -Wno-unused-but-set-variable -Wno-ignored-qualifiers -Wno-sign-compare -Wno-unused-parameter -Wno-maybe-uninitialized")
	elseif(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
		set_source_files_properties(${GENERATED_SOURCE_FILES} PROPERTIES COMPILE_FLAGS "/W0")
	endif()

	set(${OUTPUT_SOURCE_FILES} "${GENERATED_SOURCE_FILES}" PARENT_SCOPE)
	set(${OUTPUT_HEADER_FILES} "${GENERATED_HEADER_FILES}" PARENT_SCOPE)
endfunction()

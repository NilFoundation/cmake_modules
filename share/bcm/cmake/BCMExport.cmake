include(CMakeParseArguments)
include(GNUInstallDirs)
include(WriteBasicConfigVersionFile)

function(bcm_get_target_package_source OUT_VAR TARGET)
    set(RESULT)
    if(TARGET ${TARGET})
        get_property(TARGET_ALIAS TARGET ${TARGET} PROPERTY ALIASED_TARGET)
        if(TARGET_ALIAS)
            set(TARGET ${TARGET_ALIAS})
        endif()
        get_property(TARGET_IMPORTED TARGET ${TARGET} PROPERTY IMPORTED)
        if(TARGET_IMPORTED OR TARGET_ALIAS)
            get_property(TARGET_FIND_PACKAGE_NAME TARGET ${TARGET} PROPERTY INTERFACE_FIND_PACKAGE_NAME)
            if(NOT TARGET_FIND_PACKAGE_NAME)
                message(SEND_ERROR "The target ${TARGET_FIND_PACKAGE_NAME} does not have information about find_package() call.")
            endif()
            set(PKG_NAME ${TARGET_FIND_PACKAGE_NAME})
            get_property(TARGET_FIND_PACKAGE_VERSION TARGET ${TARGET} PROPERTY INTERFACE_FIND_PACKAGE_VERSION)
            if(TARGET_FIND_PACKAGE_VERSION)
                set(PKG_NAME "${PKG_NAME} ${TARGET_FIND_PACKAGE_VERSION}")
            endif()
            get_property(TARGET_FIND_PACKAGE_EXACT TARGET ${TARGET} PROPERTY INTERFACE_FIND_PACKAGE_EXACT)
            if(TARGET_FIND_PACKAGE_EXACT)
                set(PKG_NAME "${PKG_NAME} ${TARGET_FIND_PACKAGE_EXACT}")
            endif()
            set(RESULT "${PKG_NAME}")
            # get_property(TARGET_FIND_PACKAGE_REQUIRED TARGET ${TARGET} PROPERTY INTERFACE_FIND_PACKAGE_REQUIRED)
            # get_property(TARGET_FIND_PACKAGE_QUIETLY TARGET ${TARGET} PROPERTY INTERFACE_FIND_PACKAGE_QUIETLY)
        endif()
    elseif("${TARGET}" MATCHES "::")
        # It must be an aliased target from another subdirectory, so lets use generator expressions instead
        set(TARGET_NAME "$<TARGET_PROPERTY:${TARGET},ALIASED_TARGET>")
        set(RESULT "$<TARGET_PROPERTY:${TARGET_NAME},INTERFACE_FIND_PACKAGE_NAME>")
    endif()
    set(${OUT_VAR} "${RESULT}" PARENT_SCOPE)
endfunction()

function(bcm_auto_export)
    set(options)
    set(oneValueArgs NAMESPACE EXPORT NAME COMPATIBILITY)
    set(multiValueArgs TARGETS)

    cmake_parse_arguments(PARSE "${options}" "${oneValueArgs}" "${multiValueArgs}"  ${ARGN})

    string(TOLOWER ${PROJECT_NAME} PROJECT_NAME_LOWER)
    set(PACKAGE_NAME ${PROJECT_NAME})
    if(PARSE_NAME)
        set(PACKAGE_NAME ${PARSE_NAME})
    endif()

    string(TOUPPER ${PACKAGE_NAME} PACKAGE_NAME_UPPER)
    string(TOLOWER ${PACKAGE_NAME} PACKAGE_NAME_LOWER)

    set(TARGET_FILE ${PROJECT_NAME_LOWER}-targets)
    if(PARSE_EXPORT)
        set(TARGET_FILE ${PARSE_EXPORT})
    endif()
    set(CONFIG_NAME ${PACKAGE_NAME_LOWER}-config)
    set(TARGET_VERSION ${PROJECT_VERSION})

    set(BIN_INSTALL_DIR ${CMAKE_INSTALL_BINDIR})
    set(LIB_INSTALL_DIR ${CMAKE_INSTALL_LIBDIR})
    set(INCLUDE_INSTALL_DIR ${CMAKE_INSTALL_INCLUDEDIR})
    set(CONFIG_PACKAGE_INSTALL_DIR ${LIB_INSTALL_DIR}/cmake/${PACKAGE_NAME_LOWER})

    set(CONFIG_FILE "${CMAKE_CURRENT_BINARY_DIR}/${CONFIG_NAME}.cmake")

    set(CONFIG_FILE_CONTENT "
include(CMakeFindDependencyMacro)
")

    if(PARSE_TARGETS)
        # Add dependencies
        foreach(TARGET ${PARSE_TARGETS})
            get_property(TARGET_LIBS TARGET ${TARGET} PROPERTY INTERFACE_LINK_LIBRARIES)
            foreach(LIB ${TARGET_LIBS})
                bcm_get_target_package_source(PKG_SRC ${LIB})
                if(PKG_SRC)
                    string(APPEND CONFIG_FILE_CONTENT "# Library: ${LIB}\n")
                    string(APPEND CONFIG_FILE_CONTENT "find_dependency(${PKG_SRC})\n")
                else()
                    string(APPEND CONFIG_FILE_CONTENT "# Skip: ${LIB}\n")
                endif()
            endforeach()
        endforeach()
        # Compute targets imported name
        set(EXPORT_LIB_TARGETS)
        foreach(TARGET ${PARSE_TARGETS})
            get_target_property(TARGET_NAME ${TARGET} EXPORT_NAME)
            if(NOT TARGET_NAME)
                get_target_property(TARGET_NAME ${TARGET} NAME)
            endif()
            set(EXPORT_LIB_TARGET_${TARGET} ${PARSE_NAMESPACE}${TARGET_NAME})
            list(APPEND EXPORT_LIB_TARGETS ${EXPORT_LIB_TARGET_${TARGET}})
        endforeach()
        # Export custom properties
        set(EXPORT_PROPERTIES)
        foreach(TARGET ${PARSE_TARGETS})
            # TODO: Make this a property: the custom properties to be exported
            foreach(PROPERTY INTERFACE_PKG_CONFIG_NAME)
                set(PROP "$<TARGET_PROPERTY:${TARGET},${PROPERTY}>")
                set(EXPORT_PROPERTIES "${EXPORT_PROPERTIES}
$<$<BOOL:${PROP}>:set_target_properties(${EXPORT_LIB_TARGET_${TARGET}} PROPERTIES ${PROPERTY} ${PROP})>
")
            endforeach()
        endforeach()
        string(APPEND CONFIG_FILE_CONTENT "
include(\"\${CMAKE_CURRENT_LIST_DIR}/${TARGET_FILE}.cmake\")
include(\"\${CMAKE_CURRENT_LIST_DIR}/properties-${TARGET_FILE}.cmake\")
")
    endif()

    file(GENERATE OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/properties-${TARGET_FILE}.cmake CONTENT "${EXPORT_PROPERTIES}")
    install(FILES ${CMAKE_CURRENT_BINARY_DIR}/properties-${TARGET_FILE}.cmake DESTINATION ${CONFIG_PACKAGE_INSTALL_DIR})

    file(GENERATE OUTPUT "${CONFIG_FILE}" CONTENT "${CONFIG_FILE_CONTENT}")

    set(COMPATIBILITY_ARG SameMajorVersion)
    if(PARSE_COMPATIBILITY)
        set(COMPATIBILITY_ARG ${PARSE_COMPATIBILITY})
    endif()
    write_basic_config_version_file(
        ${CMAKE_CURRENT_BINARY_DIR}/${CONFIG_NAME}-version.cmake
        VERSION ${TARGET_VERSION}
        COMPATIBILITY ${COMPATIBILITY_ARG}
    )

    set(NAMESPACE_ARG)
    if(PARSE_NAMESPACE)
        set(NAMESPACE_ARG "NAMESPACE;${PARSE_NAMESPACE}")
    endif()
    install( EXPORT ${TARGET_FILE}
        DESTINATION
        ${CONFIG_PACKAGE_INSTALL_DIR}
        ${NAMESPACE_ARG}
    )

    install( FILES
        ${CONFIG_FILE}
        ${CMAKE_CURRENT_BINARY_DIR}/${CONFIG_NAME}-version.cmake
        DESTINATION
        ${CONFIG_PACKAGE_INSTALL_DIR})

endfunction()


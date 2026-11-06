find_program(PONYNOTES_AGENT_NODE NAMES node node.exe REQUIRED)
add_custom_target(ponynotes_agent_runtime ALL
  COMMAND "${PONYNOTES_AGENT_NODE}" "${CMAKE_CURRENT_LIST_DIR}/prepare.mjs"
  WORKING_DIRECTORY "${CMAKE_CURRENT_LIST_DIR}"
  COMMENT "Preparing bundled pi Agent runtime"
  VERBATIM
)
add_dependencies(${BINARY_NAME} ponynotes_agent_runtime)
install(DIRECTORY "${CMAKE_CURRENT_LIST_DIR}/bundle/"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}/agent-runtime"
  COMPONENT Runtime)

target_sources(${BINARY_NAME} PRIVATE "updater.cpp" "updater_files.cpp")
target_link_libraries(${BINARY_NAME} PRIVATE bcrypt shell32 ole32)

add_executable(vela_updater_helper WIN32 "updater_helper.cpp" "updater_files.cpp")
target_compile_features(vela_updater_helper PRIVATE cxx_std_17)
set_property(TARGET vela_updater_helper PROPERTY MSVC_RUNTIME_LIBRARY
  "MultiThreaded$<$<CONFIG:Debug>:Debug>")
target_link_libraries(vela_updater_helper PRIVATE bcrypt shell32 ole32)
install(TARGETS vela_updater_helper RUNTIME DESTINATION "." COMPONENT Runtime)

add_executable(vela_updater_test EXCLUDE_FROM_ALL
  "updater_test.cpp" "updater_files.cpp")
target_compile_features(vela_updater_test PRIVATE cxx_std_17)
set_property(TARGET vela_updater_test PROPERTY MSVC_RUNTIME_LIBRARY
  "MultiThreaded$<$<CONFIG:Debug>:Debug>")
target_link_libraries(vela_updater_test PRIVATE bcrypt shell32 ole32)

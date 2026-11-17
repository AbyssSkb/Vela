target_sources(${BINARY_NAME} PRIVATE "updater.cc")

pkg_check_modules(GLIB REQUIRED IMPORTED_TARGET glib-2.0)
add_executable(vela_update_helper "updater_helper.cc")
apply_standard_settings(vela_update_helper)
target_link_libraries(vela_update_helper PRIVATE PkgConfig::GLIB)

# Install after Flutter's bundle cleanup, which is declared by the parent.
set(VELA_UPDATE_HELPER_TARGET vela_update_helper PARENT_SCOPE)

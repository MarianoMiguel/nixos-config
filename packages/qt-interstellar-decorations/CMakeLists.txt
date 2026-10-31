# Interstellar's title bar for Qt 6 apps on Wayland (a QtWayland decoration
# plugin, key "interstellar"). Derived from QAdwaitaDecorations; see LICENSE.
cmake_minimum_required(VERSION 3.16)

project(qt-interstellar-decorations VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_AUTOMOC ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.10 REQUIRED COMPONENTS Core Gui WaylandClient)
# The decoration API is private Qt API: the plugin must be built against the
# exact Qt the apps run on (plugin.cpp falls back to Qt's own bar otherwise).
set(QT_NO_PRIVATE_MODULE_WARNING ON)
find_package(Qt6 REQUIRED COMPONENTS GuiPrivate WaylandClientPrivate)

if(NOT QT_PLUGINS_DIR)
    set(QT_PLUGINS_DIR "${QT6_INSTALL_PLUGINS}")
endif()

add_library(interstellar MODULE
    plugin.cpp
    decoration.cpp
    decoration.h
    palette.cpp
    palette.h
)
target_link_libraries(interstellar PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::GuiPrivate
    Qt6::WaylandClient
    Qt6::WaylandClientPrivate
)
# Qt's targets drag in OpenGL and xkbcommon; load only what is used.
target_link_options(interstellar PRIVATE "LINKER:--as-needed")

install(TARGETS interstellar LIBRARY DESTINATION "${QT_PLUGINS_DIR}/wayland-decoration-client")

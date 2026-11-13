set(TARGET WeaponSpawner)

add_library(${TARGET} SHARED dllmain.cpp)
target_include_directories(${TARGET} PRIVATE .)
target_link_libraries(${TARGET} PUBLIC UE4SS)

# Stage the DLL into our Win64 mirror as Mods/WeaponSpawner/dlls/main.dll
add_custom_command(TARGET ${TARGET} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_CURRENT_SOURCE_DIR}/../../Win64/ue4ss/Mods/WeaponSpawner/dlls"
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:${TARGET}> "${CMAKE_CURRENT_SOURCE_DIR}/../../Win64/ue4ss/Mods/WeaponSpawner/dlls/main.dll"
)

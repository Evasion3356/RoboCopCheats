cmake_minimum_required(VERSION 3.22)
project(RoboCopCheatsMods)

# UE4SS source, checked out at the exact release we ship (v4.0.0) so the C++ ABI matches.
# Clone (with submodules) into ../_deps/RE-UE4SS -- see README in this folder.
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../_deps/RE-UE4SS ${CMAKE_BINARY_DIR}/RE-UE4SS)
add_subdirectory(RoboCopCheats)

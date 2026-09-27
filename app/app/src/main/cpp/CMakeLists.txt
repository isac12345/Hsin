cmake_minimum_required(VERSION 3.22.1)
project("hsin_native")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_library(
    hsin_native
    SHARED
    hsin_native.cpp
)

target_compile_options(
    hsin_native
    PRIVATE
    -O2
    -ffunction-sections
    -fdata-sections
    -fvisibility=hidden
)

find_library(log-lib log)
target_link_libraries(hsin_native ${log-lib})



PROJECT(secserver)

cmake_minimum_required (VERSION 2.6)
cmake_policy(SET CMP0012 NEW)



# *** NEW ***
set(CMAKE_MODULE_PATH /tmp/cmakemod)

# *** NEW ***
find_package(MbedTLS REQUIRED)
list(APPEND proj_LIBRARIES ${MBEDTLS_LIBRARIES})



include_directories(${PROJECT_SOURCE_DIR})
add_executable(secserver server_ctt.c open62541.c)  

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -pthread")



# *** NEW *** 
target_link_libraries(secserver ${proj_LIBRARIES})



cmake_minimum_required(VERSION 3.27)
project(renderer LANGUAGES C CUDA)

# Compiler configurations
set(CMAKE_CUDA_ARCHITECTURES native)
set(CMAKE_C_STANDARD 17)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CUDA_EXTENSIONS OFF) # Stating the use of C explicitly
set(CMAKE_CUDA_COMPILER "/usr/local/cuda/bin/nvcc")
set(CMAKE_CUDA_TOOLKIT_INCLUDE_DIRECTORIES "/usr/local/cuda/include")
#set(CMAKE_CUDA_COMPILER "/vol/cuda/13.1.0/bin/nvcc")
#set(CMAKE_CUDA_TOOLKIT_INCLUDE_DIRECTORIES "/vol/cuda/13.1.0/include")
set(CMAKE_CUDA_SEPARABLE_COMPILATION ON)

# Dependencies
# OptiX path
set(PARSING_DIR ${CMAKE_CURRENT_SOURCE_DIR}/parsing)
set(PARSER_STATIC_LIB ${PARSING_DIR}/libparsing.a)
set(OPTIX_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/include/optix-dev/include" CACHE PATH "# OptiX path, check with find /vol -name optix.h")
find_package(OpenGL REQUIRED)
find_package(glfw3 CONFIG REQUIRED)
find_package(GLEW REQUIRED)
find_package(CUDAToolkit REQUIRED)
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/include)
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/include/stb)
include_directories(${OPTIX_INCLUDE_DIR})
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/include/api_wrapper)

add_custom_command(
    OUTPUT ${PARSING_DIR}/libparsing.a
    COMMAND ${CMAKE_MAKE_PROGRAM} -C ${PARSING_DIR}
    COMMENT "Building the parser using its local Makefile"
    VERBATIM
)
add_library(utils STATIC
    include/api_wrapper/thrust_wrapper.cu
    include/bound_box.cu
    include/mesh.cu
    include/objects.cu
    include/bvh.cu
    include/pathtracing.cu
    include/materials.cu
    include/lighting.cu
    include/light_sources.cu
    include/materials.cu
    include/pathtracing.cu
    include/postprocess.cu
    include/scene_processing.cu
)
add_library(parser_lib STATIC IMPORTED GLOBAL)
set_target_properties(parser_lib PROPERTIES IMPORTED_LOCATION ${PARSER_STATIC_LIB})
set_source_files_properties(include/api_wrapper/thrust_wrapper.cu PROPERTIES
    LANGUAGE CUDA
    COMPILE_OPTIONS "--extended-lambda"
)
set_target_properties(utils PROPERTIES 
    LANGUAGE CUDA
    COMPILE_OPTIONS "-g"
)
target_link_libraries(utils PRIVATE
    /usr/local/cuda/targets/x86_64-linux/lib/libnvjpeg.so
)
#target_link_libraries(utils PRIVATE
#    /vol/cuda/13.1.0/targets/x86_64-linux/lib/libnvjpeg.so
#)

target_link_libraries(utils PRIVATE
    /usr/local/cuda/targets/x86_64-linux/lib/libnvjpeg.so
)
#target_link_libraries(utils PRIVATE
#    /vol/cuda/13.1.0/targets/x86_64-linux/lib/libnvjpeg.so
#)

# Build Target
add_executable(renderer main.cu)
set_source_files_properties(main.cu PROPERTIES LANGUAGE CUDA)

# Linking
add_dependencies(parser_lib build_parser)
add_custom_target(build_parser ALL DEPENDS ${PARSING_DIR}/libparsing.a)
set_target_properties(build_parser PROPERTIES
    IMPORTED_LOCATION ${PARSING_DIR}/libparsing.a
)
target_include_directories(renderer PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${GLEW_INCLUDE_DIRS}
    ${OPTIX_INCLUDE_DIR}
    ${PARSING_DIR}
)
target_link_libraries(renderer PRIVATE
    CUDA::cudart
    /usr/local/cuda/targets/x86_64-linux/lib/libnvjpeg.so
    #vol/cuda/13.1.0/targets/x86_64-linux/lib/libnvjpeg.so
    glfw
    GLEW::GLEW
    OpenGL::GL
    utils
    parser_lib
    /usr/local/cuda/targets/x86_64-linux/lib/libnvjpeg.so
    #/vol/cuda/13.1.0/targets/x86_64-linux/lib/libnvjpeg.so
)

# Compiler Flags
target_compile_options(renderer PRIVATE
    $<$<COMPILE_LANGUAGE:C>:-O3 -g -Wall -Werror -pedantic>
    $<$<COMPILE_LANGUAGE:CUDA>:-O3 --use_fast_math -Xcompiler=-Wall -Xcompiler=-Werror>
)
target_compile_options(renderer PRIVATE
    $<$<COMPILE_LANGUAGE:C>:-Wstrict-prototypes -fsanitize=address -fsanitize=undefined -fno-sanitize-recover>
)
target_link_options(renderer PRIVATE
    $<$<COMPILE_LANGUAGE:C>:-fsanitize=address -fsanitize=undefined -fno-sanitize-recover>
)

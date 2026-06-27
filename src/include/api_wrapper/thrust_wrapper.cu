#include "constants.h"
#include "thrust_wrapper.h"

void sort_morton_shapes_thrust(MortonShape *morton_shapes, uint32_t num_triangles) {
    thrust::device_vector<uint64_t> keys(num_triangles);
    thrust::device_vector<uint64_t> values(num_triangles);
    
    thrust::transform(thrust::device,
                      morton_shapes,
                      morton_shapes + num_triangles,
                      keys.begin(),
                      [] __device__ (const MortonShape &morton){
                        return morton.morton_code;
                      });
    thrust::transform(thrust::device,
                      morton_shapes,
                      morton_shapes + num_triangles,
                      values.begin(),
                      [] __device__ (const MortonShape &morton){
                        return ((uint64_t) morton.mesh_index << 32) | (uint64_t) morton.tri_index;
                      });
    thrust::sort_by_key(keys.begin(), keys.end(), values.begin());
    thrust::transform(thrust::device,
                      keys.begin(),
                      keys.end(),
                      values.begin(),
                      morton_shapes,
                      [] __device__ (const uint64_t &code, const uint64_t &index) {
                        MortonShape shape = {
                            .morton_code = code,
                            .mesh_index = (int) (index >> 32),
                            .tri_index = (int) index
                        };
                        return shape;
                      });
}

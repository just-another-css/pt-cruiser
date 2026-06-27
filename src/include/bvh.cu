#include "bvh.h"
#include "api_wrapper/thrust_wrapper.h"

#define MAX_NUM_TREELETS 4096
#define TREELET_MASK 0x3ffc0000
#define TREELET_SHIFT 18

__device__ BVH bvh_dev;

__global__ static void compute_centroids(float3 *centroids, uint32_t*  num_triangles);
__global__ static void reduce_centroid_blocks(float3*  centroids, BoundBox* block_aabbs, uint32_t num_block, uint32_t*  num_triangles);
__global__ static void reduce_centroid_object(BoundBox*  block_boxes, uint32_t num_block);
__global__ static void reduce_centroid_global(BoundBox*  block_boxes, BoundBox *global_centroid, uint32_t num_block);
__global__ static void compute_morton_code(MortonShape *morton_codes, BoundBox*  global_centroid, float3*  centroids, uint32_t  *num_triangles);
__global__ static void build_bvh_topo(MortonShape*  morton_shapes, int *parent_index, const uint32_t num_triangles);
__global__ static void refit_bvh_aabbs(int*  parent_index, unsigned int *node_counters, const uint32_t num_triangles);

void create_bvh(void) {
    CUDA_CHECK(cudaGetLastError());
    // compute total number of triangles
    uint32_t num_triangles_size = (objects.num_objects + 1) * sizeof(uint32_t);
    uint32_t *total_num_triangles = (uint32_t*) malloc(num_triangles_size);
    MALLOC_CHECK(total_num_triangles);
    total_num_triangles[0] = 0;
    for (int i = 1; i <= objects.num_objects; i++) {
        total_num_triangles[i] = total_num_triangles[i-1] + objects.meshes[i-1].triangle_count;
    }
    uint32_t *total_num_triangles_dev;
    CUDA_CHECK(cudaMalloc(&total_num_triangles_dev, num_triangles_size));
    CUDA_CHECK(cudaGetLastError());
    CUDA_CHECK(cudaMemcpy(total_num_triangles_dev, total_num_triangles, num_triangles_size, cudaMemcpyHostToDevice));
    // Initialise bvh_dev
    BVH bvh_dev_cpy;
    const int max_num_nodes = total_num_triangles[objects.num_objects] << 1;
    create_boundboxes_dev(bvh_dev_cpy.aabbs, max_num_nodes);
    const int index_size = max_num_nodes * sizeof(int);
    CUDA_CHECK(cudaMalloc(&bvh_dev_cpy.mesh_index, index_size));
    CUDA_CHECK(cudaMalloc(&bvh_dev_cpy.triangle_index, index_size));
    CUDA_CHECK(cudaMalloc(&bvh_dev_cpy.left_child_index, index_size));
    CUDA_CHECK(cudaMalloc(&bvh_dev_cpy.right_child_index, index_size));
    CUDA_CHECK(cudaMemcpyToSymbol(bvh_dev, &bvh_dev_cpy, sizeof(BVH)));
    // CUDA_CHECK(cudaMallocManaged(&total_num_triangles, (objects.num_objects + 1) * sizeof(uint32_t), cudaMemAttachGlobal));
    // allocate centroids
    float3 *centroids;
    CUDA_CHECK(cudaMalloc(&centroids, total_num_triangles[objects.num_objects] * sizeof(float3)));
    // compute centroids for each triangle
    {
        dim3 thread_per_block;
        thread_per_block.x = thread_per_block.y = 16;
        dim3 num_blocks;
        num_blocks.x = (objects.num_objects + thread_per_block.x - 1) / thread_per_block.x;
        num_blocks.y = (objects.max_tri_count + thread_per_block.y - 1) / thread_per_block.y;
        compute_centroids<<<num_blocks, thread_per_block>>>(centroids, total_num_triangles_dev);
        CUDA_CHECK(cudaGetLastError());
        // CUDA_CHECK(cudaDeviceSynchronize());
    }
    // centroid reduction
    BoundBox *global_centroid;
    CUDA_CHECK(cudaMalloc(&global_centroid, sizeof(BoundBox)));
    {
        // Stage 1 reduction - shrinking down by hundreds of factor
        // 1D block to union points
        dim3 thread_per_block;
        thread_per_block.x = 256;
        thread_per_block.y = 1;
        // 2D block: objects along x axis, triangle along y axis
        uint32_t num_blocks = (objects.max_tri_count + thread_per_block.x - 1) / thread_per_block.x;
        dim3 num_blocks_grid;
        num_blocks_grid.x = objects.num_objects;
        num_blocks_grid.y = num_blocks;
        BoundBox *block_boxes;
        CUDA_CHECK(cudaMalloc(&block_boxes, num_blocks_grid.x * num_blocks_grid.y * sizeof(BoundBox)));
        reduce_centroid_blocks<<<num_blocks_grid, thread_per_block>>>(centroids, block_boxes, num_blocks, total_num_triangles_dev);
        // CUDA_CHECK(cudaDeviceSynchronize());
        // Stage 2 reduction to per object
        num_blocks_grid.y = 1;
        reduce_centroid_object<<<num_blocks_grid, thread_per_block>>>(block_boxes, num_blocks);
        // CUDA_CHECK(cudaDeviceSynchronize());
        // Stage 3 final conclusion
        reduce_centroid_global<<<1, thread_per_block>>>(block_boxes, global_centroid, num_blocks);
        // CUDA_CHECK(cudaDeviceSynchronize());
        // free temporary resources
        cudaFree(block_boxes);
    }
#ifdef DEBUG_BVH
    // Verify
    BoundBox verify_aabb;
    CUDA_CHECK(cudaMemcpy(&verify_aabb, global_centroid, sizeof(BoundBox), cudaMemcpyDefault));
#endif
    // compute Morton code
    MortonShape *morton_shapes;
    CUDA_CHECK(cudaMalloc(&morton_shapes, total_num_triangles[objects.num_objects] * sizeof(MortonShape)));
    {
        dim3 thread_per_block;
        thread_per_block.x = thread_per_block.y = 16;
        dim3 num_blocks;
        num_blocks.x = (objects.num_objects + thread_per_block.x - 1) / thread_per_block.x;
        num_blocks.y = (objects.max_tri_count + thread_per_block.y - 1) / thread_per_block.y;
        compute_morton_code<<<num_blocks, thread_per_block>>>(morton_shapes, global_centroid, centroids, total_num_triangles_dev);
        // CUDA_CHECK(cudaDeviceSynchronize());
    } 
    // sort Morton code
    sort_morton_shapes_thrust(morton_shapes, total_num_triangles[objects.num_objects]);
#ifdef DEBUG_BVH
    // Verify
    MortonShape *morton_cpy = (MortonShape*) malloc(total_num_triangles[objects.num_objects] * sizeof(MortonShape));
    CUDA_CHECK(cudaMemcpy(morton_cpy, morton_shapes, total_num_triangles[objects.num_objects] * sizeof(MortonShape), cudaMemcpyDefault));
    int *parent_index_cpy = (int*) malloc(index_size);
#endif
    // Build BVH
    {
        int *parent_index;
        CUDA_CHECK(cudaMalloc(&parent_index, index_size));
        // set parent of root node to be -1
        int root_parent = -1;
        CUDA_CHECK(cudaMemset(parent_index, 0xff, index_size));
        CUDA_CHECK(cudaMemcpy(parent_index, &root_parent, sizeof(int), cudaMemcpyHostToDevice));
        dim3 thread_per_block;
        thread_per_block.x = min(256, total_num_triangles[objects.num_objects]);
        thread_per_block.y = 1;
        dim3 num_blocks;
        num_blocks.x = (total_num_triangles[objects.num_objects] + thread_per_block.x - 1) / thread_per_block.x;
        num_blocks.y = 1;
        // stage1: build tree from top to bottom
        build_bvh_topo<<<num_blocks, thread_per_block>>>(morton_shapes, parent_index, total_num_triangles[objects.num_objects]);
        CUDA_CHECK(cudaDeviceSynchronize());
        // stage2: recompute aabbs from bottom to top
        unsigned int *node_counters;
        CUDA_CHECK(cudaMalloc(&node_counters, index_size));
        CUDA_CHECK(cudaMemset(node_counters, 0, index_size));
        refit_bvh_aabbs<<<num_blocks, thread_per_block>>>(parent_index, node_counters, total_num_triangles[objects.num_objects]);
        // CUDA_CHECK(cudaDeviceSynchronize());
#ifdef DEBUG_BVH
        MALLOC_CHECK(parent_index_cpy);
        CUDA_CHECK(cudaMemcpy(parent_index_cpy, parent_index, index_size, cudaMemcpyDefault));
#endif
        // free temporary resources
        cudaFree(node_counters);
        cudaFree(parent_index);
    }
#ifdef DEBUG_BVH
    // Verify
    BVH verify;
    CUDA_CHECK(cudaMemcpyFromSymbol(&verify, bvh_dev, sizeof(BVH)));
    BoundBoxes aabbs;
    create_boundboxes(aabbs, index_size);
    CUDA_CHECK(cudaMemcpy(aabbs.pt_max, verify.aabbs.pt_max, max_num_nodes * sizeof(float3), cudaMemcpyDefault));
    CUDA_CHECK(cudaMemcpy(aabbs.pt_min, verify.aabbs.pt_min, max_num_nodes * sizeof(float3), cudaMemcpyDefault));
    // fprintf("max: (%f,%f,%f) min: (%f,%f,%f)", aabbs.pt_max[0].x, aabbs.pt_max.y, aabbs.pt_max.z, aabbs.pt_min.x, aabbs.pt_min.y, aabbs.pt_min.z);
    int *tri_indices = (int*) malloc(index_size);
    MALLOC_CHECK(tri_indices);
    CUDA_CHECK(cudaMemcpy(tri_indices, verify.triangle_index, index_size, cudaMemcpyDeviceToHost));
    int *mesh_indices = (int*) malloc(index_size);
    MALLOC_CHECK(mesh_indices);
    CUDA_CHECK(cudaMemcpy(mesh_indices, verify.mesh_index, index_size, cudaMemcpyDeviceToHost));
    int *left_child_index = (int*) malloc(index_size);
    MALLOC_CHECK(left_child_index);
    CUDA_CHECK(cudaMemcpy(left_child_index, verify.left_child_index, index_size, cudaMemcpyDeviceToHost));
    int *right_child_index = (int*) malloc(index_size);
    MALLOC_CHECK(right_child_index);
    CUDA_CHECK(cudaMemcpy(right_child_index, verify.right_child_index, index_size, cudaMemcpyDeviceToHost));
#endif
    // free temporal pointers
    cudaFree(centroids);
    cudaFree(global_centroid);
    cudaFree(morton_shapes);
    free(total_num_triangles);
}

void free_bvh(void) {
    BVH bvh_dev_cpy;
    CUDA_CHECK(cudaMemcpyFromSymbol(&bvh_dev_cpy, bvh_dev, sizeof(BVH)));
    CUDA_CHECK(cudaFree(bvh_dev_cpy.mesh_index));
    CUDA_CHECK(cudaFree(bvh_dev_cpy.triangle_index));
    CUDA_CHECK(cudaFree(bvh_dev_cpy.left_child_index));
    CUDA_CHECK(cudaFree(bvh_dev_cpy.right_child_index));
    free_boundbox(bvh_dev_cpy.aabbs);
}

// Compute centroids for each triangle
__global__ static void compute_centroids(float3 *centroids, uint32_t*  num_triangles) {
    int x = blockIdx.x * blockDim.x + threadIdx.x; // object
    int y = blockIdx.y * blockDim.y + threadIdx.y; // triangle
    if (x >= objects_dev.num_objects) {
        return;
    }
    TriangleMesh *mesh = &objects_dev.meshes[x];
    if (y >= mesh->triangle_count) {
        return;
    }
    centroids[num_triangles[x] + y] = centroid(&mesh->aabbs, y);
}

__global__ static void reduce_centroid_blocks(float3*  centroids, BoundBox *block_aabbs, uint32_t num_block, uint32_t*  num_triangles) {
    __shared__ BoundBox s_boxes[256];
    int tri_index = blockIdx.y * blockDim.x + threadIdx.x;
    TriangleMesh* mesh = objects_dev.meshes + blockIdx.x;
    if (tri_index < mesh->triangle_count) {
        float3 cent = centroids[num_triangles[blockIdx.x] + tri_index];
        s_boxes[threadIdx.x].pt_max = cent;
        s_boxes[threadIdx.x].pt_min = cent;
    } else {
        initialise_boundbox(s_boxes[threadIdx.x]);
    }
    __syncthreads();
    // horizontal reduction
    for (int step = blockDim.x / 2; step > 0; step >>= 1) {
        if (threadIdx.x < step) {
            s_boxes[threadIdx.x] = union_box_box(s_boxes[threadIdx.x], s_boxes[threadIdx.x + step]);
        }
        __syncthreads(); // prevent step halved but larger threads is not completed yet
    }
    // write out the combined value on thread 0
    if (threadIdx.x == 0) {
        block_aabbs[blockIdx.x * num_block + blockIdx.y] = s_boxes[0];
    }
}

__global__ static void reduce_centroid_object(BoundBox* block_boxes, uint32_t num_block) {
    __shared__ BoundBox s_boxes[256];
    // reduce centroids to 256 threads
    BoundBox thread_box;
    initialise_boundbox(thread_box);
    for(int i = threadIdx.x; i < num_block; i += blockDim.x) {
        thread_box = union_box_box(thread_box, block_boxes[blockIdx.x * num_block + i]);
    }
    s_boxes[threadIdx.x] = thread_box;
    __syncthreads();
    // horizontal reduction
    for (int step = blockDim.x / 2; step > 0; step >>= 1) {
        if (threadIdx.x < step) {
            s_boxes[threadIdx.x] = union_box_box(s_boxes[threadIdx.x], s_boxes[threadIdx.x + step]);
        }
        __syncthreads(); // prevent step halved but larger threads is not completed yet
    }
    // synchronise to global memory
    if (threadIdx.x == 0) {
        block_boxes[blockIdx.x * num_block] = s_boxes[0];
    }
}

__global__ static void reduce_centroid_global(BoundBox*  block_boxes, BoundBox *global_centroid, uint32_t num_block) {
    __shared__ BoundBox s_boxes[256];
    // reduce centroids to 256 threads
    BoundBox thread_box;
    initialise_boundbox(thread_box);
    for(int i = threadIdx.x; i < objects_dev.num_objects; i += blockDim.x) {
        thread_box = union_box_box(thread_box, block_boxes[i * num_block]);
    }
    s_boxes[threadIdx.x] = thread_box;
    __syncthreads();
    // horizontal reduction
    for (int step = blockDim.x / 2; step > 0; step >>= 1) {
        if (threadIdx.x < step) {
            s_boxes[threadIdx.x] = union_box_box(s_boxes[threadIdx.x], s_boxes[threadIdx.x + step]);
        }
        __syncthreads(); // prevent step halved but larger threads is not completed yet
    }
    if (threadIdx.x == 0) {
        *global_centroid = s_boxes[0];
    }
}

__device__ static uint64_t encode_morton(const float3 &centroid_offset) {
    return (lshift_each_bit_3(centroid_offset.z) << 2) | (lshift_each_bit_3(centroid_offset.y) << 1) | lshift_each_bit_3(centroid_offset.x);
}

__global__ static void compute_morton_code(MortonShape *morton_codes, BoundBox* global_centroid, float3*  centroids, uint32_t  *num_triangles) {
    int obj_index = blockIdx.x * blockDim.x + threadIdx.x;
    int tri_index = blockIdx.y * blockDim.y + threadIdx.y;
    if (obj_index >= objects_dev.num_objects) {
        return;
    }
    TriangleMesh *mesh = &objects_dev.meshes[obj_index];
    if (tri_index >= mesh->triangle_count) {
        return;
    }

    const int morton_bits = 21;
    const int morton_scale = 1 << morton_bits;
    const int morton_mask = morton_scale - 1;
    uint32_t current_index = num_triangles[obj_index] + tri_index;
    morton_codes[current_index].mesh_index = obj_index;
    morton_codes[current_index].tri_index = tri_index;
    float3 centroid_offset = offset(*global_centroid, centroids[current_index]);
    scale_vec_ip(morton_scale, &centroid_offset);
    centroid_offset = vec_min(vec_max(centroid_offset, make_float3(0, 0, 0)), make_float3(morton_mask, morton_mask, morton_mask));
    morton_codes[current_index].morton_code = encode_morton(centroid_offset);
}

// length of the same prefix
__device__ static inline int common_prefix_length(MortonShape* morton_shapes, int i, int j, uint32_t num_triangles) {
    if (j < 0 || j >= num_triangles) {
        return -1;
    }
    uint64_t code_i = morton_shapes[i].morton_code;
    uint64_t code_j = morton_shapes[j].morton_code;
    // To distinguish between identical code leaves
    return code_i == code_j ? 64 + __clz(i ^ j) : __clzll(code_i ^ code_j);
}

// [0, n-1): internal nodes; [n-1, 2n-1): leaf nodes
__global__ static void build_bvh_topo(MortonShape* morton_shapes, int *parent_index, const uint32_t num_triangles) {
    int node_index = blockIdx.x * blockDim.x + threadIdx.x;
    // process n leaf nodes
    if (node_index < num_triangles) {
        int leaf_node_index = num_triangles - 1 + node_index;
        bvh_dev.mesh_index[leaf_node_index] = morton_shapes[node_index].mesh_index;
        bvh_dev.triangle_index[leaf_node_index] = morton_shapes[node_index].tri_index;
        bvh_dev.aabbs.pt_min[leaf_node_index] = objects_dev.meshes[morton_shapes[node_index].mesh_index].aabbs.pt_min[morton_shapes[node_index].tri_index];
        bvh_dev.aabbs.pt_max[leaf_node_index] = objects_dev.meshes[morton_shapes[node_index].mesh_index].aabbs.pt_max[morton_shapes[node_index].tri_index];
    }
    // only n - 1 internal nodes
    if (node_index >= num_triangles - 1) {
        return;
    }
    bvh_dev.mesh_index[node_index] = -1;
    int upper_dir = common_prefix_length(morton_shapes, node_index, node_index + 1, num_triangles);
    int lower_dir = common_prefix_length(morton_shapes, node_index, node_index - 1, num_triangles);
    int dir = upper_dir >= lower_dir ? 1 : -1;
    int delta_min = dir == 1 ? lower_dir : upper_dir;
    // find upper bound
    int bound_max = 2;
    while (common_prefix_length(morton_shapes, node_index, node_index + bound_max * dir, num_triangles) > delta_min) {
        bound_max <<= 1;
    }
    int bound = 0;
    for (int off = bound_max >> 1; off > 0; off >>= 1) {
        if (common_prefix_length(morton_shapes, node_index, node_index + (bound + off) * dir, num_triangles) > delta_min) {
            bound += off;
        }
    }
    int bound_node_index = node_index + bound * dir;
    // find split point inside [node_index, end_node_index]
    int start_node_index = min(node_index, bound_node_index);
    int end_node_index   = max(node_index, bound_node_index);
    // make split free from using dir
    int delta_node = common_prefix_length(morton_shapes, start_node_index, end_node_index, num_triangles);
    int split = start_node_index;
    int off = end_node_index - start_node_index;
    // using do while instead of for loop for corner case of `off = 1`
    do {
        off = (off + 1) >> 1;
        int mid = split + off;
        if (mid < end_node_index &&
            common_prefix_length(morton_shapes, start_node_index, mid, num_triangles) > delta_node) {
            split = mid;
        }
    } while (off > 1);
    // split = last index of the left subrange
    int left_child_index  = (split     == start_node_index) ? split     + num_triangles - 1 : split;
    int right_child_index = (split + 1 == end_node_index)   ? split + 1 + num_triangles - 1 : split + 1;
    bvh_dev.left_child_index[node_index] = left_child_index;
    bvh_dev.right_child_index[node_index] = right_child_index;
    // printf("%d\n", bvh_dev.child_index[node_index]);
#ifdef DEBUG_BVH
    if (node_index == 12052 || node_index == 12055) {
        // printf("node %d: start - %d; end - %d; bound - %d; split - %d\n", node_index, start_node_index, end_node_index, bound, split);
        // printf("node %d: delta_node - %d; bound_node_index - %d\n", node_index, delta_node, bound_node_index);
    }
#endif
    parent_index[left_child_index] = node_index;
    parent_index[right_child_index] = node_index;
}

__global__ static void refit_bvh_aabbs(int*  parent_index, unsigned int *node_counters, const uint32_t num_triangles) {
    int node_index = blockIdx.x * blockDim.x + threadIdx.x;
    if (node_index >= num_triangles) {
        return;
    }
    int leaf_nodex_index = node_index + num_triangles - 1;
    int current_node = parent_index[leaf_nodex_index];
    while (current_node != -1) {
        int visit = atomicAdd(&node_counters[current_node], 1);
        if (visit == 0) {
            // the other child will compute the parent node
            return;
        }
        assert (visit == 1);
        // recompute child node, as threads are random
        int left_child_index = bvh_dev.left_child_index[current_node];
        int right_child_index = bvh_dev.right_child_index[current_node];
        BoundBox result = union_boxes(&bvh_dev.aabbs, left_child_index, right_child_index);
#ifdef DEBUG_BVH
        if (current_node == 21611) {
            printf("%d %d\n", left_child_index, right_child_index);
            printf("(%f %f %f), (%f %f %f)\n", result.pt_min.x, result.pt_min.y, result.pt_min.z, result.pt_max.x, result.pt_max.y, result.pt_max.z);
        }
#endif
        bvh_dev.aabbs.pt_min[current_node] = result.pt_min;
        bvh_dev.aabbs.pt_max[current_node] = result.pt_max;
        if (current_node == 0) { // root node
            break;
        }
        current_node = parent_index[current_node];
    }
}

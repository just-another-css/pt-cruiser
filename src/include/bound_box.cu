#include "bound_box.h"

void create_boundboxes(BoundBoxes &boxes, uint32_t capacity) {
    int aabb_size = capacity * sizeof(float3);
    boxes.pt_min = (float3*) malloc(aabb_size);
    MALLOC_CHECK(boxes.pt_min);
    boxes.pt_max = (float3*) malloc(aabb_size);
    MALLOC_CHECK(boxes.pt_max);
}

void create_boundboxes_dev(BoundBoxes &boxes, uint32_t capacity) {
    int aabb_size = capacity * sizeof(float3);
    CUDA_CHECK(cudaMalloc(&boxes.pt_min, aabb_size));
    CUDA_CHECK(cudaMalloc(&boxes.pt_max, aabb_size));
}

__device__ void initialise_boundbox(BoundBox &box) {
    box.pt_min = make_float3(FLT_MAX, FLT_MAX, FLT_MAX);
    box.pt_max = make_float3(-FLT_MAX, -FLT_MAX, -FLT_MAX);
}

__device__ static BoundBox union_aabb(const float3 &pt_min1, const float3 &pt_max1, const float3 &pt_min2, const float3 &pt_max2) {
    BoundBox ret = {
        .pt_min = vec_min(pt_min1, pt_min2),
        .pt_max = vec_max(pt_max1, pt_max2)
    };
    return ret;
}

__device__ BoundBox union_box_aabb(const BoundBox &a, BoundBoxes *boxes, uint32_t box_index) {
    return union_aabb(a.pt_min, a.pt_max, boxes->pt_min[box_index], boxes->pt_max[box_index]);
}

__device__ BoundBox union_box_box(const BoundBox &a, const BoundBox &b) {
    return union_aabb(a.pt_min, a.pt_max, b.pt_min, b.pt_max);
}

__device__ BoundBox union_boxes(BoundBoxes *boxes, uint32_t first_index, uint32_t second_index) {
    return union_aabb(boxes->pt_min[first_index], boxes->pt_max[first_index], boxes->pt_min[second_index], boxes->pt_max[second_index]);
}

__device__ BoundBox union_box_point(BoundBoxes *boxes, uint32_t box_index, float3 point) {
    BoundBox ret;
    ret.pt_min = vec_min(boxes->pt_min[box_index], point);
    ret.pt_max = vec_max(boxes->pt_max[box_index], point);
    return ret;
}

__device__ BoundBox intersect_boxes(BoundBoxes *boxes, uint32_t first_index, uint32_t second_index) {
    BoundBox ret;
    ret.pt_min = vec_max(boxes->pt_min[first_index], boxes->pt_min[second_index]);
    ret.pt_max = vec_min(boxes->pt_max[first_index], boxes->pt_max[second_index]);
    return ret;
}

__device__ bool overlaps_boxes(BoundBoxes *boxes, uint32_t first_index, uint32_t second_index) {
    bool x = (boxes->pt_max[first_index].x >= boxes->pt_min[second_index].x && boxes->pt_min[first_index].x <= boxes->pt_max[second_index].x);
    bool y = (boxes->pt_max[first_index].y >= boxes->pt_min[second_index].y && boxes->pt_min[first_index].y <= boxes->pt_max[second_index].y);
    bool z = (boxes->pt_max[first_index].z >= boxes->pt_min[second_index].z && boxes->pt_min[first_index].z <= boxes->pt_max[second_index].z);
    return x && y && z;
}

__device__ float3 centroid(BoundBoxes *boxes, uint32_t box_index) {
    return add_vec(scale_vec(0.5, boxes->pt_min[box_index]), scale_vec(0.5, boxes->pt_max[box_index]));
}

__device__ float3 diagonal(BoundBoxes *boxes, uint32_t box_index) {
    return sub_vec(boxes->pt_max[box_index], boxes->pt_min[box_index]);
}

__device__ float surface_area(BoundBoxes *boxes, uint32_t box_index) {
    float3 diag = diagonal(boxes, box_index);
    return 2 * (diag.x * diag.y + diag.x * diag.z + diag.y * diag.z);
}

__device__ int longest_dimension(BoundBoxes *boxes, uint32_t box_index) {
    float3 diag = diagonal(boxes, box_index);
    if (diag.x > diag.y && diag.x > diag.z) {
        return 0;
    } else if (diag.y > diag.z) {
        return 1;
    } else {
        return 2;
    }
}

__device__ float3 offset(const BoundBox &box, const float3 &point) {
    float3 dev = sub_vec(point, box.pt_min);
    if (box.pt_max.x > box.pt_min.x) {
        dev.x /= box.pt_max.x - box.pt_min.x;
    }
    if (box.pt_max.y > box.pt_min.y) {
        dev.y /= box.pt_max.y - box.pt_min.y;
    }
    if (box.pt_max.z > box.pt_min.z) {
        dev.z /= box.pt_max.z - box.pt_min.z;
    }
    return dev;
}

__device__ bool inside(BoundBoxes *boxes, uint32_t box_index, float3 point) {
    bool x = point.x >= boxes->pt_min[box_index].x && point.x <= boxes->pt_max[box_index].x;
    bool y = point.y >= boxes->pt_min[box_index].y && point.y <= boxes->pt_max[box_index].y;
    bool z = point.z >= boxes->pt_min[box_index].z && point.z <= boxes->pt_max[box_index].z;
    return x && y && z;
}

__device__ bool is_empty(BoundBoxes *boxes, uint32_t box_index) {
    return boxes->pt_min[box_index].x >= boxes->pt_max[box_index].x || boxes->pt_min[box_index].y >= boxes->pt_max[box_index].y || boxes->pt_min[box_index].z >= boxes->pt_max[box_index].z;
}

void free_boundbox(BoundBoxes &boxes) {
    cudaFree(boxes.pt_min);
    cudaFree(boxes.pt_max);
}

__device__ void free_boundbox_dev(BoundBoxes &boxes) {
    free(boxes.pt_min);
    free(boxes.pt_max);
}

/* 
PRE: Ray direction is NOT axis-aligned
POST: Parameter for "near" intersection, FLT_MAX if ray does not go through bounding box
*/
__device__ float intersect_bounding_boxes(float3 ray_pt, float3 ray_dir, float3 pt_min, float3 pt_max) {
    // (Quickly) Precompute component-wise reciprocal of ray direction
    float3 dir_inv = make_float3(
        __frcp_rn(ray_dir.x),
        __frcp_rn(ray_dir.y),
        __frcp_rn(ray_dir.z)
    );


    // Calculate bounding paramaters for x
    float ray_dir_div_x = -ray_pt.x * dir_inv.x; // factor out -pt.x/dir.x
    float t_near_x = fmaf(pt_min.x, dir_inv.x, ray_dir_div_x);
    float t_far_x = fmaf(pt_max.x, dir_inv.x, ray_dir_div_x);

    float t_near = fminf(t_near_x, t_far_x);
    float t_far = fmaxf(t_near_x, t_far_x);

    // Calculate bounding parameters for y
    float ray_dir_div_y = -ray_pt.y * dir_inv.y;
    float t_near_y_temp = fmaf(pt_min.y, dir_inv.y, ray_dir_div_y);
    float t_far_y_temp = fmaf(pt_max.y, dir_inv.y, ray_dir_div_y);

    float t_near_y = fminf(t_near_y_temp, t_far_y_temp);
    float t_far_y = fmaxf(t_near_y_temp, t_far_y_temp);

    // Calculate bounding paramaters for z
    float ray_dir_div_z = -ray_pt.z * dir_inv.z;
    float t_near_z_temp = fmaf(pt_min.z, dir_inv.z, ray_dir_div_z);
    float t_far_z_temp = fmaf(pt_max.z, dir_inv.z, ray_dir_div_z);

    float t_near_z = fminf(t_near_z_temp, t_far_z_temp);
    float t_far_z = fmaxf(t_near_z_temp, t_far_z_temp);

    // Intersect previous range with z range
    t_near = fmaxf(t_near, fmaxf(t_near_y, t_near_z));
    t_far = fminf(t_far, fminf(t_far_y, t_far_z));

    // Check range is non-degenerate (i.e not empty or t_far not < 0)
    if (t_near > t_far || t_far < 0 || isnan(t_near) || isnan(t_far)) {
        return FLT_MAX;
    }
    
    // Return t_near regardless now.
    return t_near;

}

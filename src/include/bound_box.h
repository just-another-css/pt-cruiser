#ifndef BOUNDBOX_H
#define BOUNDBOX_H

#include <string.h>
#include "constants.h"
#include "math_utils.h"

#define SINGLE_BOUND_BOX_SIZE 2

typedef struct {
    // array of mins and maxs
    float3 *pt_min;
    float3 *pt_max;
} BoundBoxes;

typedef struct {
    float3 pt_min;
    float3 pt_max;
} BoundBox;

// Allocate memory for AABBs
extern void create_boundboxes(BoundBoxes &boxes, uint32_t capacity);
// Allocate device side boundboxes
extern void create_boundboxes_dev(BoundBoxes &boxes, uint32_t capacity);
// Initialize all bound boxes to pt_min = max, pt_max = min
extern __device__ void initialise_boundbox(BoundBox &box);
// Union between two bound boxes
// Return: a single BoundBox
extern __device__ BoundBox union_box_aabb(const BoundBox &a, BoundBoxes *boxes, uint32_t box_index);
// Union between two bound boxes
// Return: a single BoundBox
extern __device__ BoundBox union_box_box(const BoundBox &a, const BoundBox &b);
// Union between two bound boxes
// Return: a single BoundBox
extern __device__ BoundBox union_boxes(BoundBoxes *boxes, uint32_t first_index, uint32_t second_index);
// Union between a box and a point
// Return: a single BoundBox
extern __device__ BoundBox union_box_point(BoundBoxes *boxes, uint32_t box_index, float3 point);
// Intersection between two bound boxes
// Return: a single BoundBox
extern __device__ BoundBox intersect_boxes(BoundBoxes *boxes, uint32_t first_index, uint32_t second_index);
// Determine overlap between two bound boxes
extern __device__ bool overlaps_boxes(BoundBoxes *boxes, uint32_t first_index, uint32_t second_index);
// Compute the centroid of the given aabb
extern __device__ float3 centroid(BoundBoxes *boxes, uint32_t box_index);
// Calculate directional vector along the diagonal of a bound box
extern __device__ float3 diagonal(BoundBoxes *boxes, uint32_t box_index);
// Calculate surface area of a bound box
extern __device__ float surface_area(BoundBoxes *boxes, uint32_t box_index);
// Determine the longest axe
// 0: x; 1: y; 2: z
extern __device__ int longest_dimension(BoundBoxes *boxes, uint32_t box_index);
// Compute the continuous position of a point relative to the min corner of a bound box, in the range of [(0,0,0), (1,1,1)]
extern __device__ float3 offset(const BoundBox &box, const float3 &point);
// Check if a point is within a bound box
extern __device__ bool inside(BoundBoxes *boxes, uint32_t box_index, float3 point);
// Check if a bound box is empty i.e. guaranteed no primitive inside
extern __device__ bool is_empty(BoundBoxes *boxes, uint32_t box_index);
// free BoundBoxes
extern void free_boundbox(BoundBoxes &boxes);
// free BoundBoxes device side
extern __device__ void free_boundbox_dev(BoundBoxes &boxes);

/* Returns the "far" parameter for intersection of a ray with a bounding box, this is negative if no intersection is found */
extern __device__ float intersect_bounding_boxes(float3 ray_pt, float3 ray_dir, float3 pt_min, float3 pt_max);

#endif

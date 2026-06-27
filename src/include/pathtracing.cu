#include "pathtracing.h"
#include <curand_kernel.h>
#include <math_constants.h>
#include <stdbool.h>
#include "bvh.h"
#include "materials.h"
#include "math_utils.h"
#include "objects.h"
#include "light_sources.h"
#include "lighting.h"

typedef struct {
    float3 pos;
    int obj_i, face_i;
    float u, v;
} ray_collision;

typedef struct {
    ray_collision rc;
    float t;
} ray_collision_t;

__global__ static void initialise_rand_states(int rand_seed, curandStatePhilox4_32_10_t* rand_states) {
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    if (x >= TILE_RAYS) return;
    curand_init(rand_seed, x, 0, rand_states + x);
}

// Calculate rays for each pixel with jitter; one thread per pixel
__global__ static void calc_pixel_rays(int tile, int cur_tile_pixels, float3 cam_dir, float3 view_x_dir, float3 view_y_dir, float3* top_left_corners, float3* left_rights, float3* top_bottoms) {
    // Find thread position in grid; corresponds to pixel position
    int i = blockIdx.x * blockDim.x + threadIdx.x; // x is the faster dimension in CUDA
    if (i >= cur_tile_pixels) return;
    int pixel_i = i + tile * TILE_PIXELS;
    if (pixel_i >= TOTAL_PIXELS) return;
    int y = pixel_i / X_RES, x = pixel_i - y * X_RES; // calculate x and y within tile
    // Calculate pixel top left corner
    float x_frac = fdividef(x, X_RES_HALF) - 1, // x and y position in normalised [-1,1] range
        y_frac = fdividef(y, Y_RES_HALF) - 1;
    float3 top_left = add_vec(scale_vec(x_frac, view_x_dir), scale_vec(y_frac, view_y_dir)); // top left of pixel
    // Calculate vectors for pixel edges (consider using adjacent threads to calculate?)
    float right_x_frac = fdividef(x + 1, X_RES_HALF) - 1, // right side of pixel in range [-1,1]
        bottom_y_frac = fdividef(y + 1, Y_RES_HALF) - 1; // bottom side of pixel in range [-1,1]
    float3 top_right = add_vec(scale_vec(right_x_frac, view_x_dir), scale_vec(y_frac, view_y_dir)); // top right of pixel
    float3 bottom_left = add_vec(scale_vec(x_frac, view_x_dir), scale_vec(bottom_y_frac, view_y_dir)); // bottom left of pixel
    float grid_scalar = __frcp_rd(PIXEL_RAY_GRID_DIM); // divide vectors along whole edges of pixels to scale to sample grid cells
    left_rights[i] = scale_vec(grid_scalar, sub_vec(top_right, top_left)); // vector from left to right edges of pixel grid cell
    top_bottoms[i] = scale_vec(grid_scalar, sub_vec(bottom_left, top_left)); // vector from top to bottom edges of pixel grid cell
    add_vec_ip(&top_left, cam_dir); // add camera offset to top left vector
    top_left_corners[i] = top_left;
}

__global__ static void calc_pixel_samples(int cur_tile_pixels, float3* top_left_corners, float3* left_rights, float3* top_bottoms, float3* ray_dirs, curandStatePhilox4_32_10_t* rand_states) {
    int pixel_i = blockIdx.y * blockDim.y + threadIdx.y;
    int sample = blockIdx.x * blockDim.x + threadIdx.x; // x is the faster dimension in CUDA
    if (pixel_i >= cur_tile_pixels || sample >= RAYS_PER_PIXEL) return;
    int ray_i = pixel_i * RAYS_PER_PIXEL + sample;
    int pixel_grid_row = sample / PIXEL_RAY_GRID_DIM; // possibly optimised by compiler
    int pixel_grid_col = sample - PIXEL_RAY_GRID_DIM * pixel_grid_row; // avoid costly modulus operation
    ray_dirs[ray_i] = norm_vec(add3_vec(top_left_corners[pixel_i], // overall pixel top left corner
                                        scale_vec(pixel_grid_col + curand_uniform(rand_states + ray_i), left_rights[pixel_i]), // random x/y offsets including pixel grid offset
                                        scale_vec(pixel_grid_row + curand_uniform(rand_states + ray_i), top_bottoms[pixel_i])));
}

__global__ static void initialise_ray_buffers(int cur_tile_rays, float3 ray_origin, float3* ray_origins, float3* ray_throughputs, float3* ray_values, float* ray_refr_inds, bool* ray_light_ints) {
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    if (x >= cur_tile_rays) return;
    ray_origins[x] = ray_origin;
    ray_throughputs[x] = make_float3(1, 1, 1);
    ray_values[x] = make_float3(0, 0, 0); // THIS 
    ray_refr_inds[x] = 1;
    ray_light_ints[x] = false;
}

__device__ static float find_triangle_intersection(float3 ray_origin, float3 ray_dir, TriangleMesh* mesh, int obj_i, int face_i, float* u, float* v) {
    // Use Moller-Trumbore method to find intersection
    float3 ab = mesh->ab[face_i], ac = mesh->ac[face_i];
    float3 ac_perp = vec_cross_prod(ray_dir, ac); // perpendicular to ray and vector AC
    float det = vec_dot_prod(ab, ac_perp); // determinant of intersection matrix
    if (fabsf(det) < EPSILON) return FLT_MAX;
    float inv_det = __frcp_rn(det);
    float3 a_to_ray = sub_vec(ray_origin, mesh->a[face_i]);
    *u = inv_det * vec_dot_prod(a_to_ray, ac_perp);
    if (*u < 0 || *u > 1) return FLT_MAX;
    float3 ab_perp = vec_cross_prod(a_to_ray, ab); // perpendicular to ray and vector AB
    *v = inv_det * vec_dot_prod(ray_dir, ab_perp);
    if (*v < 0 || *u + *v > 1) return FLT_MAX;
    float t = inv_det * vec_dot_prod(ac, ab_perp);
    if (t < 0) return FLT_MAX;
    return t;
}

// Return information for first collision
__device__ static ray_collision find_first_collision(float3 ray_origin, float3 ray_dir) {
    // Traverse BVH with a stack
    int bvh_stack[64], stack_i = 0;
    float bvh_stack_t[64];
    ray_collision_t rct;
    rct.rc.obj_i = -1; // start with failed intersection
    rct.t = FLT_MAX; // any collision will be closer
    bvh_stack[0] = 0; // start at root node
    bvh_stack_t[0] = intersect_bounding_boxes(ray_origin, ray_dir, bvh_dev.aabbs.pt_min[0], bvh_dev.aabbs.pt_max[0]);
    // if (blockIdx.x * blockDim.x + threadIdx.x == 0) printf("in ffc, starting ffc-ing\n");
    while (stack_i >= 0) {
        // if (blockIdx.x * blockDim.x + threadIdx.x == 0) printf("in ffc, at stack %d\n", stack_i);
        if (stack_i > 60) printf("WARNING: TALL STACK - %d\n", stack_i);
        if (stack_i >= 62) {
            printf("FAILURE: TOO TALL STACK - %d; exiting with t %f\n", stack_i, rct.t);
            rct.rc.pos = add_vec(ray_origin, scale_vec(rct.t, ray_dir));
            return rct.rc;
        }
        int i = bvh_stack[stack_i];
        // if (blockIdx.x * blockDim.x + threadIdx.x == 0) printf("in ffc, got node %d\n", i);
        float t = bvh_stack_t[stack_i--];
        // if (blockIdx.x * blockDim.x + threadIdx.x == 0) printf("we made it here (accessing bvh_stack_t) without segfaulting, index is %d\n", i);
        if (t >= rct.t) continue;
        // if (blockIdx.x * blockDim.x + threadIdx.x == 0) printf("making an access to mesh_index (which is p) at address p (fake)\n");
        int obj_i = bvh_dev.mesh_index[i]; 
        // if (blockIdx.x * blockDim.x + threadIdx.x == 0) printf("we checked bvh dev mesh index at index %d and got obj_i %d \n", i, obj_i);
        if (obj_i >= 0) { // leaf node
            // if (blockIdx.x * blockDim.x + threadIdx.x == 0) printf("in ffc, found a leaf!! the greenery is beautiful\n");
            int face_i = bvh_dev.triangle_index[i];
            float u, v;
            float t_int = find_triangle_intersection(ray_origin, ray_dir, objects_dev.meshes + obj_i, obj_i, face_i, &u, &v);
            // if (blockIdx.x * blockDim.x + threadIdx.x == 0) printf("in ffc, the greenery about yey far away: %f\n", t_int);
            if (t_int < rct.t) {
                // if (blockIdx.x * blockDim.x + threadIdx.x == 0) printf("in ffc, the greenery is pretty close, %f\n", t_int);
                rct.t = t_int;
                rct.rc.obj_i = obj_i;
                rct.rc.face_i = face_i;
                rct.rc.u = u;
                rct.rc.v = v;
            }
        } else { // parent node
            // if (blockIdx.x * blockDim.x + threadIdx.x == 0) printf("in ffc, found a parent, i guess...\n");
            int left = bvh_dev.left_child_index[i], right = bvh_dev.right_child_index[i];
            float left_t = intersect_bounding_boxes(ray_origin, ray_dir, bvh_dev.aabbs.pt_min[left], bvh_dev.aabbs.pt_max[left]);
            float right_t = intersect_bounding_boxes(ray_origin, ray_dir, bvh_dev.aabbs.pt_min[right], bvh_dev.aabbs.pt_max[right]);
            // if (blockIdx.x * blockDim.x + threadIdx.x == 0) printf("in ffc, collided with children (suspicious)\n");
            bool use_left = left_t < rct.t;
            bool use_right = right_t < rct.t;
            if (!use_left && !use_right) continue;
            bool left_closer = left_t < right_t;
            if (use_right && left_closer) { // left < right < t
                bvh_stack[++stack_i] = right;
                bvh_stack_t[stack_i] = right_t;
                bvh_stack[++stack_i] = left;
                bvh_stack_t[stack_i] = left_t;
            } else if (use_right && use_left) { // right < left < t
                bvh_stack[++stack_i] = left;
                bvh_stack_t[stack_i] = left_t;
                bvh_stack[++stack_i] = right;
                bvh_stack_t[stack_i] = right_t;
            } else if (use_right) { // right < t < left
                bvh_stack[++stack_i] = right;
                bvh_stack_t[stack_i] = right_t;
            } else if (use_left) { // left < t < right
                bvh_stack[++stack_i] = left;
                bvh_stack_t[stack_i] = left_t;
            }
        }
    }
    //rct.rc.obj_i == GLASS ? rct.rc.pos = add_vec(ray_origin, scale_vec(rct.t + EPSILON, ray_dir)) : rct.rc.pos = add_vec(ray_origin, scale_vec(rct.t - EPSILON, ray_dir));
    rct.rc.obj_i != -1 && objects_dev.meshes[rct.rc.obj_i].materials[rct.rc.face_i] == GLASS ? rct.rc.pos = add_vec(ray_origin, scale_vec(rct.t + EPSILON, ray_dir)) : rct.rc.pos = add_vec(ray_origin, scale_vec(rct.t - EPSILON, ray_dir));
    // rct.rc.pos = add_vec(ray_origin, scale_vec(rct.t, ray_dir));
    // if (blockIdx.x * blockDim.x + threadIdx.x == 0) printf("finished ffc lesgoo!!!\n");
    return rct.rc;
}

// Return the object index of a random light source, weighted by intensity
__device__ static int find_rand_light_source(curandStatePhilox4_32_10_t* rand_state, int* light_source_i, float* light_source_intensity) {
    float target = curand_uniform(rand_state); // random value in range (0,1] representing selected cumulative normalised light source intensity
    // TODO: binary search to find light source?
    int i_limit = light_sources_dev.num_light_sources;
    for (int i = 0; i < i_limit; i++) if (light_sources_dev.cum_norm_intensities[i] >= target) {
        *light_source_i = i;
        *light_source_intensity = light_sources_dev.norm_intensities[i];
        return light_sources_dev.obj_is[i];
    }
    *light_source_i = i_limit - 1;
    *light_source_intensity = light_sources_dev.norm_intensities[i_limit - 1];
    return light_sources_dev.obj_is[i_limit - 1]; // should be unreachable; catch-all case added to ensure valid return vlaue
}

__device__ static __forceinline__ float3 calc_rand_ray(int light_source_i, int obj_i, float3 ray_origin, curandStatePhilox4_32_10_t* rand_state) {
    // Select random triangle uniformly to cast ray towards
    TriangleMesh *mesh = objects_dev.meshes + obj_i;
    int tri_count = mesh->triangle_count;
    int face_i = tri_count - 1; // min((int)(curand_uniform(rand_state) * mesh->triangle_count), mesh->triangle_count - 1); // all triangles included
    float target = curand_uniform(rand_state);
    float* cum_norm_triangle_areas = light_sources_dev.cum_norm_triangle_areas[light_source_i];
    for (int i = 0; i < tri_count; i++) if (cum_norm_triangle_areas[i] >= target) {
        face_i = i;
        break;
    }
    float u = curand_uniform(rand_state);
    float v = curand_uniform(rand_state);
    if (u + v > 1.0f) { u = 1.0f - u; v = 1.0f - v; } // fold back into triangle
    float3 point = add3_vec(
        mesh->a[face_i],
        scale_vec(u, mesh->ab[face_i]),
        scale_vec(v, mesh->ac[face_i]));
    return sub_vec(point, ray_origin);
}

__device__ static float3 calc_next_ray_dir(float3 ray_dir, ray_collision ray_int, float* ray_refr_ind, Material material, curandStatePhilox4_32_10_t* rand_state) {
    // Check if transparent; if so, check random; if over threshold, refract based on material data
    float transparency = materials_data.transparencies[material];
    float3 normal = f4_to_f3(objects_dev.meshes[ray_int.obj_i].normals[ray_int.face_i]);
    // if (vec_dot_prod(ray_dir, normal) > 0) scale_vec_ip(-1.0f, &normal); // always face toward incoming ray
    if (transparency > 0) {
        // --- Refraction case ---
        // `normal` here already faces against the incoming ray (dot(ray_dir, normal) < 0).
        // We need the geometric normal to tell entering from exiting.
        float3 geo_normal = f4_to_f3(objects_dev.meshes[ray_int.obj_i].normals[ray_int.face_i]);
        // bool entering = vec_dot_prod(ray_dir, geo_normal) < 0;

        float eta_i = *ray_refr_ind;                                  // current medium
        bool entering = eta_i <= 1.0f;
        float eta_t = entering ? materials_data.refractive_indices[material] // entering glass
                            : 1.0f;                               // exiting to air
        float refr_ratio = fdividef(eta_i, eta_t);

        float norm_dot_ray = vec_dot_prod(normal, ray_dir);          // negative (normal faces against ray)
        float cosi = -norm_dot_ray;                                  // positive
        float k = 1.0f - refr_ratio * refr_ratio * (1.0f - cosi * cosi);

        if (k < 0.0f && !entering) {
            // Total internal reflection: reflect, do NOT change the medium index
            return sub_vec(ray_dir, scale_vec(2.0f * norm_dot_ray, normal));
        }

        // Successful refraction: update the medium the ray is now travelling in
        *ray_refr_ind = eta_t;

        return add_vec(
            scale_vec(refr_ratio, ray_dir),
            scale_vec(refr_ratio * cosi - sqrtf(k), normal)
        );
    }
    // Diffuse ray with cosine distribution
    float z = fmaf(curand_uniform(rand_state), 2, -1); // z component of random offset vector; determines size of circular slice of sphere
    float angle = curand_uniform(rand_state) * CUDART_PI_F * 2; // angle of random offset vector in circular slice determined by z
    float radius = sqrtf(1 - z * z); // radius of circular slice of sphere
    float3 diffuse_ray = norm_vec_safe(add_vec(normal, make_float3(radius * cosf(angle), radius * sinf(angle), z))); // add to normal vector and normalise for Lambertian distribution

    // Reflection ray with roughness
    float3 specular_ray = sub_vec(ray_dir, scale_vec(2 * vec_dot_prod(ray_dir, normal), normal)); // cast ray for pure reflection for later offset
    // float cone_angle = asinf(curand_uniform(rand_state) * materials_data.roughnesses[material]); // select an angle between 0 and roughness
    // float ray_cone_angle = 2 * CUDART_PI_F * curand_uniform(rand_state); // choose a second angle
    
    // // create arbitrary orthonormal basis based on z axis
    float3 ortho_fst = scale_vec(rsqrtf(fmaf(specular_ray.y, specular_ray.y, specular_ray.x * specular_ray.x)), make_float3(-specular_ray.y, specular_ray.x, 0));
    float3 ortho_snd = vec_cross_prod(specular_ray, ortho_fst);
    scale_vec_ip(rsqrtf(vec_dot_sqr(ortho_snd)), &ortho_snd);

    // // calculate final reflection ray
    // float sin_theta = sinf(cone_angle);
    // float cos_theta = cosf(cone_angle);
    // float sin_phi = sinf(ray_cone_angle);
    // float cos_phi = cosf(ray_cone_angle);
    // float3 reflection_ray = make_float3( 
    //     fmaf(cos_theta, specular_ray.x, sin_theta * fmaf(cos_phi, ortho_fst.x, sin_phi * ortho_snd.x)),
    //     fmaf(cos_theta, specular_ray.y, sin_theta * fmaf(cos_phi, ortho_fst.y, sin_phi * ortho_snd.y)),
    //     fmaf(cos_theta, specular_ray.z, sin_theta * fmaf(cos_phi, ortho_fst.z, sin_phi * ortho_snd.z))
    // );
    float smoothness = materials_data.smoothnesses[material];
    float n = smoothness / (1.0f - smoothness);          // same n as the BRDF
    float u1 = curand_uniform(rand_state);
    float u2 = curand_uniform(rand_state);
    float cos_theta = powf(u1, 1.0f / (n + 1.0f));        // Phong-lobe polar angle
    float sin_theta = sqrtf(fmaxf(0.0f, 1.0f - cos_theta * cos_theta));
    float phi = 2.0f * CUDART_PI_F * u2;
    float sin_phi = sinf(phi);
    float cos_phi = cosf(phi);
    // build direction in the frame around `specular_ray` (the mirror direction),
    // using your existing ortho_fst / ortho_snd basis:
    float3 reflection_ray = make_float3(
        fmaf(cos_theta, specular_ray.x, sin_theta * fmaf(cosf(phi), ortho_fst.x, sinf(phi) * ortho_snd.x)),
        fmaf(cos_theta, specular_ray.y, sin_theta * fmaf(cosf(phi), ortho_fst.y, sinf(phi) * ortho_snd.y)),
        fmaf(cos_theta, specular_ray.z, sin_theta * fmaf(cosf(phi), ortho_fst.z, sinf(phi) * ortho_snd.z)));

    // float3 reflection_ray_ = add_vec(scale_vec(cosf(cone_angle), specular_ray), 
    //                                  scale_vec(sinf(cone_angle), add_vec(scale_vec(cosf(ray_cone_angle), ortho_fst),
    //                                                                      scale_vec(sinf(ray_cone_angle), ortho_snd))));

    // sanity check that ray doesn't go through the surface, otherwise flip phi
    if (vec_dot_prod(reflection_ray, normal) <= 0) {
        // sin is unchanged, modify cos
        cos_phi *= -1; // cos(pi - x) = -cos(x)
        reflection_ray = make_float3( 
            fmaf(cos_theta, specular_ray.x, sin_theta * fmaf(cos_phi, ortho_fst.x, sin_phi * ortho_snd.x)),
            fmaf(cos_theta, specular_ray.y, sin_theta * fmaf(cos_phi, ortho_fst.y, sin_phi * ortho_snd.y)),
            fmaf(cos_theta, specular_ray.z, sin_theta * fmaf(cos_phi, ortho_fst.z, sin_phi * ortho_snd.z))
        );
    }

    // Select ray for new direction
    return curand_uniform(rand_state) >= smoothness ? diffuse_ray : reflection_ray;
    // return make_float3(0, 0, 0);
}

__device__ static __forceinline__ float calc_term_threshold(float3 throughput) {
    return 1.0f - fminf(1, fmaxf(fmaxf(throughput.x, throughput.y), throughput.z));
}

/* @brief Execute one step of pathtracing for associated ray; one thread per ray
 * @param ray_dirs Array of all ray direction vectors
 * @param ray_origins Array of all ray position vectors
 * @param ray_throughputs Array of last ray throughput (RGB value)
 * @param ray_values Array of current colurs of rays
 * @param ray_refr_inds Array of refractive indices of current media of rays
 * @param rand_states Array of Philox cuRAND states for Russian roulette
 * @param next_step Flag to continue pathtracing; stored in pinned host memory
 * @param first_step Flag to optionally write to buffer if light source intersected
 * @param ray_light_ints Array of bools representing if the corresponding ray intersected a light source
*/
__global__ static void pathtrace_step(int cur_tile_rays, float3* ray_dirs, float3* ray_origins, float3* ray_throughputs, ray_collision* last_ray_collisions, float3* ray_values, float* ray_refr_inds, curandStatePhilox4_32_10_t* rand_states, bool* next_step, bool first_step, bool do_rr, bool *ray_light_ints) {
    // Find thread position in grid; corresponds to ray index
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    if (x >= cur_tile_rays) return;
    curandStatePhilox4_32_10_t *rand_state = rand_states + x;
    float3 ray_origin = ray_origins[x], ray_dir = ray_dirs[x], ray_thrput = ray_throughputs[x]; // copy values for faster access
    if (zero_vec(ray_thrput)) return;
    // Sample a light source with NEE if not on the first step
    if (!first_step) {
        // if (!x) printf("in step, starting NEE\n");
        int light_source_i;
        float light_source_intensity;
        int light_source_obj_i = find_rand_light_source(rand_state, &light_source_i, &light_source_intensity); // get a random light source
        float3 light_source_ray = calc_rand_ray(light_source_i, light_source_obj_i, ray_origin, rand_state); // calculate a random vector towards the light source
        float3 norm_light_source_ray = norm_vec(light_source_ray);
        ray_collision light_source_ray_rc = find_first_collision(ray_origin, norm_light_source_ray); // check first object in ray direction
        // if (!x) printf("in step, sampled, applying\n");
        if (light_source_ray_rc.obj_i == light_source_obj_i) { // if equal to light source, add contribution
            ray_collision last_ray_collision = last_ray_collisions[x];
            TriangleMesh* light_source_mesh = objects_dev.meshes + light_source_obj_i;
            float2 light_source_uv = add3_vec2(light_source_mesh->uv_a[light_source_ray_rc.face_i], scale_vec2(light_source_ray_rc.u, light_source_mesh->uv_ab[light_source_ray_rc.face_i]), scale_vec2(light_source_ray_rc.v, light_source_mesh->uv_ac[light_source_ray_rc.face_i]));
            ray_values[x] = add_vec(ray_values[x], multiply3_vec(scale_vec(calc_next_throughput_nee(ray_dir, objects_dev.meshes[last_ray_collision.obj_i].normals[last_ray_collision.face_i], norm_light_source_ray, objects_dev.meshes[last_ray_collision.obj_i].materials[last_ray_collision.face_i]) *
                                                                           fabsf(vec_dot_prod(norm_light_source_ray, f4_to_f3(light_source_mesh->normals[light_source_ray_rc.face_i]))) * // cos(angle between ray and light face normal)
                                                                           light_sources_dev.total_triangle_areas[light_source_i] * // inv. of probability of selecting triangle
                                                                           __frcp_rn(vec_dot_sqr(light_source_ray) * // divide by distance to light
                                                                                     light_source_intensity), // inv. of probability of selecting light source
                                                                           ray_thrput), // use material BRDF and NEE ray
                                                                 objects_dev.lightings[light_source_obj_i], // use object lighting modifier
                                                                 f4_to_f3(tex2D<float4>(materials_data.textures[light_source_mesh->materials[light_source_ray_rc.face_i]], light_source_uv.x, light_source_uv.y)))); // sample light source texture
        }
    }
    // if (!x) printf("in step, starting pathtracing\n");
    // Find current ray intersection
    ray_collision ray_int = find_first_collision(ray_origin, ray_dir);
    if (ray_int.obj_i == -1) { // ray extends to infinity
        ray_throughputs[x] = make_float3(0,0,0);
        return;
    }
    TriangleMesh *ray_int_mesh = objects_dev.meshes + ray_int.obj_i;
    Material material = ray_int_mesh->materials[ray_int.face_i];
    // if (!x) printf("in step, the ray lived!!");
    float3 light_output = objects_dev.lightings[ray_int.obj_i];
    // Calculate normalised UV coordinate for texture sampling
    float2 ray_int_uv = add3_vec2(ray_int_mesh->uv_a[ray_int.face_i], scale_vec2(ray_int.u, ray_int_mesh->uv_ab[ray_int.face_i]), scale_vec2(ray_int.v, ray_int_mesh->uv_ac[ray_int.face_i]));
    float3 texture_value = f4_to_f3(tex2D<float4>(materials_data.textures[material], ray_int_uv.x, ray_int_uv.y));
    // Check if object is a light
    if (first_step && nonzero_vec(light_output)) {
        // if (!x) printf("in step, the ray lived in the light\n");
        ray_values[x] = add_vec(ray_values[x], multiply3_vec(ray_thrput, light_output, texture_value));
        ray_light_ints[x] = true;
    }
    // if (!x) printf("in step, the ray is figuring out its future\n");
    // Calculate new ray direction
    float3 new_ray_dir = calc_next_ray_dir(ray_dir, ray_int, ray_refr_inds + x, material, rand_state);
    // Calculate new throughput with BRDF
    ray_thrput = multiply_vec(scale_vec(calc_next_throughput(ray_dir, ray_int_mesh->normals[ray_int.face_i], new_ray_dir, material), ray_thrput), // use material BRDF
                              texture_value); // load pixel from texture
    // if (!x) printf("in step, the ray is moving on");
    // Russian roulette
    float term_thrshld = calc_term_threshold(ray_thrput); // calculate probability threshold for termination
    // if (curand_uniform(rand_state) < term_thrshld) {
    //     // if (!x) printf("in step, the ray died, so sad\n");
    //     return;
    // }
    if (do_rr) {
        if (curand_uniform(rand_state) < term_thrshld) { // ray killed, early exit
            ray_throughputs[x] = make_float3(0,0,0);
            return;
        }
        scale_vec_ip(__frcp_rn(1 - term_thrshld), &ray_thrput); // account for killed rays
    }
    // if (!x) printf("in step, the ray has mourned\n");
    // Assign new ray dir/pos/throughput for next step
    ray_dirs[x] = new_ray_dir;
    ray_origins[x] = ray_int.pos;
    ray_throughputs[x] = ray_thrput;
    last_ray_collisions[x] = ray_int;
    // if (!x) printf("in step, the ray has spoken (written but same thing)\n");
    // Signal to host to continue pathtracing
    *next_step = true;
}

__global__ static void calc_pixels(int tile, int cur_tile_pixels, float3* ray_values, bool* ray_light_ints, float3* pixels, float* light_ints) {
    int x = blockIdx.x * blockDim.x + threadIdx.x; // pixel index
    if (x >= cur_tile_pixels) return;
    int start = x * RAYS_PER_PIXEL; // multiply by number of rays per pixel
    x += tile * TILE_PIXELS; // shift to current tile
    float3 pixel_acc = ray_values[start];
    float light_acc = ray_light_ints[start];
    for (int i = 1; i < RAYS_PER_PIXEL; i++) {
        add_vec_ip(&pixel_acc, ray_values[start + i]);
        light_acc += ray_light_ints[start + i];
    }
    float div_rays_per_pixel = __frcp_rn(RAYS_PER_PIXEL);
    pixels[x] = scale_vec(div_rays_per_pixel, pixel_acc);
    light_ints[x] = light_acc * div_rays_per_pixel;
}

void pathtrace(float3 cam_pos, float3 cam_up, float3 cam_dir, float3* pixels, float* light_ints) {
    // Allocate all buffers before execution to allow for tiling
    curandStatePhilox4_32_10_t* rand_states;
    CUDA_CHECK(cudaMalloc(&rand_states, TILE_RAYS * sizeof(curandStatePhilox4_32_10_t)));
    float3 *top_left_corners, *left_rights, *top_bottoms, *ray_dirs;
    CUDA_CHECK(cudaMalloc(&top_left_corners, TILE_PIXELS * sizeof(float3)));
    CUDA_CHECK(cudaMalloc(&left_rights, TILE_PIXELS * sizeof(float3)));
    CUDA_CHECK(cudaMalloc(&top_bottoms, TILE_PIXELS * sizeof(float3)));
    CUDA_CHECK(cudaMalloc(&ray_dirs, TILE_RAYS * sizeof(float3)));
    float3 *ray_origins, *ray_throughputs, *ray_values;
    CUDA_CHECK(cudaMalloc(&ray_origins, TILE_RAYS * sizeof(float3)));
    CUDA_CHECK(cudaMalloc(&ray_throughputs, TILE_RAYS * sizeof(float3)));
    CUDA_CHECK(cudaMalloc(&ray_values, TILE_RAYS * sizeof(float3)));
    ray_collision* last_ray_collisions;
    CUDA_CHECK(cudaMalloc(&last_ray_collisions, TILE_RAYS * sizeof(ray_collision)));
    float* ray_refr_inds;
    CUDA_CHECK(cudaMalloc(&ray_refr_inds, TILE_RAYS * sizeof(float)));
    bool* ray_light_ints;
    CUDA_CHECK(cudaMalloc(&ray_light_ints, TILE_RAYS * sizeof(bool)));
    bool *next_step, next_step_cpy;
    CUDA_CHECK(cudaMalloc(&next_step, sizeof(bool)));
    // Calculate view vectors
    float y_scale = tanf(Y_FOV * 0.5);
    float3 view_x_dir = norm_vec(vec_cross_prod(cam_dir, cam_up));
    float3 view_y_dir = scale_vec(y_scale, norm_vec(vec_cross_prod(cam_dir, view_x_dir)));
    scale_vec_ip(y_scale * X_RES / Y_RES, &view_x_dir);
    // Initialise RNG states
    {
        int block_size = 512;
        initialise_rand_states<<<(TILE_RAYS + block_size - 1) / block_size, block_size>>>(CUDA_RAND_SEED, rand_states);
    }
    CUDA_CHECK(cudaGetLastError());
    int num_tiles = (TOTAL_PIXELS + TILE_PIXELS - 1) / TILE_PIXELS, cur_tile_pixels, cur_tile_rays;
    // fprintf(stderr, "total pixles %d, tile pixels %d, num tiles %d\n", TOTAL_PIXELS, TILE_PIXELS, num_tiles);
    for (int tile = 0; tile < num_tiles; tile++) {
        cur_tile_pixels = min(TILE_PIXELS, TOTAL_PIXELS - tile * TILE_PIXELS);
        cur_tile_rays = cur_tile_pixels * RAYS_PER_PIXEL;
        // fprintf(stderr, "doing tile %d of %d, %d pixels and %d rays in tile\n", tile, num_tiles, cur_tile_pixels, cur_tile_rays);
        // Initialise initial rays
        {
            dim3 block_dim;
            block_dim.x = 64; // coalesce writes within 1D block
            dim3 grid_dim;
            grid_dim.x = (TILE_PIXELS + block_dim.x - 1) / block_dim.x;
            calc_pixel_rays<<<grid_dim, block_dim>>>(tile, cur_tile_pixels, cam_dir, view_x_dir, view_y_dir, top_left_corners, left_rights, top_bottoms);
        }
        CUDA_CHECK(cudaGetLastError());
        {
            dim3 block_dim;
            block_dim.x = 16; // ensure that block is fully utilised with small number of samples per pixel
            block_dim.y = 16;
            dim3 grid_dim;
            grid_dim.x = (RAYS_PER_PIXEL + block_dim.x - 1) / block_dim.x;
            grid_dim.y = (TILE_PIXELS + block_dim.y - 1) / block_dim.y;
            calc_pixel_samples<<<grid_dim, block_dim>>>(cur_tile_pixels, top_left_corners, left_rights, top_bottoms, ray_dirs, rand_states);
        }
        CUDA_CHECK(cudaGetLastError());
        // Initialise remaining buffers
        {
            int block_size = 512;
            initialise_ray_buffers<<<(TILE_RAYS + block_size - 1) / block_size, block_size>>>(cur_tile_rays, cam_pos, ray_origins, ray_throughputs, ray_values, ray_refr_inds, ray_light_ints);
        }
        CUDA_CHECK(cudaGetLastError());
        // Execute path tracing steps until all rays die
        next_step_cpy = true;
        for (int steps = 0; next_step_cpy && steps < RAY_BOUNCE_LIMIT; steps++) {
            // Run pathtracing step
            CUDA_CHECK(cudaMemset(next_step, 0, sizeof(bool)));
            int block_size = 32;
            pathtrace_step<<<(TILE_RAYS + block_size - 1) / block_size, block_size>>>(cur_tile_rays, ray_dirs, ray_origins, ray_throughputs, last_ray_collisions, ray_values, ray_refr_inds, rand_states, next_step, !steps, steps > 5, ray_light_ints);
            CUDA_CHECK(cudaGetLastError());
            // Check if next step required
            CUDA_CHECK(cudaMemcpy(&next_step_cpy, next_step, sizeof(bool), cudaMemcpyDeviceToHost));
            // fprintf(stderr, "finished bounce %d, next_step %d\n", steps, next_step_cpy);
        }
        CUDA_CHECK(cudaGetLastError());
        // Average final ray samples to produce final pixel values
        {
            int block_size = 512;
            calc_pixels<<<(TILE_PIXELS + block_size - 1) / block_size, block_size>>>(tile, cur_tile_pixels, ray_values, ray_light_ints, pixels, light_ints);
        }
        CUDA_CHECK(cudaGetLastError());
    }
    // Free buffers
    CUDA_CHECK(cudaFree(top_left_corners));
    CUDA_CHECK(cudaFree(left_rights));
    CUDA_CHECK(cudaFree(top_bottoms));
    CUDA_CHECK(cudaFree(rand_states));
    CUDA_CHECK(cudaFree(ray_dirs));
    CUDA_CHECK(cudaFree(ray_origins));
    CUDA_CHECK(cudaFree(ray_throughputs));
    CUDA_CHECK(cudaFree(ray_values));
    CUDA_CHECK(cudaFree(ray_refr_inds));
    CUDA_CHECK(cudaFree(ray_light_ints));
    CUDA_CHECK(cudaFree(next_step));
    // fputs("finished freeing, exiting\n", stderr);
    CUDA_CHECK(cudaGetLastError());
}

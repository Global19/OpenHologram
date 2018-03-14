/* CUDA Library Include */
#include "HologramPointCloud.h"


// for PointCloud
typedef struct KernelConst {
	int n_points;	///number of point cloud

	float scaleX;		/// Scaling factor of x coordinate of point cloud
	float scaleY;		/// Scaling factor of y coordinate of point cloud
	float scaleZ;		/// Scaling factor of z coordinate of point cloud

	float offsetDepth;	/// Offset value of point cloud in z direction

	int Nx;		/// Number of pixel of SLM in x direction
	int Ny;		/// Number of pixel of SLM in y direction

	float sin_thetaX; ///sin(tiltAngleX)
	float sin_thetaY; ///sin(tiltAngleY)
	float k;		  ///Wave Number = (2 * PI) / lambda;

	float pixel_x; /// Pixel pitch of SLM in x direction
	float pixel_y; /// Pixel pitch of SLM in y direction
	float halfLength_x; /// (pixel_x * nx) / 2
	float halfLength_y; /// (pixel_y * ny) / 2
} GpuConst;


__global__ void kernelCghPointCloud_cuda(float3 *PointCloud, float *amplitude, const GpuConst *Config, float *dst) {
	int idxX = blockIdx.x * blockDim.x + threadIdx.x;
	int idxY = blockIdx.y * blockDim.y + threadIdx.y;

	if ((idxX < Config->Nx) && (idxY < Config->Ny)) {
		for (int j = 0; j < Config->n_points; ++j) {
			//Convert to CUDA API Vector Data Type
			float3 ScalePoint3D;
			ScalePoint3D.x = PointCloud[j].x * Config->scaleX;
			ScalePoint3D.y = PointCloud[j].y * Config->scaleY;
			ScalePoint3D.z = PointCloud[j].z * Config->scaleZ + Config->offsetDepth;

			float3 PlanePoint = make_float3(0.f, 0.f, 0.f);
			PlanePoint.x = ((float)idxX + 0.5f) * Config->pixel_x - Config->halfLength_x;
			PlanePoint.y = Config->halfLength_y - ((float)idxY + 0.5f) * Config->pixel_y;

			float r = sqrtf((PlanePoint.x - ScalePoint3D.x)*(PlanePoint.x - ScalePoint3D.x) + (PlanePoint.y - ScalePoint3D.y)*(PlanePoint.y - ScalePoint3D.y) + ScalePoint3D.z*ScalePoint3D.z);
			float referenceWave = Config->k*Config->sin_thetaX*PlanePoint.x + Config->k*Config->sin_thetaY*PlanePoint.y;
			float result = amplitude[j] * cosf(Config->k*r - referenceWave);

			*(dst + idxX + idxY * Config->Nx) += result; //R-S Integral
		}
	}
	__syncthreads();
}


extern "C"
void cudaPointCloudKernel(const int block_x, const int block_y, const int thread_x, const int thread_y, float3 *PointCloud, float *amplitude, const GpuConst *Config, float *dst) {
	dim3 Dg(block_x, block_y, 1);  //grid : designed 2D blocks
	dim3 Db(thread_x, thread_y, 1);  //block : designed 2D threads

	kernelCghPointCloud_cuda << < Dg, Db >> > (PointCloud, amplitude, Config, dst);
}
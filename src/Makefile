NVCC 		= nvcc
CC 			= gcc
CFLAGS		= -Wall -g
CUDA_PATH 	= /vol/cuda/13.0.0
SRC			= main.cu
NVCCFLAGS	= -O3 -w
INCLUDES	= -I$(CUDA_PATH)/include
LIBS		= -L$(CUDA_PATH)/lib64 -lGL -lGLEW -lglfw -lcudart
BUILD		= render

all: $(BUILD)

clean:
	$(RM)

render: $(SRC)
	$(NVCC) $(NVCCFLAGS) $(SRC) $(INCLUDES) $(LIBS) -o render

.PHONY: all clean

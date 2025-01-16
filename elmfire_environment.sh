#!/bin/bash

# module purge ; module load Python grpcio wget csvkit GDAL netCDF-Fortran

export ELMFIRE_SCRATCH_BASE=/dev/shm/$USER/elmfire/scratch

export ELMFIRE_BASE_DIR=/work/kaplan_lab/projects/elmfire

export ELMFIRE_INSTALL_DIR=$ELMFIRE_BASE_DIR/build/linux/bin

export CLOUDFIRE_SERVER=172.92.17.198

export PATH=$PATH:$ELMFIRE_INSTALL_DIR
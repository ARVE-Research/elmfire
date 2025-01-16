#!/usr/bin/bash

source ../elmfire_environment.sh

# ------------------------------------------
# user set parameters

# simulation time in hours

simhours=24

# get the directory containing the input files from the first argument on the command line

domaindir=${1}

# should not need to modify anything below this line

# ------------------------------------------
# utility function replace_line

replace_line () {
   infile=$1
   match_pattern="$2"
   new_value="$3"
   is_string=$4

   line=`grep -n "$match_pattern" $infile | cut -d: -f1`
      
   sed -i "$line d" $infile
   if [ "$is_string" = "yes" ]; then
      sed -i "$line i $match_pattern = '$new_value'" $infile
   else
      sed -i "$line i $match_pattern = $new_value" $infile
   fi
}

# ------------------------------------------
# set the fixed values for the run parameters

NUM_FLOAT_RASTERS=7
FLOAT_RASTER[1]=ws   ; FLOAT_VAL[1]=15.0 # Wind speed, mph
FLOAT_RASTER[2]=wd   ; FLOAT_VAL[2]=0.0  # Wind direction, deg
FLOAT_RASTER[3]=m1   ; FLOAT_VAL[3]=3.0  # 1-hr   dead moisture content, %
FLOAT_RASTER[4]=m10  ; FLOAT_VAL[4]=4.0  # 10-hr  dead moisture content, %
FLOAT_RASTER[5]=m100 ; FLOAT_VAL[5]=5.0  # 100-hr dead moisture content, %
FLOAT_RASTER[6]=adj  ; FLOAT_VAL[6]=1.0  # Spread rate adjustment factor (-)
FLOAT_RASTER[7]=phi  ; FLOAT_VAL[7]=1.0  # Initial value of phi field

LH_MOISTURE_CONTENT=30.0 # Live herbaceous moisture content, percent
LW_MOISTURE_CONTENT=60.0 # Live woody moisture content, percent

# ------------------------------------------

# ELMFIRE_VER=${ELMFIRE_VER:-2024.0326}

# ----
# setup paths to input and output

jobname=${domaindir##*/}   # strip path from domain directory

# delete the jobname directory if it exists

if [ -e $jobname ] ; then rm -r $jobname ; fi 

# create directory for this job

mkdir $jobname

# create subdirectories for input and output

mkdir $jobname/inputs
mkdir $jobname/outputs

# and for scratch files in /dev/shm

mkdir -p $ELMFIRE_SCRATCH_BASE

# ----
# identify the fuel file

fuelfile=$domaindir/LC23_F40_240.tif

if [ ! -e $fuelfile ] 
then
  echo "ERROR: couldn't find the fuel file: $fuelfile"
  exit
fi

# ----
# create constant field files for wind speed, direction, fuel moisture, etc. using the fuel file as a template

for i in $(eval echo "{1..$NUM_FLOAT_RASTERS}"); do

  echo "creating inputs/${FLOAT_RASTER[i]}.tif with fixed value ${FLOAT_VAL[i]}"

  gdal_create -ot Float32 -if $fuelfile -burn ${FLOAT_VAL[i]} $jobname/inputs/${FLOAT_RASTER[i]}.tif

done

# move adj and phi files to the same folder as the other input rasters

mv $jobname/inputs/adj.tif $domaindir/.
mv $jobname/inputs/phi.tif $domaindir/.

# ----
# generate job file

jobfile=$jobname/$jobname.namelist

# copy template file to a fresh jobfile in the inputs folder

cp elmfire.namelist.template $jobfile

echo "generating jobfile $jobfile"

# read resolution, extents, and map projection from fuel file

xmin=`gdalinfo $fuelfile | grep 'Lower Left'  | cut -d'(' -f2 | cut -d, -f1 | xargs`
ymin=`gdalinfo $fuelfile | grep 'Lower Left'  | cut -d'(' -f2 | cut -d, -f2 | cut -d')' -f1 | xargs`
xmax=`gdalinfo $fuelfile | grep 'Upper Right' | cut -d'(' -f2 | cut -d, -f1 | xargs`
ymax=`gdalinfo $fuelfile | grep 'Upper Right' | cut -d'(' -f2 | cut -d, -f2 | cut -d')' -f1 | xargs`

a_srs=`gdalsrsinfo $fuelfile | grep PROJ.4 | cut -d: -f2 | xargs` # spatial reference system
cellsize=`gdalinfo $fuelfile | grep 'Pixel Size' | cut -d'(' -f2 | cut -d, -f1` # grid size in meter

# calculate simulation time in seconds

simulation_tstop=`echo "$simhours * 3600" | bc -l`

# insert the values collected above into job file

replace_line $jobfile FUELS_AND_TOPOGRAPHY_DIRECTORY $domaindir yes
replace_line $jobfile COMPUTATIONAL_DOMAIN_XLLCORNER $xmin no
replace_line $jobfile COMPUTATIONAL_DOMAIN_YLLCORNER $ymin no
replace_line $jobfile COMPUTATIONAL_DOMAIN_CELLSIZE  $cellsize no
replace_line $jobfile SIMULATION_TSTOP $simulation_tstop no
replace_line $jobfile DTDUMP $simulation_tstop no
replace_line $jobfile A_SRS "$a_srs" yes

replace_line $jobfile LH_MOISTURE_CONTENT $LH_MOISTURE_CONTENT no
replace_line $jobfile LW_MOISTURE_CONTENT $LW_MOISTURE_CONTENT no

replace_line $jobfile WEATHER_DIRECTORY $jobname/inputs yes

# ----
# loop over 5km sub-domain tiles

tilesize=5000   # in meters

# nested loop iterates through a grid of cells
# outer loop controls the longitude (x), and inner loop controls the latitude (y)
# Then calculates the bounding coordinates (lon0, lon1, lat0, lat1) using the minimum coordinates and grid res.

i=1

# for ((x=2;x<=11;x++))
for ((x=2;x<=2;x++))
do

  lon0=`echo "$xmin + $tilesize * ($x - 1)" | bc -l`
  lon1=`echo "$lon0 + $tilesize" | bc -l`

  for ((y=2;y<=3;y++))
  do
    
    tile=`printf %03i $i`

    printf " working on tile $tile out of 100\r" 1>&2 
    
    # create an ignition mask with zeroes everywhere
    
    ignfile=$domaindir/ignmask.tif
    
    gdal_create -ot Float32 -if $fuelfile -burn 0. $ignfile

    lat0=`echo "$ymin + $tilesize * ($y - 1)" | bc -l`
    lat1=`echo "$lat0 + $tilesize" | bc -l`
    
    # creates a GMT (Generic Mapping Tools) polygon file for the subject tile.
    # defines a square polygon using the calculated coordinates. 
    # File is named using the tile index i
    
    # define a square polygon from x to x+5000 and y to y+5000
    
    cat << EOF > $jobname/tilepolygon.gmt
# @VGMT1.0 @GPOLYGON
# @Jp"$a_srs"
>
$lon0 $lat0
$lon0 $lat1
$lon1 $lat1
$lon1 $lat0
EOF

    # 'rasterizes' the polygon into the corresponding raster tile. 
    # The polygon (square) is burned into the raster ignition mask file as a value of 1, 
    # while everything around it would be considered 0.
    
    gdal_rasterize -burn 1 $jobname/tilepolygon.gmt $ignfile
    
    rm $jobname/tilepolygon.gmt

    # create subdirectory for output for this tile and put this directory name into the job file
    
    outdir=$jobname/outputs/$tile
    
    mkdir $outdir
    
    replace_line $jobfile OUTPUTS_DIRECTORY $outdir yes
    
    # run the model
    
    elmfire $jobfile # runs the simulation
    
    # increment the loop counter

    let i++

  done
done

echo 1>&2


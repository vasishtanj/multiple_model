#!/usr/bin/env bash

# Copyright (C) 2018-2019 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

usage() {
    echo "Security barrier camera demo that showcases three models coming with the product"
    echo "-d name     specify the target device to infer on; CPU, GPU, FPGA or MYRIAD are acceptable. Sample will look for a suitable plugin for device specified"
    echo "-help            print help message"
    exit 1
}

error() {
    local code="${3:-1}"
    if [[ -n "$2" ]];then
        echo "Error on or near line $1: $2; exiting with status ${code}"
    else
        echo "Error on or near line $1; exiting with status ${code}"
    fi
    exit "${code}"
}
trap 'error ${LINENO}' ERR

target="CPU"

# parse command line options
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -h | -help | --help)
    usage
    ;;
    -d)
    target="$2"
    echo target = "${target}"
    shift
    ;;
    -sample-options)
    sampleoptions="$2 $3 $4 $5 $6"
    echo sample-options = "${sampleoptions}"
    shift
    ;;
    *)
    # unknown option
    ;;
esac
shift
done

ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

target_image_path="$ROOT_DIR/car_1.bmp"

run_again="Then run the script again\n\n"
dashes="\n\n###################################################\n\n"

if [[ -f /etc/centos-release ]]; then
    DISTRO="centos"
elif [[ -f /etc/lsb-release ]]; then
    DISTRO="ubuntu"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    DISTRO="macos"
fi

if [[ $DISTRO == "centos" ]]; then
    sudo -E yum install -y centos-release-scl epel-release
    sudo -E yum install -y gcc gcc-c++ make glibc-static glibc-devel libstdc++-static libstdc++-devel libstdc++ libgcc \
                           glibc-static.i686 glibc-devel.i686 libstdc++-static.i686 libstdc++.i686 libgcc.i686 cmake

    sudo -E rpm -Uvh http://li.nux.ro/download/nux/dextop/el7/x86_64/nux-dextop-release-0-1.el7.nux.noarch.rpm || true
    sudo -E yum install -y epel-release
    sudo -E yum install -y cmake ffmpeg gstreamer1 gstreamer1-plugins-base libusbx-devel

    # check installed Python version
    if command -v python3.5 >/dev/null 2>&1; then
        python_binary=python3.5
        pip_binary=pip3.5
    fi
    if command -v python3.6 >/dev/null 2>&1; then
        python_binary=python3.6
        pip_binary=pip3.6
    fi
    if [ -z "$python_binary" ]; then
        sudo -E yum install -y rh-python36 || true
        . scl_source enable rh-python36
        python_binary=python3.6
        pip_binary=pip3.6
    fi
elif [[ $DISTRO == "ubuntu" ]]; then
    printf "Run sudo -E apt -y install build-essential python3-pip virtualenv cmake libcairo2-dev libpango1.0-dev libglib2.0-dev libgtk2.0-dev libswscale-dev libavcodec-dev libavformat-dev libgstreamer1.0-0 gstreamer1.0-plugins-base\n"
    sudo -E apt update
    sudo -E apt -y install build-essential python3-pip virtualenv cmake libcairo2-dev libpango1.0-dev libglib2.0-dev libgtk2.0-dev libswscale-dev libavcodec-dev libavformat-dev libgstreamer1.0-0 gstreamer1.0-plugins-base
    python_binary=python3
    pip_binary=pip3

    system_ver=`cat /etc/lsb-release | grep -i "DISTRIB_RELEASE" | cut -d "=" -f2`
    if [ $system_ver = "18.04" ]; then
        sudo -E apt-get install -y libpng-dev
    else
        sudo -E apt-get install -y libpng12-dev
    fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
    # check installed Python version
    if command -v python3.7 >/dev/null 2>&1; then
        python_binary=python3.7
        pip_binary=pip3.7
    elif command -v python3.6 >/dev/null 2>&1; then
        python_binary=python3.6
        pip_binary=pip3.6
    elif command -v python3.5 >/dev/null 2>&1; then
        python_binary=python3.5
        pip_binary=pip3.5
    else
        python_binary=python3
        pip_binary=pip3
    fi
fi

if ! command -v $python_binary &>/dev/null; then
    printf "\n\nPython 3.5 (x64) or higher is not installed. It is required to run Model Optimizer, please install it. ${run_again}"
    exit 1
fi

if [[ $DISTRO == "macos" ]]; then
    $pip_binary install pyyaml requests
else
    sudo -E $pip_binary install pyyaml requests
fi

if [ -e "$ROOT_DIR/../../bin/setupvars.sh" ]; then
    setupvars_path="$ROOT_DIR/../../bin/setupvars.sh"
else
    printf "Error: setupvars.sh is not found\n"
fi
if ! . $setupvars_path ; then
    printf "Unable to run ./setupvars.sh. Please check its presence. ${run_again}"
    exit 1
fi

# Step 1. Downloading Intel models
printf "${dashes}"
printf "Downloading Intel models\n\n"

if [ "$target" = "MYRIAD" or "$target" = "HDDL" ]; then
    # MYRIAD supports networks with FP16 format only
    target_precision="FP16"
else
    target_precision="FP32"
fi
printf "target_precision = ${target_precision}\n"

downloader_path="${INTEL_OPENVINO_DIR}/deployment_tools/tools/model_downloader/downloader.py"
models_path="$HOME/openvino_models/ir/${target_precision}"

vehicle_license_plate_detection_model=vehicle-license-plate-detection-barrier-0106
vehicle_attributes_recognition_model=vehicle-attributes-recognition-barrier-0039
license_plate_recognition_model=license-plate-recognition-barrier-0001

if [ "$target_precision" = "FP16" ]; then
    vehicle_license_plate_detection_model=${vehicle_license_plate_detection_model}-fp16
    vehicle_attributes_recognition_model=${vehicle_attributes_recognition_model}-fp16
    license_plate_recognition_model=${license_plate_recognition_model}-fp16
fi

vehicle_license_plate_detection_model_path=${models_path}/Security/object_detection/barrier/0106/dldt/${vehicle_license_plate_detection_model}
vehicle_attributes_recognition_model_path=${models_path}/Security/object_attributes/vehicle/resnet10_update_1/dldt/${vehicle_attributes_recognition_model}
license_plate_recognition_model_path=${models_path}/Security/optical_character_recognition/license_plate/dldt/${license_plate_recognition_model}

if ! [ -f "${vehicle_license_plate_detection_model_path}.xml" ] && ! [ -f "${vehicle_license_plate_detection_model_path}.bin" ]; then
    printf "\nRun $downloader_path --name $vehicle_license_plate_detection_model --output_dir ${models_path}\n\n"
    $python_binary $downloader_path --name $vehicle_license_plate_detection_model --output_dir ${models_path}
else
    printf "\n${vehicle_license_plate_detection_model} have been loaded previously, skip loading model step."
fi

if ! [ -f "${vehicle_attributes_recognition_model_path}.xml" ] && ! [ -f "${vehicle_attributes_recognition_model_path}.bin" ]; then
    printf "\nRun $downloader_path --name $vehicle_attributes_recognition_model --output_dir ${models_path}\n\n"
    $python_binary $downloader_path --name $vehicle_attributes_recognition_model --output_dir ${models_path}
else
    printf "\n${vehicle_attributes_recognition_model} have been loaded previously, skip loading model step."
fi

if ! [ -f "${license_plate_recognition_model_path}.xml" ] && ! [ -f "${license_plate_recognition_model_path}.bin" ]; then
    printf "\nRun $downloader_path --name $license_plate_recognition_model --output_dir ${models_path}\n\n"
    $python_binary $downloader_path --name $license_plate_recognition_model --output_dir ${models_path}
else
    printf "\n${license_plate_recognition_model} have been loaded previously, skip loading model step.\n"
fi

# Step 2. Build samples
printf "${dashes}"
printf "Build Inference Engine samples\n\n"

samples_path="${INTEL_OPENVINO_DIR}/deployment_tools/inference_engine/samples"

if ! command -v cmake &>/dev/null; then
    printf "\n\nCMAKE is not installed. It is required to build Inference Engine samples. Please install it. ${run_again}"
    exit 1
fi

OS_PATH=$(uname -m)
NUM_THREADS="-j2"

if [ $OS_PATH == "x86_64" ]; then
  OS_PATH="intel64"
  NUM_THREADS="-j8"
fi

build_dir="$HOME/inference_engine_samples_build"
if [ -e $build_dir/CMakeCache.txt ]; then
	rm -rf $build_dir/CMakeCache.txt
fi
mkdir -p $build_dir
cd $build_dir
cmake -DCMAKE_BUILD_TYPE=Release $samples_path
make $NUM_THREADS security_barrier_camera_demo

# Step 3. Run samples
printf "${dashes}"
printf "Run Inference Engine security_barrier_camera demo\n\n"

binaries_dir="${build_dir}/${OS_PATH}/Release"
cd $binaries_dir

printf "Run ./security_barrier_camera_demo -d $target -d_va $target -d_lpr $target -i $target_image_path -m "${vehicle_license_plate_detection_model_path}.xml" -m_va "${vehicle_attributes_recognition_model_path}.xml" -m_lpr "${license_plate_recognition_model_path}.xml" ${sampleoptions}\n\n"
./security_barrier_camera_demo -d $target -d_va $target -d_lpr $target -i $target_image_path -m "${vehicle_license_plate_detection_model_path}.xml" -m_va "${vehicle_attributes_recognition_model_path}.xml" -m_lpr "${license_plate_recognition_model_path}.xml" ${sampleoptions}

printf "${dashes}"
printf "Demo completed successfully.\n\n"

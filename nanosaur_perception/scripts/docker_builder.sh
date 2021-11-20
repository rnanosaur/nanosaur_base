#!/bin/bash
# Copyright (C) 2021, Raffaello Bonghi <raffaello@rnext.it>
# All rights reserved
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 1. Redistributions of source code must retain the above copyright 
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. Neither the name of the copyright holder nor the names of its 
#    contributors may be used to endorse or promote products derived 
#    from this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND 
# CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, 
# BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS 
# FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, 
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; 
# OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, 
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE 
# OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, 
# EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

bold=`tput bold`
red=`tput setaf 1`
green=`tput setaf 2`
yellow=`tput setaf 3`
reset=`tput sgr0`

# Get the entry in the dpkg status file corresponding to the provied package name
# Prepend two newlines so it can be safely added to the end of any existing
# dpkg/status file.
get_dpkg_status() {
    echo -e "\n"
    awk '/Package: '"$1"'/,/^$/' /var/lib/dpkg/status
}

usage()
{
    if [ "$1" != "" ]; then
        echo "${red}$1${reset}" >&2
    fi

    local name=$(basename ${0})
    echo "nanosaur perception docker builder" >&2
    echo "" >&2
    echo "Commands:" >&2
    echo "  -v                      |  Verbose. Schow extra info " >&2
    echo "  -ci                     |  Build docker without cache " >&2
    echo "  --push                  |  Push docker. Need to be logged in " >&2
    echo "  --latest                |  Tag and push latest release" >&2
    echo "  --repo REPO_NAME        |  Set repository to push " >&2
    echo "  --branch BRANCH_DISTRO  |  Set tag from branch " >&2
    echo "  --base-image BASE_IMAGE |  Change base image to build. Default=${bold}$BASE_IMAGE_DEFAULT${reset}" >&2
}

main()
{
    local PLATFORM="$(uname -m)"
    # Check if is running on NVIDIA Jetson platform
    if [[ $PLATFORM != "aarch64" ]]; then
        echo "${red}Run this script only on ${bold}${green}NVIDIA${reset}${red} Jetson platform${reset}"
        exit 33
    fi

    local PUSH=false
    local VERBOSE=false
    local REPO_NAME="nanosaur/perception"
    local CI_BUILD=false
    local BRANCH_DISTRO="foxy"
    local LATEST=false
    # Base image
    local BASE_IMAGE=""
	# Decode all information from startup
    while [ -n "$1" ]; do
        case "$1" in
            -h|--help) # Load help
                usage
                exit 0
                ;;
            -v)
                VERBOSE=true
                ;;
            -ci)
                CI_BUILD=true
                ;;
            --repo)
                REPO_NAME=$2
                shift 1
                ;;
            --branch)
                BRANCH_DISTRO=$2
                shift 1
                ;;
            --latest)
                LATEST=true
                shift 1
                ;;
            --push)
                PUSH=true
                ;;
            --base-image)
                BASE_IMAGE=$2
                shift 1
                ;;
            *)
                usage "[ERROR] Unknown option: $1" >&2
                exit 1
                ;;
        esac
            shift 1
    done

    # Build tag
    local TAG="$BRANCH_DISTRO"

    if ! $PUSH ; then
        echo "- Extract Libraries info"
        local DPKG_STATUS=$(get_dpkg_status cuda-cudart-10-2)$(get_dpkg_status libcufft-10-2)
        if $VERBOSE ; then
            echo "${yellow} Libraries ${reset}"
            echo "$DPKG_STATUS"
        fi

        local CI_OPTIONS=""
        if $CI_BUILD ; then
            # Set no-cache and pull before build
            # https://newbedev.com/what-s-the-purpose-of-docker-build-pull
            CI_OPTIONS="--no-cache --pull"
        fi

        # Change base image
        local BASE_IMAGE_ARG=""
        if [ ! -z "$BASE_IMAGE" ] ; then
            echo "- ${yellow}Override base image with $BASE_IMAGE${reset}"
            BASE_IMAGE_ARG="--build-arg BASE_IMAGE=$BASE_IMAGE"
        fi

        echo "- Build repo ${green}$REPO_NAME:$TAG${reset}"
        docker build $CI_OPTIONS -t $REPO_NAME:$TAG --build-arg "DPKG_STATUS=$DPKG_STATUS" $BASE_IMAGE_ARG . || { echo "${red}Build $REPO_NAME:$TAG failure!${reset}"; exit 1; }

        if $CI_BUILD ; then
            echo "- ${bold}Prune${reset} old docker images"
            docker image prune -f
        fi
    else
        echo "- Push repo ${green}$REPO_NAME:$TAG${reset}"
        docker image push $REPO_NAME:$TAG
    fi

    if $LATEST ; then
        echo "- Tag & Push ${bold}latest${reset} release from $REPO_NAME:$TAG"
        docker tag $REPO_NAME:$TAG $REPO_NAME:latest
        docker image push $REPO_NAME:latest
    fi
}

main $@
# EOF

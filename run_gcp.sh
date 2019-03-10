#!/usr/bin/env bash

# No-desktop GCP launcher script
# Fernando Sanchez <fernandosanchezmunoz@gmail.com>

# every exit != 0 fails the script
set -e

echo -e "
           _         _   _           
 ___ ___ _| |___ ___| |_| |_ ___ ___ 
|   | . | . | -_|_ -| '_|  _| . | . |
|_|_|___|___|___|___|_,_|_| |___|  _|
                                |_|  
"

# =============================================================================
# Default values
# =============================================================================

export NAME=nodesktop
export MACHINE_TYPE=n1-standard-2
export IMAGE=cos-stable-72-11316-136-0
export IMAGE_PROJECT=cos-cloud
export BOOT_DISK_SIZE=200GB
export CONTAINER_IMAGE=fernandosanchez/nodesktop
export VNC_COL_DEPTH=24
export VNC_RESOLUTION=1280x1024
export VNC_PW=nopassword
export HOME_MOUNT_DIR=/mnt/home
export ROOT_MOUNT_DIR=/mnt/root
export VNC_PORT=5901
export NOVNC_PORT=6901
export NOVNC_TAG=novnc-server



# =============================================================================
# Functions
# =============================================================================

# Prefixes output and writes to STDERR:
error() {
	echo -e "\n\n nodesktop error: $@\n" >&2
}

# Checks for command presence in $PATH, errors:
check_command() {
	TESTCOMMAND=$1
	HELPTEXT=$2

	printf '%-50s' " - $TESTCOMMAND..."
	command -v $TESTCOMMAND >/dev/null 2>&1 || {
		echo "[ MISSING ]"
		error "The '$TESTCOMMAND' command was not found. $HELPTEXT"

		exit 1
	}
	echo "[ OK ]"
}

# Tests variables for valid values:
check_config() {
	PARAM=$1
	VAR=$2
	printf '%-50s' " - '$VAR'..."
	if [[ $PARAM == *"(unset)"* ]]; then
		echo "[ UNSET ]"
		error "Please set the gcloud variable '$VAR' via:
		gcloud config set $VAR <value>"

		exit 1
	fi
	echo "[ OK ]"
}

# Returns just the value we're looking for OR unset:
gcloud_activeconfig_intercept() {
	gcloud $@ 2>&1 | grep -v "active configuration"
}

# Enables a single API:
enable_api() {
	gcloud services enable $1 >/dev/null 2>&1
	if [ ! $? -eq 0 ]; then
		echo -e "\n  ! - Error enabling $1"
		exit 1
	fi
}

# Enable a firewall rule for a tag/port:
enable_firewall_for_tag() {
	TESTTAG=$1
	TESTPORT=$2

	printf '%-50s' " - $TESTTAG..."
	
	if [[ ! $(gcloud compute firewall-rules list --format=json|grep $TESTTAG) ]];then
		echo -e "[CLOSED]"
		printf "Opening firewall port for "$TESTTAG" ..."

		gcloud compute firewall-rules create  \
			$TESTTAG \
			--direction=INGRESS \
			--priority=1000 \
			--network=default \
			--action=ALLOW \
			--rules=tcp:$TESTPORT \
			--source-ranges=0.0.0.0/0 \
			--target-tags=$TESTTAG \
			> /dev/null 2>&1
		if [ ! $? -eq 0 ]; then
			error "Error opening port "$TESTPORT" for tag "$TESTTAG
			exit 1
		fi
	else
		echo -e "[OPEN]"
	fi
}

# =============================================================================
# Base sanity checking
# =============================================================================

# Check for our requisite binaries:
printf "** Checking for requisite binaries..."
check_command gcloud "** Please install the Google Cloud SDK from: https://cloud.google.com/sdk/downloads"

# This executes all the gcloud commands in parallel and then assigns them to separate variables:
# Needed for non-array capabale bashes, and for speed.
echo "** Checking gcloud variables..."
PARAMS=$(cat <(gcloud_activeconfig_intercept config get-value compute/zone) \
	<(gcloud_activeconfig_intercept config get-value compute/region) \
	<(gcloud_activeconfig_intercept config get-value project) \
	<(gcloud_activeconfig_intercept auth application-default print-access-token))
read GCP_ZONE GCP_REGION GCP_PROJECT GCP_AUTHTOKEN <<<$(echo $PARAMS)

# Check for our requisiste gcloud parameters:
check_config $GCP_PROJECT "project"
check_config $GCP_REGION "compute/region"
check_config $GCP_ZONE "compute/zone"

# Check credentials are set:
printf '%-50s' " - 'application-default access token'..."
if [[ $GCP_AUTHTOKEN == *"ERROR"* ]]; then
	echo "[ UNSET ]"
	error "** You do not have application-default credentials set, please run this command:
	gcloud auth application-default login"
	exit 1
fi
echo "[ OK ]"

# =============================================================================
# Initialization and idempotent test/setting
# =============================================================================

# List of requisite APIs:
REQUIRED_APIS="
	compute
	dns
	storage-api
	storage-component
"

# Bulk parallel process all of the API enablement:
echo -e "** Checking requisiste GCP APIs..."

# Read-in our currently enabled APIs, less the googleapis.com part:
GCP_CURRENT_APIS=$(gcloud services list | grep -v NAME | cut -f1 -d'.')

# Keep track of whether we modified the API state for friendliness:
ENABLED_ANY=1

for REQUIRED_API in $REQUIRED_APIS; do
	if [ $(grep -q $REQUIRED_API <(echo $GCP_CURRENT_APIS))$? -eq 0 ]; then
		# It's already enabled:
		printf '%-50s' " - $REQUIRED_API"
		echo "[ ON ]"
	else
		# It needs to be enabled:
		printf '%-50s' " + $REQUIRED_API"
		enable_api $REQUIRED_API.googleapis.com &
		ENABLED_ANY=0
		echo "[ OFF ]"
	fi
done

# If we've enabeld any API, wait for child processes to finish:
if [ $ENABLED_ANY -eq 0 ]; then
	printf '%-50s' "**  Concurrently enabling APIs..."
	wait

else
	printf '%-50s' "** API status..."
fi
echo "[ OK ]"

# =============================================================================
# Open firewall ports
# =============================================================================

echo -e "** Checking for firewall ports..."
enable_firewall_for_tag ${NOVNC_TAG} ${NOVNC_PORT}

# =============================================================================
# Launch instance with container
# =============================================================================

echo -e "** Creating instance..."

gcloud beta compute instances \
	create-with-container ${NAME} \
	--machine-type=${MACHINE_TYPE} \
	--subnet=default \
	--image=${IMAGE} \
	--image-project=${IMAGE_PROJECT} \
	--boot-disk-size=${BOOT_DISK_SIZE} \
	--boot-disk-type=pd-standard \
	--boot-disk-device-name=${NAME} \
	--container-image=${CONTAINER_IMAGE} \
	--container-restart-policy=always \
	--labels=container-vm=${IMAGE} \
	--tags=${TAG} \
	--container-env=VNC_COL_DEPTH=${VNC_COL_DEPTH},VNC_RESOLUTION=${VNC_RESOLUTION},VNC_PW=${VNC_PW}

# These are set from gcloud config values
#	--project=${PROJECT} \
#	--zone=${ZONE} \
# These are not required
	#--network-tier=PREMIUM \
	#--maintenance-policy=MIGRATE \
	#--service-account=${SVC_ACCOUNT} \
	#--scopes=https://www.googleapis.com/auth/devstorage.read_only,\
#https://www.googleapis.com/auth/logging.write,\
#https://www.googleapis.com/auth/monitoring.write,\
#https://www.googleapis.com/auth/servicecontrol,\
#https://www.googleapis.com/auth/service.management.readonly,\
#https://www.googleapis.com/auth/trace.append \

# Show info message with URL

export EXT_IP=$(gcloud compute instances list | grep ${NAME} | awk '{print $5}')
echo -e "** Success! nodesktop will be available shortly at:"
echo -e "http://"${EXT_IP}":"${NOVNC_PORT}

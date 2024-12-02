#!/bin/bash

# Enable command logging
set -x

# Setup logging
exec 1> >(logger -s -t $(basename $0)) 2>&1

# Flag file to track execution
FLAG_FILE="/home/ubuntu/.publisher_token_initialized"
LOCK_FILE="/tmp/publisher_setup.lock"

# Ensure only one instance runs
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    echo "Another instance is running. Exiting."
    exit 1
fi

# Check if already run successfully
if [ -f "$FLAG_FILE" ]; then
    echo "Publisher already initialized. Exiting."
    exit 0
fi

# Wait for system to be ready
sleep 120

# Check if docker is running
while ! systemctl is-active --quiet docker; do
  sleep 10
done

# Function to wait for apt locks to be released
wait_for_apt() {
  while fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
     echo "Waiting for other software managers to finish..."
     sleep 5
  done
}

# Function to install packages with retry
install_packages() {
  local max_attempts=10
  local attempt=1
  local packages="$1"
  
  while [ $attempt -le $max_attempts ]; do
    echo "Attempt $attempt to install packages: $packages"
    wait_for_apt
    if sudo DEBIAN_FRONTEND=noninteractive apt-get update -y && \
       sudo DEBIAN_FRONTEND=noninteractive apt-get install -y $packages; then
      echo "Package installation successful"
      return 0
    fi
    echo "Package installation failed, waiting before retry..."
    sleep 30
    attempt=$((attempt + 1))
  done
  echo "Failed to install packages after $max_attempts attempts"
  return 1
}

# Install required packages with retry
if ! install_packages "curl jq"; then
  echo "Failed to install required packages. Exiting."
  exit 1
fi

# Configuration variables
TENANT_URL="##TENANT_URL##"
API_TOKEN="##API_TOKEN##"
PUB_NAME=$(hostname)
_PUB_TAG="##PUB_TAG##"
PUB_UPGRADE="##PUB_UPGRADE##"

# Verify if tags were provided
if [ ! -z "$_PUB_TAG" ]; then
  IFS=, read -a arr <<<"${_PUB_TAG}"
  printf -v tags ',{"tag_name": "%s"}' "${arr[@]}"
  PUB_TAG="${tags:1}"
  TAGS=',"tags": [ '${PUB_TAG}' ]'
fi

# Set default upgrade profile
if [ -z "$PUB_UPGRADE" ]; then
  PUB_UPGRADE=1
fi

echo "Verifying upgrade profile..."
UPGRADE_PROFILE_URL="https://${TENANT_URL}/api/v2/infrastructure/publisherupgradeprofiles/${PUB_UPGRADE}"
echo "API Call: curl -X GET ${UPGRADE_PROFILE_URL}"
UPGRADE_PROFILE=$(curl -s -X 'GET' "${UPGRADE_PROFILE_URL}" -H 'accept: application/json' -H "Netskope-Api-Token: ${API_TOKEN}")
echo "Upgrade Profile Response: ${UPGRADE_PROFILE}"

STATUS=$(echo ${UPGRADE_PROFILE} | jq -r '.status')
if [ "$STATUS" != "success" ] ; then
  echo "Using default Upgrade Profile ID!"
  PUB_UPGRADE=1
fi

echo "Creating Publisher object..."
CREATE_URL="https://${TENANT_URL}/api/v2/infrastructure/publishers?silent=0"
CREATE_PAYLOAD='{"name": "'"${PUB_NAME}"'","lbrokerconnect": false'"${TAGS}"',"publisher_upgrade_profiles_id": '${PUB_UPGRADE}'}'
echo "API Call: curl -X POST ${CREATE_URL}"
echo "Payload: ${CREATE_PAYLOAD}"

PUB_CREATE=$(curl -s -X 'POST' "${CREATE_URL}" \
  -H 'accept: application/json' \
  -H "Netskope-Api-Token: ${API_TOKEN}" \
  -H 'Content-Type: application/json' \
  -d "${CREATE_PAYLOAD}")
echo "Create Publisher Response: ${PUB_CREATE}"

STATUS=$(echo ${PUB_CREATE} | jq -r '.status')
if [ "$STATUS" != "success" ] ; then
  echo "Failed to create Publisher object!"
  exit 1
fi

echo "Publisher ${PUB_NAME} created successfully"

# Get Publisher Token
PUB_ID=$(echo ${PUB_CREATE} | jq '.data.id')
TOKEN_URL="https://${TENANT_URL}/api/v2/infrastructure/publishers/${PUB_ID}/registration_token"
echo "API Call: curl -X POST ${TOKEN_URL}"

PUB_TOKEN=$(curl -s -X 'POST' "${TOKEN_URL}" \
  -H 'accept: application/json' \
  -H "Netskope-Api-Token: ${API_TOKEN}" \
  -d '')
echo "Token Response: ${PUB_TOKEN}"

STATUS=$(echo ${PUB_TOKEN} | jq -r '.status')
if [ "$STATUS" != "success" ] ; then
  echo "Failed to retrieve Publisher Token!"
  exit 1
fi

echo "Registering Publisher..."
PUB_TOKEN=$(echo ${PUB_TOKEN} | jq -r '.data.token')
sudo /home/ubuntu/npa_publisher_wizard -token "${PUB_TOKEN}"

if [ $? -eq 0 ]; then
  echo "Publisher ${PUB_NAME} registered successfully"
  # Create flag file only if everything succeeded
  touch "$FLAG_FILE"
else
  echo "Failed to register publisher"
  exit 1
fi
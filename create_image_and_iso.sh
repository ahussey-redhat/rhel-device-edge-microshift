#!/usr/bin/env bash
set -euo pipefail

echo "Creating MicroShift Kiosk RHEL Device Edge image"

MS_BUILDID=$(composer-cli compose start-ostree --ref "rhel/9/$(uname -m)/edge" minimal-microshift edge-container | awk '{print $2}')

# Wait a hot minute (or 5) for the 'edge-container' build of the minimal-microshift image to be complete
MS_BUILD_STATUS=$(composer-cli compose status | grep ${MS_BUILDID} | tr -s ' ' ' ' | cut -d ' ' -f2)
echo "Image build starting"
while [[ ${MS_BUILD_STATUS} == "RUNNING" ]] || [[ ${MS_BUILD_STATUS} == "WAITING" ]]; do
  if [[ ${MS_BUILD_STATUS} == "FINISHED" ]]; then
    echo 'Build successful!'
  fi
  if [[ ${MS_BUILD_STATUS} == "FAILED" ]]; then
    echo 'Build failed! Exiting'
    exit 1
  fi
  sleep 10
  MS_BUILD_STATUS_FULL=$(composer-cli compose status | grep ${MS_BUILDID} | tr -s ' ' ' ')
  MS_BUILD_ID=$(echo "${MS_BUILD_STATUS_FULL}"| cut -d ' ' -f1)
  MS_BUILD_STATUS=$(echo "${MS_BUILD_STATUS_FULL}"| cut -d ' ' -f2)
  MS_BUILD_VERSION=$(echo "${MS_BUILD_STATUS_FULL}"| cut -d ' ' -f9)
  if [[ ${MS_BUILD_STATUS} == "FINISHED" ]]; then
    echo 'Build successful!'
  fi
  if [[ ${MS_BUILD_STATUS} == "FAILED" ]]; then
    echo 'Build failed! Exiting'
    exit 1
  fi
  echo "Build Status: ${MS_BUILD_STATUS} Build ID: ${MS_BUILD_ID} Version: ${MS_BUILD_VERSION}"
done;

# Export the minimal-microshift image
composer-cli compose image ${MS_BUILDID}
chown $(whoami). ${MS_BUILDID}-container.tar
chmod a+r ${MS_BUILDID}-container.tar

# Import the minimal-microshift image into Podman in preperation for serving it
IMAGEID=$(cat < "./${MS_BUILDID}-container.tar" | podman load | grep -o -P '(?<=sha256[@:])[a-z0-9]*')
podman tag quay.io/ahussey/microshift-kiosk:lastest ${IMAGEID}
podman tag quay.io/ahussey/microshift-kiosk:$(date +%Y-%m-%d-%H%M) ${IMAGEID}
podman push quay.io/ahussey/microshift-kiosk:lastest

# Serve the minimal-microshift image
podman stop microshift-server || true
podman run -d --rm --name=microshift-server -p 8080:8080 ${IMAGEID}

echo "Creating MicroShift Kiosk RHEL Device Edge installer (ISO)"
# Build the installer ISO
INSTALLER_BUILDID=$(sudo composer-cli compose start-ostree --url http://192.168.124.134:8080/repo/ --ref "rhel/9/$(uname -m)/edge" microshift-installer edge-installer | awk '{print $2}')

INSTALLER_BUILD_STATUS=$(composer-cli compose status | grep ${INSTALLER_BUILDID} | tr -s ' ' ' ' | cut -d ' ' -f2)
while [[ ${INSTALLER_BUILD_STATUS} != "FINISHED" ]] || [[ ${INSTALLER_BUILD_STATUS} != "FAILED" ]]; do
  echo "Waiting for MicroShift installer build to complete."
  sleep 10
  INSTALLER_BUILD_STATUS=$(composer-cli compose status | grep ${INSTALLER_BUILDID} | tr -s ' ' ' ' | cut -d ' ' -f2)
done;

# Download the installer ISO
composer-cli compose image ${INSTALLER_BUILDID}
chown $(whoami). ${INSTALLER_BUILDID}-installer.iso
chmod a+r ${INSTALLER_BUILDID}-installer.iso

# Inject the Kickstart file
mkksiso ks.cfg ${INSTALLER_BUILDID}-installer.iso rhel-edge-microshift.iso
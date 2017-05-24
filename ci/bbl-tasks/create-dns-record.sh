#!/bin/bash

set -eu -o pipefail

# ENV
: "${BBL_STATE_DIR:?}"
: "${DNS_DOMAIN:?}"
: "${SHARED_DNS_ZONE_NAME:?}"
: "${GCP_DNS_SERVICE_ACCOUNT_KEY:?}"
: "${GCP_PROJECT_ID:?}"

# INPUTS
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
workspace_dir="$( cd "${script_dir}/../../../" && pwd )"
bbl_state_dir="${workspace_dir}/bbl-state/${BBL_STATE_DIR}"

create_dns_record() {
  gcloud auth activate-service-account --key-file=<( echo "${GCP_DNS_SERVICE_ACCOUNT_KEY}" )
  gcloud config set project "${GCP_PROJECT_ID}"

  bbl_name_servers_json="$( bbl lbs --json | jq -r '.cf_system_domain_dns_servers' )"
  bbl_name_servers_raw="$( echo "${bbl_name_servers_json}" | jq -r 'join(" ")' )"
  gcp_name_servers_json="$( gcloud dns record-sets list --zone "${SHARED_DNS_ZONE_NAME}" --name "${DNS_DOMAIN}" --format=json )"

  gcloud dns record-sets transaction start --zone="${SHARED_DNS_ZONE_NAME}"

  record_count="$( echo "${gcp_name_servers_json}" | jq 'length' )"
  if [ "${record_count}" != "0" ]; then
    gcp_name_servers_raw="$( echo "${gcp_name_servers_json}" | jq -r '.[0].rrdatas | join(" ")' )"
    gcloud dns record-sets transaction remove --name "${DNS_DOMAIN}" --type=NS --zone="${SHARED_DNS_ZONE_NAME}" --ttl=300 ${gcp_name_servers_raw}
  fi

  gcloud dns record-sets transaction add --name "${DNS_DOMAIN}" --type=NS --zone="${SHARED_DNS_ZONE_NAME}" --ttl=300 ${bbl_name_servers_raw}
  gcloud dns record-sets transaction execute --zone="${SHARED_DNS_ZONE_NAME}"
}

pushd "${bbl_state_dir}" > /dev/null
  create_dns_record
popd > /dev/null
#!/bin/bash
cf push "${CF_APP}" --hostname "${CF_HOSTNAME}" -d "${CF_DOMAIN}"
# cf logs "${CF_APP}" --recent

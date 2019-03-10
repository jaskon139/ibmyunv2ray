#!/bin/bash
set -e -o pipefail
export CF_EXEC="/usr/local/Bluemix/bin/cfcli/cf"
echo "cf login -a \"${CF_TARGET_URL}\" -u apikey -p \"${PIPELINE_BLUEMIX_API_KEY}\" -o \"${CF_ORG}\" -s \"${CF_SPACE}\" "
cf login -a "${CF_TARGET_URL}" -u apikey -p "${PIPELINE_BLUEMIX_API_KEY}" -o "${CF_ORG}" -s "${CF_SPACE}"
cat > _customer_script.sh <<'EOF_CUSTOMER_SCRIPT'
#!/bin/bash
set -e -o pipefail
cat > _cust_script.sh <<'EOF_REAL_CUSTOMER_SCRIPT'
#!/bin/bash
cf push "${CF_APP}" --hostname "${CF_HOSTNAME}" -d "${CF_DOMAIN}"
# cf logs "${CF_APP}" --recent
EOF_REAL_CUSTOMER_SCRIPT
source _cust_script.sh
EOF_CUSTOMER_SCRIPT
if [ "$PIPELINE_DEBUG_SCRIPT" == "true" ]; then
current_time=$(echo $(($(date +%s%N)/1000000)))
fi
source _customer_script.sh
if [ "$PIPELINE_DEBUG_SCRIPT" == "true" ]; then
end_time=$(echo $(($(date +%s%N)/1000000)))
let "total_time=$end_time - $current_time"
echo "_DEBUG:USER_DEPLOY_SCRIPT:$total_time"
current_time=
end_time=
total_time=
fi
set +vx
if [ "$PIPELINE_DEBUG_SCRIPT" == "true" ]; then
current_time=$(echo $(($(date +%s%N)/1000000)))
fi
/opt/IBM/pipeline/bin/ids-set-env.sh 'https://devops-api.ng.bluemix.net/v1/pipeline/notifications/stage_properties/78e9ed5a-6cf1-4714-b37b-ebf96dec2908' 'bc020589d1ca462d26d225e3b304d3a6.ddd518dc943812e01f0ad6dc1253f3b2633763abb0bfb638cf45d4a8ffc672f730f63a4bf8dc6d677ee4578ffd1917e3236c59e3b52832ddc7cd5f17b316912d849019a9a4b6dd4c38d8f2ebba022018.b1a045cd44f620c258b3522378061cba8eca7b69' "$IDS_OUTPUT_PROPS"
if [ "$PIPELINE_DEBUG_SCRIPT" == "true" ]; then
end_time=$(echo $(($(date +%s%N)/1000000)))
let "total_time=$end_time - $current_time"
echo "_DEBUG:UPLOAD_STAGE_PROPERTIES:$total_time"
current_time=
end_time=
total_time=
fi

#!/bin/bash
set -e -o pipefail
cat > _cust_script.sh <<'EOF_REAL_CUSTOMER_SCRIPT'
#!/bin/bash
cf push "${CF_APP}" --hostname "${CF_HOSTNAME}" -d "${CF_DOMAIN}"
# cf logs "${CF_APP}" --recent
EOF_REAL_CUSTOMER_SCRIPT
source _cust_script.sh

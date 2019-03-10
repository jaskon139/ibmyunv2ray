#!/bin/dash
###############################################################################
# Licensed Materials - Property of IBM
# (c) Copyright IBM Corporation 2016. All Rights Reserved.
#
# Note to U.S. Government Users Restricted Rights:
# Use, duplication or disclosure restricted by GSA ADP Schedule
# Contract with IBM Corp.
###############################################################################

#------------------------------------------------------------------------------
# Parameters and Defaults
#------------------------------------------------------------------------------

# arg1 is the archive ID
[ -z ${PIPELINE_ARCHIVE_ID} ] && PIPELINE_ARCHIVE_ID=${1}

#------------------------------------------------------------------------------
# Function to run a curl command
#------------------------------------------------------------------------------

RunCurl() {
    local method="${1}"; shift
    local url="${1}"; shift

    local speedLimit=1024 # minimum bytes per second
    local speedTime=15 # seconds after which to trigger 'speed-limit' abort
    local connectTimeout=10 # seconds within which a connection must be made

    local maxAttempts=10
    local exitCode=-1

    # theses are only needed for debugging at the moment.
    local outputFile=''
    local grabOutputFile='no'

    # Parse options to the function that should not be passed to the curl command.
    local curlSuccessCodes='0'
    local logCommandLine='yes'
    while echo "${1}" | grep --quiet '^\+\+'
    do
        if echo "${1}" | grep --quiet 'curl-success-codes'
        then
            curlSuccessCodes="${2}"
            shift 2
        elif echo "${1}" | grep --quiet 'log-command-line'
        then
            logCurlDataValue="${2}"
            shift 2
        fi
    done

    #
    # Build up the command line.
    #
    local command="curl \
        --request ${method} \
        --silent \
        --show-error \
        --fail \
        --continue-at - \
        --connect-timeout ${connectTimeout} \
        --speed-limit ${speedLimit} \
        --speed-time ${speedTime} \
        --dump-header /tmp/curl$$.headers \
        --url '${url}' \
    "

    local arg
    for arg in "$@"
    do
        # Wrap with single quotes unless arg only contains
        # one or more alpha-numeric, hyphen, period, or underscore
        # characters.
        if echo "${arg}" | egrep --quiet '^[-._[:alnum:]]+$'
        then
            command="${command}        ${arg}"
        else
            command="${command}        '${arg}'"
        fi

        # This is needed for debugging at the moment.
        # So we can log the output file's size when
        # we have to retry.
        if [ "${grabOutputFile}" = 'yes' ]
        then
            # this argument is the name of the output file
            outputFile="${arg}"
            grabOutputFile='no'
        elif echo "${arg}" | egrep --quiet '\-o|\-\-output'
        then
            # the next argument will be the name of the output file
            grabOutputFile='yes'
        fi
    done

    # log the command line after removing any authorization string and temp_url_* parameters.
    if [ "${logCommandLine}" = 'yes' ]
    then
        local commandToLog="$(echo ${command} | sed '
            s/\(Authorization: \)[^'\'']\+/\1***/g;
            s/\(temp_url[_a-z0-9]\+\)=[a-z0-9]\+/\1=***/g
        ')"
        LogKeyValues \
            "%s:type:curl-command" \
            "%s:command:${commandToLog}"
    fi

    # for logging, remove the temp_url_* parameters
    local urlToLog="$(echo "${url}" | sed 's/\(temp_url[_a-z0-9]\+\)=[a-z0-9]\+/\1=***/g')"

    #
    # Loop
    #

    local attemptNumber=1;
    while [ ${attemptNumber} -le ${maxAttempts} ] && [ ${exitCode} -ne 0 ];
    do
        # debug current status when retry is > 1.
        if [ ! -z "${outputFile}" ]
        then
            local outputFileBytes=-1
            [ -f "${outputFile}" ] && outputFileBytes=$(stat --format=%s "${outputFile}")
            LogKeyValues \
                "%s:type:curl-retry" \
                "%s:method:${method}" \
                "%s:url:${urlToLog}" \
                "%d:attempt:${attemptNumber}" \
                "%d:outputFileBytes:${outputFileBytes}"
        fi

        #
        # Execute the curl command line.
        #

        local startSecs=$(date +%s)
        eval "${command} 2>/tmp/curl$$.stderr"
        local exitCode=$?   # See https://ec.haxx.se/usingcurl-returns.html for possible exit codes.
        local stopSecs=$(date +%s)
        local elapsedSecs=$((${stopSecs} - ${startSecs}))

        # If we got an exitCode that's in one that we expect, then reset
        # the exitCode to 0. Yes, this is a bit of a hack ;-).
        for successCode in ${curlSuccessCodes}
        do
            if [ ${exitCode} = ${successCode} ]
            then
                exitCode=0
                break
            fi
        done

        # The headers can include carriage returns, which mess with our greps,
        # so remove the carriage returns now.
        tr -d '\r' < /tmp/curl$$.headers > /tmp/curl$$.headers.clean
        mv /tmp/curl$$.headers.clean /tmp/curl$$.headers

        # Get the HTTP status code from the headers.
        local httpStatusCode="$(awk '/^HTTP/ {print $2}' /tmp/curl$$.headers)"

        # For debugging info, get the content length from the headers.
        local contentLengthKV=''
        local contentLength="$(grep '^Content-Length:' /tmp/curl$$.headers | cut -d' ' -f2)"
        [ ! -z "${contentLength}" ] && contentLengthKV="%d:contentLength:${contentLength}"

        # For debugging info, get the content range from the headers.
        local contentRangeKV=''
        local contentRange="$(grep '^Content-Range:' /tmp/curl$$.headers | cut -d' ' -f2-)"
        [ ! -z "${contentRange}" ] && local contentRangeKV="%s:contentRange:${contentRange}"

        # Abnormal exit?
        if [ ${exitCode} != 0 ]
        then
            # If the stderr file has just one line (usually) curl's error text,
            # then grab it as is. If the stderr file has more than one line, then
            # convert to a single line.
            local outputLineCount=$(wc --lines /tmp/curl$$.stderr | cut -d' ' -f1)
            if [ ${outputLineCount} = 1 ]
            then
                local stdErrText="$(cat /tmp/curl$$.stderr)"
            else
                local stdErrText="$(awk '{printf("%s\\n",$0)}' /tmp/curl$$.stderr)"
            fi
            local stdErrKV="%s:stderr:${stdErrText}"

            LogInfo "curl attempt #${attemptNumber} exited with ${exitCode} and standard error '${stdErrText}'"
        fi

        # Log it.
        LogKeyValues \
            "%s:type:curl" \
            "%s:method:${method}" \
            "%s:url:${urlToLog}" \
            "%s:status:${httpStatusCode}" \
            "%d:seconds:${elapsedSecs}" \
            "%d:exitCode:${exitCode}" \
            "%d:attempt:${attemptNumber}" \
            "${contentLengthKV}" \
            "${contentRangeKV}" \
            "${stdErrKV}"

        # Cleanup
        rm -f /tmp/curl$$.headers
        rm -f /tmp/curl$$.stderr

        # Increment retry attempt number
        attemptNumber=$((${attemptNumber} + 1))
    done

    return ${exitCode}
}

#------------------------------------------------------------------------------
# Logging functions.
#------------------------------------------------------------------------------

LogKeyValues() {
    # build up a json string
    printf '{' > /tmp/log$$.json
    printf '"timestamp":"%s"' $(date --iso-8601=ns) >> /tmp/log$$.json
    printf ',"host":"%s"' ${HOSTNAME} >> /tmp/log$$.json
    printf ',"orgId":"%s"' ${PIPELINE_ORGANIZATION_ID} >> /tmp/log$$.json
    printf ',"taskId":"%s"' ${TASK_ID} >> /tmp/log$$.json
    printf ',"jobId":"%s"' ${IDS_JOB_ID} >> /tmp/log$$.json
    printf ',"pipelineId":"%s"' ${PIPELINE_ID} >> /tmp/log$$.json
    printf ',"stageExecId":"%s"' ${PIPELINE_STAGE_EXECUTION_ID} >> /tmp/log$$.json
    printf ',"stageId":"%s"' ${PIPELINE_STAGE_ID} >> /tmp/log$$.json
    printf ',"toolchainId":"%s"' ${PIPELINE_TOOLCHAIN_ID} >> /tmp/log$$.json

    local kv
    for kv in "$@"
    do
        if [ -z "${kv}" ]
        then
            # skip empty arguments
            continue
        fi

        # if the first character is not a %, then a type has not been specified,
        # so assume key and value are already quoted
        if ! echo "%{kv}" | grep --quiet '^%'
        then
            printf ',%s' "${kv}" >> /tmp/log$$.json
            continue
        fi

        # a type has been specified
        local type="$(echo "${kv}" | cut -d: -f1)"
        local key="$(echo "${kv}" | cut -d: -f2)"
        local value="$(echo "${kv}" | cut -d: -f3-)"
        if [ "${type}" = "%d" ]
        then
            # number values are not quoted
            printf ',"%s":%d' "${key}" ${value} >> /tmp/log$$.json
        else
            # string values need to be quoted, but first
            # escape any double quotes that would mess up json
            value="$(echo "${value}" | sed 's/"/\\"/g')"
            printf ',"%s":"%s"' "${key}" "${value}" >> /tmp/log$$.json
        fi
    done

    printf '}' >> /tmp/log$$.json
    local json="$(cat /tmp/log$$.json)"
    rm -f /tmp/log$$.json

    # save to a local log
    echo "${json}" >> /tmp/$$.log

    # output to console
    [ "${PIPELINE_DEBUG_SCRIPT}" = 'true' ] && echo "${json}" 1>&2

    return 0
}

LogMessage() {
    local message="${1}"
    local severity=${2}

    if [ "${PIPELINE_DEBUG_SCRIPT}" = 'true' ]
    then
        echo "== ${severity}: ${message} ==" 1>&2
    fi

    LogKeyValues "%s:type:message" "%s:text:${message}" "%s:severity:${severity}"
}

LogError() {
    LogMessage "${1}" "ERROR"
}

LogInfo() {
    LogMessage "${1}" "INFO"
}

ConsoleError() {
    echo "ERROR: ${1}"
    LogMessage "${1}" "ERROR"
}

ConsoleInfo() {
    echo "INFO: ${1}"
    LogMessage "${1}" "INFO"
}

#------------------------------------------------------------------------------
# Main program.
#------------------------------------------------------------------------------

# Enable debugging output.
if test "${PIPELINE_DEBUG_SCRIPT}" = 'true'; then
  set -x
fi

#
# Initialze variables.
#

SCRIPT_START_SECS=$(date +%s)

if test -z "${PIPELINE_CODESTATION_URL}"; then
  PIPELINE_CODESTATION_URL=http://localhost:3000
fi

if [ -z "${PIPELINE_ORGANIZATION_ID}" ] && [ -z "${PIPELINE_ARCHIVE_TOKEN}" ]; then
  if test -z "${organization}"; then
    ConsoleError "export organization=<org name> is not set"
    exit 1
  else
    PIPELINE_ORGANIZATION_ID=`cf org $organization --guid`
  fi
fi

if [ -z "${TOOLCHAIN_TOKEN}" ] && [ -z "${PIPELINE_ARCHIVE_TOKEN}" ]; then
    TOOLCHAIN_TOKEN=`cf oauth-token`
fi

FILENAME="${PIPELINE_ARCHIVE_ID}.zip"

if test "${PIPELINE_DEBUG_SCRIPT}" = 'true'; then
  echo "-----"
  echo "Begin"
  echo "Organization: ${PIPELINE_ORGANIZATION_ID}"
  echo "Archive ID: ${PIPELINE_ARCHIVE_ID}"
  date
  df -h
  echo "-----"
fi

#
# Get temporary URLs to the stored artifact and metadata objects, and get the
# encryption key.
#
tmpurl=$(RunCurl GET "${PIPELINE_CODESTATION_URL}/codestation/v2/s3Storages/${PIPELINE_ARCHIVE_ID}/tempgeturl/${FILENAME}.enc" \
  --header "X-Organization-ID: ${PIPELINE_ORGANIZATION_ID}" \
  --header "Authorization: ${TOOLCHAIN_TOKEN}" \
  --header "X-Artifact-ID: ${PIPELINE_ARCHIVE_ID}" \
  --header "X-Artifact-Token: ${PIPELINE_ARCHIVE_TOKEN}" \
  --header "Accept: application/json" \
)

key=$(RunCurl GET "${PIPELINE_CODESTATION_URL}/codestation/v2/artifacts/${PIPELINE_ARCHIVE_ID}/key" \
  --header "X-Organization-ID: ${PIPELINE_ORGANIZATION_ID}" \
  --header "Authorization: ${TOOLCHAIN_TOKEN}" \
  --header "X-Artifact-ID: ${PIPELINE_ARCHIVE_ID}" \
  --header "X-Artifact-Token: ${PIPELINE_ARCHIVE_TOKEN}" \
  --header "Accept: application/json" \
)

if test "${PIPELINE_DEBUG_SCRIPT}" = 'true'; then
  echo Temp URL for download is: $tmpurl
fi
if test -z "${tmpurl}" || test "${tmpurl}" = 'Unable to generate temporary URL'; then
  ConsoleError "Unable to retrieve temporary URL for downloading artifacts."
  exit 1
fi

if test -z "${key}"; then
  ConsoleError "Unable to retrieve artifact encryption key."
  exit 1
fi

#
# Download the artifact zip file.
#

if test "${PIPELINE_DEBUG_SCRIPT}" = 'true'; then
  echo "-----"
  echo "Download and Decrypt Encrypted File"
  date
  df -h
  echo "-----"
fi

RunCurl "GET" ${tmpurl} --output "/tmp/${FILENAME}.enc"
if [ $? -ne 0 ]; then
  ConsoleInfo "Could not find artifacts in S3 Storage. Attempting fallback to get from Swift"
  tmpurl=$(RunCurl GET "${PIPELINE_CODESTATION_URL}/codestation/v2/artifacts/${PIPELINE_ARCHIVE_ID}/tempgeturl/${FILENAME}.enc" \
    --header "X-Organization-ID: ${PIPELINE_ORGANIZATION_ID}" \
    --header "Authorization: ${TOOLCHAIN_TOKEN}" \
    --header "X-Artifact-ID: ${PIPELINE_ARCHIVE_ID}" \
    --header "X-Artifact-Token: ${PIPELINE_ARCHIVE_TOKEN}" \
    --header "Accept: application/json" \
  )
  RunCurl "GET" ${tmpurl} --output "/tmp/${FILENAME}.enc"
  if [ $? -ne 0 ]; then
    ConsoleError "Unable to download artifacts."
    exit 1
  fi
fi

if [ -f /tmp/${FILENAME}.enc -a -s /tmp/${FILENAME}.enc ]; then
  rm -f ${FILENAME}
  openssl enc -d -aes-256-ctr -in "/tmp/${FILENAME}.enc" -out "/tmp/${FILENAME}" -pass "pass:${key}" -nosalt
  rm -f /tmp/${FILENAME}.enc
fi

#
# Unzip the artifacts
#

if [ -f "/tmp/${FILENAME}" ]; then
  if test "${PIPELINE_DEBUG_SCRIPT}" = 'true'; then
    echo "-----"
    echo "Unzip File"
    date
    df -h
    echo "-----"
  fi

  ZIP_VERBOSITY="-qq"
  if test "${PIPELINE_DEBUG_SCRIPT}" = 'true'; then
    ZIP_VERBOSITY=""
  fi

  unzip ${ZIP_VERBOSITY} "/tmp/${FILENAME}"
  if [ $? -ne 0 ]; then
      ConsoleError "Unable to extract artifacts."
      exit 1
  fi
fi

#
# Finish up
#

SCRIPT_ELAPSED_SECS=$(($(date +%s) - ${SCRIPT_START_SECS}))
LogKeyValues \
    "%s:type:download-artifacts" \
    "%d:seconds:${SCRIPT_ELAPSED_SECS}"

if test "${PIPELINE_DEBUG_SCRIPT}" = 'true'; then
  echo "-----"
  echo "Finished"
  date
  df -h
  echo "-----"
fi

###############################################################################
# End of artifact download script.
###############################################################################

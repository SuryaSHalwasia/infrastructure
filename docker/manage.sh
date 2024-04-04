#!/bin/bash
export MSYS_NO_PATHCONV=1

# getDockerHost; for details refer to https://github.com/bcgov/DITP-DevOps/tree/main/code/snippets#getdockerhost
. /dev/stdin <<<"$(cat <(curl -s --raw https://raw.githubusercontent.com/bcgov/DITP-DevOps/main/code/snippets/getDockerHost))" 
export DOCKERHOST=$(getDockerHost)
set -e

#
# Global utility functions - START
#
function echoError (){
  _msg=${1}
  _red='\e[31m'
  _nc='\e[0m' # No Color
  echo -e "${_red}${_msg}${_nc}"
}

function echoWarning (){
  _msg=${1}
  _yellow='\e[33m'
  _nc='\e[0m' # No Color
  echo -e "${_yellow}${_msg}${_nc}"
}

function isInstalled () {
  rtnVal=$(type "$1" >/dev/null 2>&1)
  rtnCd=$?
  if [ ${rtnCd} -ne 0 ]; then
    return 1
  else
    return 0
  fi
}

function isJQInstalled () {
  JQ_EXE=jq
  if ! isInstalled ${JQ_EXE}; then
    echoError "The ${JQ_EXE} executable is required and was not found on your path."
    echoError "Installation instructions can be found here: https://stedolan.github.io/jq/download"
    echoError "Alternatively, a package manager such as Chocolatey (Windows) or Brew (Mac) can be used to install this dependecy."
    exit 1
  fi
}

function isCurlInstalled () {
  CURL_EXE=curl
  if ! isInstalled ${CURL_EXE}; then
    echoError "The ${CURL_EXE} executable is required and was not found on your path."
    echoError "If your shell of choice doesn't come with curl preinstalled, try installing it using either [Homebrew](https://brew.sh/) (MAC) or [Chocolatey](https://chocolatey.org/) (Windows)."
    exit 1
  fi
}

function isNgrokInstalled () {
  NGROK_EXE=ngrok
  if ! isInstalled ${NGROK_EXE}; then
    echoError "The ${NGROK_EXE} executable is needed and not on your path."
    echoError "It can be downloaded from here: https://ngrok.com/download"
    echoError "Alternatively, a package manager such as Chocolatey (Windows) or Brew (Mac) can be used to install this dependecy."
    exit 1
  fi
}

function checkNgrokTunnelActive () {
  if [ -z "${NGROK_AGENT_ENDPOINT}" ]; then
    echoError "It appears that ngrok tunneling is not enabled."
    echoError "Please open another shell in the scripts folder and execute start-ngrok.sh before trying again."
    exit 1
  fi
}



function generateKey(){
  (
    _length=${1:-48}
    # Format can be `-base64` or `-hex`
    _format=${2:--base64}

    echo $(openssl rand ${_format} ${_length})
  )
}

function generateSeed(){
  (
    _prefix=${1}
    _seed=$(echo "${_prefix}$(generateKey 32)" | fold -w 32 | head -n 1 )
    _seed=$(echo -n "${_seed}")
    echo ${_seed}
  )
}
#
# Global utility functions - END
#
SCRIPT_HOME="$(cd "$(dirname "$0")" && pwd)"

# =================================================================================================================
# Usage:
# -----------------------------------------------------------------------------------------------------------------
usage() {
  cat <<-EOF
    
      Usage: $0 [command] [options]
    
      Commands:
    
      logs - Display the logs from the docker compose run (ctrl-c to exit).

      start - Runs the containers in production mode.
      up - Same as start.
      
      start-dev - Runs a live development version of the containers, with hot-reloading
              enabled.

      start-demo - Runs the containers in production mode, using the BCovrin Test ledger and
              exposing the agent to the Internet using ngrok.

      stop - Stops the services.  This is a non-destructive process.  The volumes and containers
             are not deleted so they will be reused the next time you run start.
    
      down - Brings down the services and removes the volumes (storage) and containers.
      rm - Same as down

EOF
  exit 1
}
# -----------------------------------------------------------------------------------------------------------------
# Default Settings:
# -----------------------------------------------------------------------------------------------------------------
DEFAULT_CONTAINERS="infrastructure wallet webhook-server"
# -----------------------------------------------------------------------------------------------------------------
# Functions:
# -----------------------------------------------------------------------------------------------------------------


configureEnvironment() {

  if [ -f .env ]; then
    while read line; do
      if [[ ! "$line" =~ ^\# ]] && [[ "$line" =~ .*= ]]; then
        export ${line//[$'\r\n']}
      fi
    done <.env
  fi

  for arg in "$@"; do
    # Remove recognized arguments from the list after processing.
    shift

    # echo "arg: ${arg}"
    # echo "Remaining: ${@}"

    case "$arg" in
      *=*)
        # echo "Exporting ..."
        export "${arg}"
        ;;
      *)
        # echo "Saving for later ..."
        # If not recognized, save it for later procesing ...
        set -- "$@" "$arg"
        ;;
    esac
  done

  # Global
  export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-infrastructure}"
  export S2I_SCRIPTS_PATH=${S2I_SCRIPTS_PATH:-/usr/libexec/s2i}
  export DEBUG=${DEBUG}
  export LOG_LEVEL=${LOG_LEVEL:-DEBUG}

  # wallet
  export WALLET_HOST="wallet"
  export WALLET_PORT="5432"
  export WALLET_USER="DB_USER"
  export WALLET_PASSWORD="DB_PASSWORD"
  export WALLET_DATABASE="infrastructure"

  # tails-server
  export TAILS_SERVER_PORT=6543
  export TAILS_STORAGE_PATH=${STORAGE_PATH:-"/tmp/tails-files"}
  export TAILS_SERVER_URL=${TAILS_SERVER_URL:-http://$DOCKERHOST:6543}

  # agent
  export LEDGER_URL=${LEDGER_URL-http://$DOCKERHOST:9000}
  export AGENT_WALLET_NAME="infrastructure_agent"
  export AGENT_WALLET_ENCRYPTION_KEY="key"
  export ACAPY_MULTITENANT=true
  export AGENT_STORAGE_WALLET_TYPE="postgres_storage"
  export TRACE_LABEL="infrastructure.Agent"
  if [[ ! -f ".env" ]]; then
    export ACAPY_WALLET_SEED="infrastructure_000000000000000000000"
  fi
  export AGENT_ADMIN_PORT=8051
  export AGENT_WEBHOOK_PORT=8050
  export AGENT_WEBHOOK_URL=${AGENT_WEBHOOK_URL:-http://webhook-server:1080}
  export AGENT_HTTP_INTERFACE_PORT=8050
  export AGENT_NAME="infrastructure"
  export AGENT_ENDPOINT=${NGROK_AGENT_ENDPOINT:-http://$DOCKERHOST:$AGENT_HTTP_INTERFACE_PORT}
  export AGENT_ADMIN_MODE="admin-insecure-mode"
  
}

getInputParams() {
  ARGS=""

  for arg in $@; do
    case "$arg" in
    *=*)
      # Skip it
      ;;
    *)
      ARGS+=" $arg"
      ;;
    esac
  done

  echo ${ARGS}
}

getStartupParams() {
  CONTAINERS=""
  ARGS=""

  for arg in $@; do
    case "$arg" in
    *=*)
      # Skip it
      ;;
    -*)
      ARGS+=" $arg"
      ;;
    *)
      CONTAINERS+=" $arg"
      ;;
    esac
  done

  if [ -z "$CONTAINERS" ]; then
    CONTAINERS="$DEFAULT_CONTAINERS"
  fi

  echo ${ARGS} ${CONTAINERS}
}

deleteVolumes() {
  _projectName=${COMPOSE_PROJECT_NAME:-docker}

  echo "Stopping and removing any running containers ..."
  docker-compose down -v

  _pattern="^${_projectName}_\|^docker_"
  _volumes=$(docker volume ls -q | grep ${_pattern})

  if [ ! -z "${_volumes}" ]; then
    echo "Removing project volumes ..."
    echo ${_volumes} | xargs docker volume rm
  else
    echo "No project volumes exist."
  fi

  echo "Removing build cache ..."
  rm -Rf ../client/tob-web/.cache
}

toLower() {
  echo $(echo ${@} | tr '[:upper:]' '[:lower:]')
}

echoError (){
  _msg=${1}
  _red='\033[0;31m'
  _nc='\033[0m' # No Color
  echo -e "${_red}${_msg}${_nc}" >&2
}

functionExists() {
  (
    if [ ! -z ${1} ] && type ${1} &>/dev/null; then
      return 0
    else
      return 1
    fi
  )
}
# =================================================================================================================

pushd "${SCRIPT_HOME}" >/dev/null
COMMAND=$(toLower ${1})
shift || COMMAND=usage

_startupParams=$(getStartupParams --force-recreate $@)

case "${COMMAND}" in
  logs)
    configureEnvironment "$@"
    docker-compose logs -f
    ;;
  build)
    isS2iInstalled

    configureEnvironment "$@"

    buildImage=$(toLower ${1})
    shift || buildImage=all
    buildImage=$(echo ${buildImage} | sed s~^infrastructure-~~)
    case "$buildImage" in
      *=*)
        buildImage=all
        ;;
    esac

    if functionExists "build-${buildImage}"; then
      eval "build-${buildImage}"
    else
      echoError "\nThe build function, build-${buildImage}, does not exist.  Please check your build parameters and try again.\nUse '-h' to get full help details."
      exit 1
    fi
    ;;
  start|start|up)
    isJQInstalled
    isCurlInstalled

    
    
    if [ -f .env ]; then
    source .env
    fi


    #Generating Infrastructure
    echo "Creating Infrastructure"
    #
    if [[ ! -f ".env" ]]; then
      ACAPY_WALLET_SEED=$(generateSeed infrastructure)
      echo "Generated ACAPY_WALLET_SEED=${ACAPY_WALLET_SEED}"
      echo "ACAPY_WALLET_SEED=${ACAPY_WALLET_SEED}" > .env
    fi

    
    configureEnvironment "$@"
    docker-compose up -d ${_startupParams} ${DEFAULT_CONTAINERS}
    docker-compose logs -f
    ;;
  start-demo)
    isJQInstalled
    isCurlInstalled

    if [ -f .env ]; then
    source .env
    fi

    #Generating Infrastructure
    echo "Creating Infrastructure"
    #

    export LEDGER_URL="http://test.bcovrin.vonx.io"
    export TAILS_SERVER_URL="https://tails-dev.vonx.io"
    if [[ ! -f ".env" ]]; then
      ACAPY_WALLET_SEED=$(generateSeed infrastructure)
      echo "Generated ACAPY_WALLET_SEED=${ACAPY_WALLET_SEED}"
      echo "ACAPY_WALLET_SEED=${ACAPY_WALLET_SEED}" > .env
    fi

    unset NGROK_AGENT_ENDPOINT

    if [ -z "$NGROK_AGENT_ENDPOINT" ]; then
      isNgrokInstalled
      export NGROK_AGENT_ENDPOINT=$(${CURL_EXE} http://localhost:4040/api/tunnels | ${JQ_EXE} --raw-output '.tunnels | map(select(.name | contains("issuer-agent"))) | .[0] | .public_url')
      echo $NGROK_AGENT_ENDPOINT
    fi
    
    checkNgrokTunnelActive
    echo "Running in demo mode, will use ${LEDGER_URL} as ledger and ${NGROK_AGENT_ENDPOINT} as the agent endpoint."

    configureEnvironment "$@"
    docker-compose --env-file .env up -d ${_startupParams} ${DEFAULT_CONTAINERS}
    docker-compose logs -f
    ;;
  start-dev)
    isJQInstalled
    isCurlInstalled

    if [ -f .env ]; then
    source .env
    fi

    #Generating Infrastructure
    echo "Creating Infrastructure"
    #

    export LEDGER_URL="http://test.bcovrin.vonx.io"
    export TAILS_SERVER_URL="https://tails-dev.vonx.io"
    if [[ ! -f ".env" ]]; then
      ACAPY_WALLET_SEED=$(generateSeed issuer-kit-demo)
      echo "Generated ACAPY_WALLET_SEED=${ACAPY_WALLET_SEED}"
      echo "ACAPY_WALLET_SEED=${ACAPY_WALLET_SEED}" > .env
    fi

    unset NGROK_AGENT_ENDPOINT

    if [ -z "$NGROK_AGENT_ENDPOINT" ]; then
      isNgrokInstalled
      export NGROK_AGENT_ENDPOINT=$(${CURL_EXE} http://localhost:4040/api/tunnels | ${JQ_EXE} --raw-output '.tunnels | map(select(.name | contains("issuer-agent"))) | .[0] | .public_url')
      echo $NGROK_AGENT_ENDPOINT
    fi
    
    checkNgrokTunnelActive
    echo "Running in demo mode, will use ${LEDGER_URL} as ledger and ${NGROK_AGENT_ENDPOINT} as the agent endpoint."

    configureEnvironment "$@"
    docker-compose --env-file .env up -d ${_startupParams} ${DEFAULT_CONTAINERS}
    docker-compose logs -f
    ;;
    
  stop)
    configureEnvironment
    docker-compose stop 
    ;;
  rm|down)
    if [ -f ".env" ] ; then
        rm ".env"
    fi

    configureEnvironment
    deleteVolumes
    ;;
  *)
    usage
    ;;
esac

popd >/dev/null

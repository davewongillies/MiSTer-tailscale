#!/usr/bin/env bash

set -eo pipefail

SCRIPTS_PATH=/media/fat/Scripts
TS_INSTALL_PATH=${SCRIPTS_PATH}/.config/tailscale
TS_VERSION="1.84.0"
TS_ARCH="arm"
TS_ARTIFACT="tailscale_${TS_VERSION}_${TS_ARCH}.tgz"
TS_PKG_SRV="https://pkgs.tailscale.com/stable"
TS_BIN=${TS_INSTALL_PATH}/tailscale

[ -f ${TS_INSTALL_PATH}/tailscaled.ini ] && source ${TS_INSTALL_PATH}/tailscaled.ini

SCRIPT_INI=${SCRIPTS_PATH}/tailscale.ini

[ -f ${SCRIPT_INI} ] && source ${SCRIPT_INI}

ini_get() {
  if [ -f ${SCRIPT_INI} ]; then
    grep -E "^${1}=.*$" ${SCRIPT_INI} | cut -d= -f2 ; true
  fi
}

ini_set() {
  ! [ -f ${SCRIPT_INI} ] && touch ${SCRIPT_INI}

  val="$(ini_get ${1} ${2})"

  if [[ -z "${val}" ]]; then
    echo "${1}=${2}" >> ${SCRIPT_INI}
  else
    sed -i -e "s!${1}=.*!${1}=${2}!g" ${SCRIPT_INI}
  fi

  source ${SCRIPT_INI}
}

is_running_from_menu() {
  if ps -o args|grep -q "^{script} /bin/bash /tmp/script -f root$" && ps -o args|grep -q "^bash /media/fat/Scripts/$(basename $0)$"; then
    return 0
  else
    return 1
  fi
}

ts() {
  if ! grep -q "# davewongillies/tailscale" /media/fat/linux/user-startup.sh ; then
    echo Adding tailscale.sh to user-startup.sh
    echo '
# davewongillies/tailscale
[[ -e /media/fat/Scripts/tailscale.sh ]] && /media/fat/Scripts/tailscale.sh $1 &' >> /media/fat/linux/user-startup.sh
  fi

  if ! [ -e ${TS_INSTALL_PATH}/tailscaled ]; then
    mkdir -p $TS_INSTALL_PATH/.state
    echo Downloading Tailscale version $TS_VERSION...
    wget -qq "${TS_PKG_SRV}/${TS_ARTIFACT}" -O /tmp/${TS_ARTIFACT}
    tar xf /tmp/${TS_ARTIFACT} -C /tmp

    echo Copying tailscale, tailscaled to ${TS_INSTALL_PATH}...
    cp /tmp/tailscale_${TS_VERSION}_${TS_ARCH}/{tailscale,tailscaled} $TS_INSTALL_PATH

    echo Cleaning up Tailscale install files
    rm -rf /tmp/tailscale_${TS_VERSION} /tmp/${TS_ARTIFACT}

    ini_set tailscaled_autoconnect true
    ts_start && ts_up && $TS_BIN status

  else
    $TS_BIN $*
  fi
}

ts_up() {
  $TS_BIN up --qr
}

ts_start() {
  echo Starting tailscaled...
  ${TS_INSTALL_PATH}/tailscaled --tun=userspace-networking --statedir=${TS_INSTALL_PATH}/.state/ > /dev/null 2>&1 &
  if [ "$(ini_get tailscaled_autoconnect true)" == "true" ]; then
    ts_up
  fi
}

ts_kill() {
  echo Killing tailscaled
  killall -HUP tailscaled
}

ts_restart() {
  echo Restarting Tailscale...
  echo Disconnecting from Tailscale...
  $TS_BIN down
  ts_kill
  ts_start
  ts_up
  echo Restart complete
}

ts_autoconnect_toggle() {
  val=$(ini_get tailscaled_autoconnect)

  if [[ -z "${val}" ]]; then
    echo "Enabling tailscaled_autoconnect"
    ini_set tailscaled_autoconnect true
  elif [ "${val}" == "true" ]; then
    echo "Disabling tailscaled_autoconnect"
    ini_set tailscaled_autoconnect false
  else
    echo "Enabling tailscaled_autoconnect"
    ini_set tailscaled_autoconnect true
  fi
}

main() {
  result=$1
  if is_running_from_menu; then
    while true; do
      # Define the dialog exit status codes
      : ${DIALOG_OK=0}
      : ${DIALOG_CANCEL=1}
      : ${DIALOG_HELP=2}
      : ${DIALOG_EXTRA=3}
      : ${DIALOG_ITEM_HELP=4}
      : ${DIALOG_ESC=255}

      # Duplicate (make a backup copy of) file descriptor 1
      # on descriptor 3
      exec 3>&1

      # Generate the dialog box while running dialog in a subshell
      result=$(dialog \
        --clear \
        --title "Tailscale" \
        --cancel-label "Exit" \
        --menu "Choose an option" \
        23 80 12 \
        up          "Connect to Tailscale, logging in if needed" \
        down        "Disconnect from Tailscale" \
        start       "Start tailscaled and connect to Tailscale" \
        stop        "Disconnect from Tailscale and stop tailscaled" \
        restart     "Restart tailscaled and reconnect to Tailscale" \
        autoconnect "Toggle autoconnect to Tailscale on startup" \
        ip          "Show Tailscale IP addresses" \
        dns         "Show DNS status" \
        status      "Show state of tailscaled" \
        metrics     "Show Tailscale metrics" \
        version     "Print Tailscale version" \
        update      "Update Tailscale to the latest version" \
        login       "Log in to a Tailscale account" \
        logout      "Disconnect from Tailscale and expire current node key" \
        install     "Install and setup Tailscale" \
        uninstall   "Uninstall Tailscale" \
      2>&1 1>&3)

      # Get dialog's exit status
      return_value=$?

      # Close file descriptor 3
      exec 3>&-

      # Act on the exit status
      case $return_value in
        $DIALOG_OK)
          echo Running tailscale command $result...
          ts_cmd $result
          echo "Press any key to continue..."
          read -n 1 -s
          ;;
      esac
    done
  else
    ts_cmd $*
  fi
}

ts_cmd() {
  result=$1
  case $result in
    kill|stop)
      echo Disconnecting from Tailscale...
      $TS_BIN down
      echo Stopping tailscaled...
      ts_kill
      ;;
    up)
      echo Connecting to Tailscale...
      ts_up
      ;;
    start)
      ts_start
      ;;
    down)
      $TS_BIN down
      ;;
    restart)
      ts_restart
      ;;
    update)
      $TS_BIN update --yes
      ts_restart
      ;;
    dns)
      $TS_BIN dns status;;
    autoconnect)
      ts_autoconnect_toggle
      ;;
    *)
      ts $result
      ;;
  esac
}

main $1

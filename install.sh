#!/bin/bash
scriptname=$0
dirname=$(dirname "$scriptname")
echo ""

usage() {
  cat <<EOL
Usage: $scriptname [opts]

Installs openfortivpn-sso

Options
  -p, --prefix <prefix>  An optional prefix where to install openfortivpn-sso.
                         If not provided, it defaults to /usr/local/bin
  -u, --update           Update openfortivpn and openfortivpn-webview to the
                         latest versions available
  -y, --yes              Assume yes to all questions. It does not ask for
                         confirmation for installing/updating openfortivpn-sso
                         and openfortivpn-webview, and adding current user to
                         openfortivpn group so that it can run openfortivpn-sso
                         with sudo without a password.

  
Examples:
1. Install openfortivpn-sso to default prefix /usr/local/bin. openfortivpn-webview is already installed (either as an AppImage or as a repository package) and in the PATH.
   sudo $scriptname

2. Install openfortivpn-sso to default prefix /usr/local/bin, and install, if not already installed, openfortivpn and openfortivpn-webview
   sudo $scriptname --install-requirements

3. Install openfortivpn-sso to \$HOME/.local/bin, and install, if not already installed, openfortivpn and openfortivpn-webview
   $scriptname -r -p \$HOME/.local/bin
EOL
}

error_arg_missing() {
  echo "ERROR: required argument $1 missing"
  echo ""
  usage
  exit 1
}

error_optarg_missing() {
  echo "ERROR: option $1 requires and argument"
  echo ""
  usage
  exit 1
}

error_unknown_option() {
  echo "ERROR: unknown option $1"
  echo ""
  usage
  exit 1
}

error_duplicated_option() {
  echo "ERROR: duplicated option $1"
  echo ""
  usage
  exit 1
}

error_madatory_option_missing() {
  echo "ERROR: mandatory option $1 missing"
  echo ""
  usage
  exit 1
}

used_options=()
check_used_option() {
  local option=${1:1} # remove initial dash since it makes the search fail
  local regex="\<$option\>"
  if [[ ${used_options[@]} =~ $regex ]]; then
    error_duplicated_option "-$option"
  else
    used_options+=("$option")
  fi
}

opt_prefix=''
opt_update=0
opt_yes=0

while [ "$#" -gt 0 ]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  -p | --prefix)
    check_used_option "-p"
    [[ -z $2 || $2 = -* ]] && error_optarg_missing $1
    opt_prefix="$2"
    shift 2
    ;;
  -u | --update)
    check_used_option "-u"
    opt_update=1
    shift 1
    ;;
  -y | --yes)
    check_used_option "-r"
    opt_yes=1
    shift 1
    ;;
  *)
    if [[ $1 = -* ]]; then
      error_unknown_option $1
    else
      break
    fi
    ;;
  esac
done

##############################################################################
# Create temp dir (for downloads) and ensure it is cleaned up on exit
##############################################################################
TEMP_DIR=$(mktemp -d)

function cleanup {
  rm -rf ${TEMP_DIR}
}
trap cleanup EXIT

##############################################################################
# prefix
##############################################################################

prefix="/usr/local/bin"
if [[ -n $opt_prefix ]]; then
  prefix=${opt_prefix%%*(/)}
fi

SUDO=0
if [[ -d $prefix ]]; then
  if [[ -w $prefix ]]; then
    SUDO=0
  else
    SUDO=1
    echo "You user cannot write to prefix $prefix. Acquiring sudo permissions."
    sudo ls >/dev/null
  fi
else
  if mkdir -p "$prefix" 2>/dev/null; then
    SUDO=0
  else
    SUDO=1
    echo "Prefix directory $prefix does not exist and cannot be created without sudo. Acquiring sudo permissions."
    sudo mkdir -p "$prefix"
  fi
fi

##############################################################################
# Utility function: confirm
##############################################################################
confirm() {
  local prompt="${1:-Are you sure?}"
  local default=$2
  if [ -z "$default" ]; then
    default='y'
  fi
  case "$default" in
  y | Y | yes | YES)
    default='y'
    prompt_responses="[Y/n]"
    ;;
  n | N | no | NO)
    default='n'
    prompt_responses="[y/N]"
    ;;
  *)
    echo "Invalid default value: $default. Use 'y' or 'n'."
    return 1
    ;;
  esac

  # If the user has passed -y, assume yes
  if [ $opt_yes -eq 1 ]; then
    echo "$prompt [y/N]: y"
    return 0
  fi

  # If the user has not passed -y, ask for confirmation
  local response
  while true; do
    read -r -p "$prompt $prompt_responses " response
    if [ -z "$response" ]; then
      response=$default
    fi
    case "$response" in
    [yY][eE][sS] | [yY])
      return 0
      ;;
    [nN][oO] | [nN])
      return 1
      ;;
    *)
      echo "Invalid response. Please answer 'y' or 'n'."
      ;;
    esac
  done
}

##############################################################################
# Check that openfortivpn > 1.19.0 is installed
##############################################################################

compare_versions() {
  local version1=$1
  local version2=$2
  local IFS=.
  local ver1=($version1)
  local ver2=($version2)

  # Compare each segment of the version numbers
  for ((i = 0; i < ${#ver1[@]}; i++)); do
    if [ -z "${ver2[i]}" ]; then
      # If version2 is shorter, consider missing segments as 0
      ver2[i]=0
    fi

    if [ "${ver1[i]}" -gt "${ver2[i]}" ]; then
      return 0 # ver1 is greater than ver2
    else
      return 1 # ver2 is greater or equal
    fi
  done
}

# Function to get repo version
get_repo_version() {
  if command -v apt-get &>/dev/null; then
    apt-cache policy openfortivpn | grep Candidate | awk '{print $2}' | cut -d- -f1
  elif command -v dnf &>/dev/null; then
    dnf list openfortivpn | grep openfortivpn | awk '{print $2}' | cut -d- -f1
  elif command -v yum &>/dev/null; then
    yum list openfortivpn | grep openfortivpn | awk '{print $2}' | cut -d- -f1
  elif command -v pacman &>/dev/null; then
    pacman -Si openfortivpn | grep Version | awk '{print $3}' | cut -d- -f1
  else
    echo "Unsupported package manager"
    return 1
  fi
}

install_openfortivpn() {
  openfortivpn_repo_version=$(get_repo_version)
  compare_versions "1.19.0" $openfortivpn_repo_version
  if [ $? -eq 1 ]; then
    echo "Installing latest available openfortivpn..."
    # Detect package manager and install openfortivpn
    if command -v apt-get &>/dev/null; then
      sudo apt-get update
      sudo apt-get install -y openfortivpn
    elif command -v yum &>/dev/null; then
      sudo yum install -y openfortivpn
    elif command -v dnf &>/dev/null; then
      sudo dnf install -y openfortivpn
    elif command -v pacman &>/dev/null; then
      sudo pacman -S --noconfirm openfortivpn
    elif command -v zypper &>/dev/null; then
      sudo zypper install -y openfortivpn
    else
      echo "Unsupported package manager. Cannot install openfortivpn."
      exit 1
    fi
  else
    echo -e "\033[0;31m✗ Not installing openfortivpn since the version in the repositories is not greater than 1.19.0. You need to manually install it\033[0m"
    distro=$(lsb_release -is)
    if [[ $distro = "Ubuntu" ]]; then
      echo "If your Ubuntu distro is old, you may consider manually installing the package of a newer ubuntu from https://packages.ubuntu.com/search?keywords=openfortivpn"
    fi
    exit 1
  fi
}

OPENFORTIVPN=${OPENFORTIVPN:-$(which openfortivpn)}
if [[ $? -eq 1 ]]; then
  if confirm "
openfortivpn not found.
  
  If it is installed but not in the PATH, consider passing its location in the
  OPENFORTIVPN variable.

  Example: OPENFORTIVPN=/home/user/openfortivpn $scriptname

Do you want me to download and install openfortivpn from your distro repositories?" yes; then
    install_openfortivpn
    OPENFORTIVPN=$(which openfortivpn)
  else
    exit 1
  fi
elif [ $opt_update -eq 1 ]; then
  install_openfortivpn
  OPENFORTIVPN=$(which openfortivpn)
else
  version=$($OPENFORTIVPN --version)
  echo ""
  echo "openfortivpn v${version} found. If you wanted to update it, run the script again with the -u option"
fi

if ! [ -x $OPENFORTIVPN ]; then
  echo "ERROR: cannot run $OPENFORTIVPN. It does not have permissions to execute it."
  echo ""
  usage
  exit 1
fi

openfortivpn_version=$($OPENFORTIVPN --version)
compare_versions "1.19.0" $openfortivpn_version
if [ $? -eq 0 ]; then
  echo "ERROR: installed openfortivpn version ($openfortivpn_version) is older that required (>1.19.0)."
  echo ""
  echo "In case you have more than one version installed, you may use the OPENFORTIVPN variable to pass another installed openfortivpn."
  echo ""
  if confirm "Do you want me to install the latest available openfortivpn from your distro repositories?" yes; then
    install_openfortivpn || {
      echo ""
      echo "I couldn't install openfortivpn. Please install it manually."
      exit 1
    }
    OPENFORTIVPN=$(which openfortivpn)
  else
    echo ""
    echo "Please install openfortivpn manually."
    exit 1
  fi
fi

##############################################################################
# openfortivpn-webview
##############################################################################

# Check if openfortivpn-webview is installed as a deb package
openfortivpn_webview_deb_installed() {
  if command -v apt-get &>/dev/null; then
    if apt list --installed 2>/dev/null | grep -qw openfortivpn-webview; then
      return 0
    fi
  fi
}

uninstall_openfortivpn_webview_deb() {
  echo "Uninstalling openfortivpn-webview previously installed via apt..."
  sudo apt purge --purge -y openfortivpn-webview
}

install_app_image() {
  echo "Installing AppÌmage of openfortivpn-webview..."
  if openfortivpn_webview_deb_installed; then
    if confirm "openfortivpn-webview is already installed as a deb package. Do you want me to uninstall it?" yes; then
      uninstall_openfortivpn_webview_deb || {
        echo ""
        echo "I couldn't uninstall openfortivpn-webview. Please uninstall it manually."
        exit 1
      }
    else
      return 1
    fi
  fi
  assets_json=$(curl -L -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" https://api.github.com/repos/gm-vm/openfortivpn-webview/releases/latest)
  OPENFORTIVPN_WEBVIEW=$prefix/openfortivpn-webview
  arch="$(uname -m)"
  if [[ "$arch" == "aarch64" ]]; then
    arch="arm64"
  fi
  appimage_url=$(echo $assets_json | grep -oP "https?://[^\s]+${arch}\.AppImage")
  if [[ -z "$appimage_url" ]]; then
    echo "Cannot find a suitable AppImage for architecture ${arch} at https://github.com/gm-vm/openfortivpn-webview/releases/latest"
    return 1
  fi

  $([ $SUDO -eq 1 ] && echo sudo) wget -O $OPENFORTIVPN_WEBVIEW $appimage_url || {
    echo "Couldn't download $appimage_url"
    return 1
  }
  $([ $SUDO -eq 1 ] && echo sudo) chmod +x $OPENFORTIVPN_WEBVIEW

  echo "openfortivpn-webview installed to $OPENFORTIVPN_WEBVIEW"
}

install_deb() {
  echo "Installing .deb version of openfortivpn-webview..."
  assets_json=$(curl -L -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" https://api.github.com/repos/gm-vm/openfortivpn-webview/releases/latest)
  arch="$(uname -m)"
  if [[ "$arch" == "aarch64" ]]; then
    arch="arm64"
  elif [[ "$arch" == "x86_64" ]]; then
    arch="amd64"
  fi
  deb_url=$(echo $assets_json | grep -oP "https?://[^\s]+${arch}\.deb")
  if [[ -z "$deb_url" ]]; then
    echo "Cannot find a suitable .deb package for architecture ${arch} at https://github.com/gm-vm/openfortivpn-webview/releases/latest"
    return 1
  fi
  wget -O $TEMP_DIR/openfortivpn-webview.deb $deb_url || {
    echo "Couldn't download $deb_url"
    return 1
  }
  sudo apt install -y $TEMP_DIR/openfortivpn-webview.deb || {
    echo "Couldn't install openfortivpn-webview .deb"
    return 1
  }
  echo "openfortivpn-webview installed"
}

install_openfortivpn_webview() {
  if openfortivpn_webview_deb_installed; then
    if confirm "
  openfortivpn-webview is provided as an AppImage or as a .deb package.
  openfortivpn-webview is already installed as a .deb package.
Update .deb?" yes; then
      install_deb || {
        if confirm "I couldn't install the .deb of openfortivpn-webview. Do you want me to try to install the AppImage version instead?" yes; then
          install_deb || {
            echo ""
            echo "I couldn't install the AppImage of openfortivpn-webview either. Please install openfortivpn-webview manually."
            exit 1
          }
        else
          exit 1
        fi
      }
    else
      install_app_image || {
        echo ""
        echo "I couldn't install the AppImage of openfortivpn-webview. Please install openfortivpn-webview manually or try the .dev version."
        exit 1
      }
    fi
  fi
  if command -v apt-get &>/dev/null; then
    if confirm "
  openfortivpn-webview is provided as an AppImage or as a .deb package.
  In Ubuntu/Debian -based distros it is recommended to use the .deb version of openfortivpn-webview.

Should I install the .deb version?" yes; then
      install_deb || {
        if confirm "I couldn't install the .deb of openfortivpn-webview. Do you want me to try to install the AppImage version instead?" yes; then
          install_deb || {
            echo ""
            echo "I couldn't install the AppImage of openfortivpn-webview either. Please install openfortivpn-webview manually."
            exit 1
          }
        else
          exit 1
        fi
      }
    else
      install_app_image || {
        echo ""
        echo "I couldn't install the AppImage of openfortivpn-webview. Please install openfortivpn-webview manually or try the .dev version."
        exit 1
      }
    fi
  else
    install_app_image || {
      echo ""
      echo "I couldn't install the AppImage of openfortivpn-webview. Please install it manually."
      exit 1
    }
  fi
}

OPENFORTIVPN_WEBVIEW=${OPENFORTIVPN_WEBVIEW:-$(which openfortivpn-webview)}
if [[ $? -eq 1 ]]; then
  echo ""
  if confirm "
openfortivpn-webview not found in the system.

  If it is installed but not in the PATH, consider passing its location in the
  the OPENFORTIVPN_WEBVIEW variable.

  Example:
  OPENFORTIVPN_WEBVIEW=/home/user/openfortivpn-webview-1.2.3.AppImage $scriptname

Do you want me to automatically download and install openfortivpn-webview?" yes; then
    install_openfortivpn_webview
  else
    exit 1
  fi
elif [ $opt_update -eq 1 ]; then
  install_openfortivpn_webview
else
  version=$($OPENFORTIVPN_WEBVIEW --version)
  echo ""
  echo "openfortivpn-webview v${version} found. If you wanted to update it, wun the script again with the -u option"
fi

##############################################################################
# Create group openfortivpn and allow its members to run openfortivpn        #
# without sudo password                                                      #
##############################################################################

# Check if current user is in the group
echo ""
echo "Users in openfortivpn group will be able to run openfortivpn with sudo without being forced to authenticate with a password."
if id -nG $(logname) | grep -qw openfortivpn; then
  echo "openfortivpn group already exists, and user '$(logname)' is a member."
else
  echo ""
  if confirm "Do you want to crete group openfortivpn and automatically add your user ($USER) to it?" yes; then
    sudo groupadd openfortivpn 2>/dev/null

    #using logname instead of $USER to get the user behind a potential sudo
    sudo usermod -a -G openfortivpn $(logname)

    cat <<EOL | sudo tee /etc/sudoers.d/openfortivpn >/dev/null
%openfortivpn ALL=(ALL) NOPASSWD: $OPENFORTIVPN
EOL
    sudo chmod 440 /etc/sudoers.d/openfortivpn
  fi
fi
echo "  Current members of the openfortivpn group:"
echo "    $(awk -F':' '/^openfortivpn/{print $4}' /etc/group)"
echo "  You can add other users with:"
echo "    sudo usermod -a -G openfortivpn username"
echo "  or remove existing ones with:"
echo "    sudo gpasswd -d username openfortivpn"

##############################################################################
# Install openfortivpn-sso                                                   #
##############################################################################
install_openfortivpn-sso() {
  echo ""
  openfortivpnsso=$prefix/openfortivpn-sso
  $([ $SUDO -eq 1 ] && echo sudo) cp $dirname/openfortivpn-sso $openfortivpnsso
#   cat <<EOL | $([ $SUDO -eq 1 ] && echo sudo) tee $openfortivpnsso >/dev/null
# #!/bin/bash
# scriptname=\$0
# echo ""

# OPENFORTIVPN=\${OPENFORTIVPN:-\$(which openfortivpn)}
# [[ \$? -eq 1 ]] && OPENFORTIVPN=''

# OPENFORTIVPN_WEBVIEW=\${OPENFORTIVPN_WEBVIEW:-\$(which openfortivpn-webview)}
# [[ \$? -eq 1 ]] && OPENFORTIVPN_WEBVIEW=''

# usage() {
#   cat <<EOL
# Usage: \$scriptname host[:port] [openfortivpn-webview_opts] [-- openfortivpn_opts]

# Connect to a Forti VPN Server authenticating with SSO enabled
#   host[:port]                   the VPN gateway
#   [openfortivpn-webview_opts]   openfortivpn-webview options. List them with:
#                                 openfortivpn-webview --help
#   [-- openfortivpn_opts]        options that will be passed to openfortivpn.
#                                 For more details, run:
#                                 openfortivpn --help

# If openfortivpn is not in the PATH, use the OPENFORTIVPN variable to pass its location. Example:
#    OPENFORTIVPN=/home/user/openfortivpn \$scriptname

# If openfortivpn-webview is not in the PATH, use the OPENFORTIVPN_WEBVIEW variable to pass its location. Example:
#    OPENFORTIVPN_WEBVIEW=/home/user/openfortivpn-webview-1.2.3.AppImage \$scriptname

# If you needed to use an http proxy to access the vpn gateway:
#  - If using the AppImage version of openfortivpn-webview (default):
#    \$scriptname host[:port] --proxy-server=proxy.example.com:8080 [other_openfortivpn-webview_opts] [-- openfortivpn_opts]
 
#  - If you have manually installed the Qt variant of openfortivpn-webview:
#    QTWEBENGINE_CHROMIUM_FLAGS="--proxy-server=proxy.example.com:8080" \$scriptname host[:port] [openfortivpn-webview_opts] [-- openfortivpn_opts]

# Simple usage example:
#   \$scriptname vpngateway.example.com
# $(echo EOL)
# }


# ##############################################################################
# # Check that openfortivpn > 1.19.0 is installed
# ##############################################################################

# compare_versions() {
#   local version1=\$1
#   local version2=\$2
#   local IFS=.
#   local ver1=(\$version1)
#   local ver2=(\$version2)

#   # Compare each segment of the version numbers
#   for ((i = 0; i < \${#ver1[@]}; i++)); do
#     if [ -z "\${ver2[i]}" ]; then
#       # If version2 is shorter, consider missing segments as 0
#       ver2[i]=0
#     fi

#     if [ "\${ver1[i]}" -gt "\${ver2[i]}" ]; then
#       return 0 # ver1 is greater than ver2
#     else
#       return 1 # ver2 is greater or equal
#     fi
#   done
# }

# if [[ -z \$OPENFORTIVPN ]]; then
#   cat <<EOL
# ERROR: openfortivpn not found in the system. If it is installed but not in the
#        PATH, consider passing its location in the OPENFORTIVPN variable.
#        Example:
#        OPENFORTIVPN=/home/user/openfortivpn \$scriptname
# $(echo EOL)
#   echo ""
#   usage
#   exit 1
# fi

# if ! [ -x \$OPENFORTIVPN ]; then
#   echo "ERROR: file does not exist or you do not have permissions to execute it."
#   echo "       \$OPENFORTIVPN"
#   echo ""
#   usage
#   exit 1
# fi

# openfortivpn_version=\$(\$OPENFORTIVPN --version)
# compare_versions "1.19.0" \$openfortivpn_version
# if [ \$? -eq 0 ]; then
#   echo "ERROR: installed openfortivpn version (\$openfortivpn_version) is older that required (>1.19.0)."
#   distro=\$(lsb_release -is)
#   if [[ \$distro = "Ubuntu" ]]; then
#     echo "You may consider manually installing the package of a newer ubuntu from https://packages.ubuntu.com/search?keywords=openfortivpn"
#   fi
#   echo ""
#   echo "In case you have more than one version installed, you may use the OPENFORTIVPN variable to pass another installed openfortivpn."
#   echo ""
#   usage
#   exit 1
# fi


# ##############################################################################
# # Check that openfortivpn-webview is installed
# ##############################################################################

# if [[ -z \$OPENFORTIVPN_WEBVIEW ]]; then
#   cat <<EOL
# ERROR: openfortivpn-webview not found in the system.
# If not installed, please download and install the latest version from
#   https://github.com/gm-vm/openfortivpn-webview/releases/latest

# If it is installed but not in the PATH, consider passing its location in the
# OPENFORTIVPN_WEBVIEW variable. Example:
#   OPENFORTIVPN_WEBVIEW=/home/user/openfortivpn-webview-1.2.3.AppImage \$scriptname

# $(echo EOL)
#   usage
#   exit 1
# fi


# ##############################################################################
# # Parse options
# ##############################################################################

# if [ "\$#" -eq 0 ]; then
#   usage
#   exit 0
# fi

# openfortivpnwebview_opts=()
# vpngateway=''

# while [ "\$#" -gt 0 ]; do
#   case "\$1" in
#   -h | --help)
#     usage
#     exit 0
#     ;;
#   *)
#     if [ -z \$vpngateway ]; then
#       if [[ \$1 = -* ]]; then
#         echo "ERROR: invalid host[:port]"
#         echo ""
#         usage
#         exit 1
#       fi
#       vpngateway=\$1
#       shift 1
#     elif [ \$1 = "--" ]; then
#       shift 1
#       break
#     else
#       openfortivpnwebview_opts+=("\$1")
#       shift 1
#     fi
#     ;;
#   esac
# done

# ##############################################################################
# # Run openfortivpn-sso
# ##############################################################################

# if [ \$(id -u) -eq 0 ]; then
#   echo "For security reasons, this script should not be run as root"
#   exit 1
# fi

# while true; do
#   cookie=\$(\$OPENFORTIVPN_WEBVIEW \$vpngateway \$openfortivpnwebview_opts 2>/dev/null)
#   if [ \$? -ne 0 ]; then
#     # Exit if the browser window has been closed manually.
#     exit 0
#   fi
#   echo \$cookie | sudo \$OPENFORTIVPN \$vpngateway --cookie-on-stdin \$@
#   if [ \$? -eq 0 ]; then
#     # Exit if openfortivpn has been closed manually
#     exit 0
#   fi
# done
# EOL

  $([ $SUDO -eq 1 ] && echo sudo) chmod +x $openfortivpnsso

  echo "openfortivpn-sso installed to $openfortivpnsso"
}

install_openfortivpn-sso

echo ""

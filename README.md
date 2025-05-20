# openfortivpn-sso

A helper script to connect to Fortinet VPN servers using SSO (Single Sign-On) with [`openfortivpn`](https://github.com/adrienverge/openfortivpn) and [`openfortivpn-webview`](https://github.com/gm-vm/openfortivpn-webview).

## Features

- Automates SSO authentication for Fortinet VPNs.
- Supports both AppImage and .deb installations of `openfortivpn-webview`.
- Handles proxy configuration for webview authentication.
- Installs and updates dependencies as needed.
- Creates group `openfortivpn` of users that can run it without being asked for a (sudo) password

## Installation

### 1. Download the repository

Clone or download the repository files to your system.

### 2. Run the installer

By default, the script installs `openfortivpn-sso` to `/usr/local/bin` and will prompt to install or update dependencies if needed.

```sh
sudo ./install.sh
```

#### Options

- `-p, --prefix <prefix>`: Install to a custom directory (e.g., `$HOME/.local/bin`)
- `-u, --update`: Update `openfortivpn` and `openfortivpn-webview` to the latest versions
- `-y, --yes`: Assume "yes" to all prompts (for automation)

**Examples:**

Install to default location and install dependencies if needed:

```sh
sudo ./install.sh --update
```

Install to a custom location:

```sh
./install.sh -p $HOME/.local/bin
```

## Usage

After installation, run:

```sh
openfortivpn-sso <host[:port]> [openfortivpn-webview_opts] [-- openfortivpn_opts]
```

- `host[:port]`: The VPN gateway address.
- `[openfortivpn-webview_opts]`: Options for `openfortivpn-webview` (see `openfortivpn-webview --help`).
- `[-- openfortivpn_opts]`: Options passed directly to `openfortivpn` (see `openfortivpn --help`).

**Example:**

```sh
openfortivpn-sso vpngateway.example.com
```

### Proxy Support

If you need to use an HTTP proxy:

- **AppImage version**:

  ```sh
  openfortivpn-sso host[:port] --proxy-server=proxy.example.com:8080 [other_webview_opts] [-- openfortivpn_opts]
  ```

- **Deb version**:

  ```sh
  QTWEBENGINE_CHROMIUM_FLAGS="--proxy-server=proxy.example.com:8080" openfortivpn-sso host[:port] [webview_opts] [-- openfortivpn_opts]
  ```

### Environment Variables

- `OPENFORTIVPN`: Path to `openfortivpn` if not in `PATH`.
- `OPENFORTIVPN_WEBVIEW`: Path to `openfortivpn-webview` if not in `PATH`.

**Example:**

```sh
OPENFORTIVPN=/opt/openfortivpn OPENFORTIVPN_WEBVIEW=$HOME/Downloads/openfortivpn-webview.AppImage openfortivpn-sso vpngateway.example.com
```

## Group Permissions

The installer can create an `openfortivpn` group and add your user, allowing passwordless `sudo` for `openfortivpn` (for convenience).

- Add a user:  
  `sudo usermod -a -G openfortivpn username`
- Remove a user:  
  `sudo gpasswd -d username openfortivpn`

## Troubleshooting

- Ensure `openfortivpn` version is **greater than 1.19.0**.
- If dependencies are missing, rerun the installer with `-u` or install them manually.
- For more help, run:

  ```sh
  openfortivpn-sso --help
  ```

## License

See the respective licenses for `openfortivpn` and `openfortivpn-webview`.

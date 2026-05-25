# Relay Server Setup Script

This repository contains an automated **relay setup** script.

## Requirements

- Ubuntu 24.04/26.04 with `sudo` available.

## Usage

Clone repo:

```sh
git clone https://github.com/x13a/setup-relay
cd setup-relay
```

Run setup:

```sh
./setup.sh
```

Enter a destination IPv4 address, IPv6 address, or domain name, then the port
and protocol.

The resolved IP is saved in the firewall rules; DNS changes are not tracked
automatically. If the IP changes, remove the old relay rules and run setup again.

## License

MIT

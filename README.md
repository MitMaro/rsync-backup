# Rsync Backup Script

[![GitHub license](https://img.shields.io/badge/license-ISC-blue.svg)](https://raw.githubusercontent.com/MitMaro/rsync-backup/master/LICENSE.md)

A wrapper around rsync to create a remote backup of any set of files on a schedule.

## Default files

This script will always back up the following:

- `$HOME/README.md`
- `$HOME/.ssh`
- `/etc/cron.d/backup`
- The installed script (default: `$HOME/backup.sh`)

## Install

The default location the script will install is to `$HOME/backup.sh`, this can be changed by using the `BACKUP_INSTALL_LOCATION`.

```shell
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash install
```

## Update

The script will automatically pull updates from GitHub.

To manually update, from the project directory:

```shell
git fetch origin && git reset --hard origin/master
``` 

## Usage

The following environment variables are available:

- BACKUP_SERVER_IP - The IP address of the target server
- BACKUP_IDENTIFIER - A unique id for the source device/server
- BACKUP_SSH_USER - The SSH user on the target server
- BACKUP_IDENT_FILE - The SSH key for SSH communication
- BACKUP_PATHS - An array of paths to backup

Generally this script is used through the script created through the installation process. However, the following options can be provided as arguments to the script, however not all options will work as expected.

```
Usage: backup.sh [options] <src, [src...]>

Options:
  --target, -t      The directory on the target to copy files. (required)

  --ssh-server      The SSH server. (required)

  --identifier, -i  A unique identifier for this computer. Default: hostname

  --ssh-port        The SSH connection port.

  --ssh-user        The SSH user. Default: current user

  --ssh-ident       The SSH key to use.

  --verbose, -v     Show more verbose output of actions performed.

  --no-color        Disable colored output.

  --dry-run         Run rsync in dry run mode. Providing this options also assumes --verbose.

  --log-to-file     Log output to a file located inside ~/.local/rsync-backup instead of to stdout.

  --exclude-file    An rsync exclude file, used to filter out files.

  --include-file    An rsync include file, used to include files, even if excluded.

  --help            Show this usage message and exit.
```

## Use case

This script can be used to automatically back up a list of paths, generally useful in server environments. I use it to back up files from various Proxmox LXCs in my homelab.

## License

Rsync Backup is released under the ISC license. See [LICENSE](LICENSE).

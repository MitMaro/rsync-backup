# Rsync Backup

[![GitHub license](https://img.shields.io/badge/license-ISC-blue.svg)](https://raw.githubusercontent.com/MitMaro/rsync-backup/master/LICENSE.md)

A wrapper around rsync to create a remote backup of any set of files.

## Install

    git clone https://github.com/MitMaro/rsync-backup.git /path/to/install/location
    alias rsync-backup="/path/to/install/location/sync.sh"

## Usage

    rsync backup
    
    Usage: rsync-backup [options] <src, [src...]>
    
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

### Example usage

Syncs my home directory to a drive mounted at `192.168.1.100:/Volumes/Data/Sync` using an include and exclude file.

    ./sync.sh \
        -target /Volumes/Data/Sync \
        --ssh-server 192.168.1.100 \
        --include-file /home/mitmaro/.local/rsync-backup/include-list.lst \
        --exclude-file /home/mitmaro/.local/rsync-backup/exclude-list.lst \
        /home/mitmaro

## Use Case

There are few cloud backup services that support Linux with had the features that I was looking for and for a decent
price. I also really liked the offering that [Sync.com](https://www.sync.com/?_sync_refer=33cbaa0) offered.
*(disclosure: contains referral link)* As a Canadian, Sync.com being a Canadian company was the biggest plus. They do
not however offer a Linux client. I created this script to sync, via a cron job, the files from my Linux laptop to an
external drive attached to an I had an old Apple laptop kicking around. The old laptop is running the Sync.com client
and syncs my files to Sync.com.

## License

Rsync Backup is released under the ISC license. See [LICENSE](LICENSE).

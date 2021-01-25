# Pulsar Favorites Sync

![GPL v3.0](https://img.shields.io/github/license/patrick96/notification-mount.svg)

**THIS SCRIPT NO LONGER WORKS FOR ME, USE AT YOUR OWN RISK!**

This script helps you synchronize your list of favorites in the [Pulsar Music Player][pulsar] with a local playlist on
your computer.

# Requirements

This script was designed to work on Linux but it should work on any system that can run bash.

* [sqlite3](https://www.sqlite.org/)
* Java
* [Android Platform Tools (for adb)](https://developer.android.com/studio/releases/platform-tools.html)

Additionally if this script should be useful, you will need to have the same folder structure for your
music files on your computer and your phone. So for any file the path relative to the music directory
should be the same on your phone and computer

# Usage

**Warning:** I have noticed that after the restore the favorites playlist in pulsar may be empty. If you encounter this, 
you may be unable to sync your playlist to the phone, only from it. To restore the original favorites playlist before it 
was wiped, look for the line `Starting syncing process in /tmp/tmp.XXXXXXXXX` in the output of `sync.sh` when you ran it 
before. That folder in `/tmp` contains a file `backup.ab`, run `adb restore backup.ab` to restore the original favorites 
list in pulsar.

First make sure you meet all the requirements described above, if you don't, things could go wrong.

Now clone this repository with its submodules:
``` bash
git clone --recursive https://github.com/patrick96/pulsar-favorites-sync
cd pulsar-favorites-sync
```

Connect your android phone to your computer, make sure to enable usb debugging on the phone.
Use `adb devices` to make sure it is recognized. If you have multiple devices connected, disconnect
all except for the one you want to synchronize (Multiple connected android devices are not supported)

Now you will need to set the path to the music folder on your phone and the path to the desired playlist
file on your computer inside the sync script.
For that open `sync.sh` at the line starting with `MUSIC_FOLDER` replace `%INSERT PATH HERE%` with the 
absolute path to the music folder on your phone.
On the line starting with `FAVORITES` replace `%INSERT PATH HERE%` with the path to your local favorites
playlist.

For me this would look like this:
``` bash
MUSIC_FOLDER="/storage/9C33-6BBD/Music/"
FAVORITES="$HOME/Music/Playlists/f.m3u"
```

Now you can run `./sync.sh`

This will shortly after prompt you for an encryption password to export the favorites database from
your phone, insert '1' (without the quotes) and press "BACK UP MY DATA"

Now the script will merge the favorites from the specified favorites files with the ones from your
phone. It will also create a backup of the old favorites file, just in case.

The merged favorites will now be copied back onto the phone, for that your phone will ask you for a 
decryption password, which you can leave empty.

Now you should be done.
But also check if everything was successful because your phone will not tell you if there was an error
with syncing the favorites back to your phone, if you feel like something went wrong check the output of `adb logcat | grep "BackupManagerService"`

[pulsar]: https://play.google.com/store/apps/details?id=com.rhmsoft.pulsar

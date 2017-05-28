#!/usr/bin/env bash

__ScriptVersion="0.0.1"

function usage() {
    echo -e "Usage: $0 [options]"
    echo -e "Description: Sync favorites from pulsar with a local playlist"
    echo -e "Options:"
    echo -e "    -h: Display this help message"
    echo -e "    -v: Display script version"
}

function version() {
    echo "$0 -- Version $__ScriptVersion"
}

do_exit=0

while getopts ":hv" opt; do
    case $opt in
        h)
            usage
            do_exit=1
            ;;
        v)
            version
            do_exit=1
            ;;

        *)
            echo "Invalid option: -$OPTARG" >&2
            usage
            exit 1
            ;;
    esac 
done
shift $((OPTIND-1))

[ $do_exit -eq 1 ] && exit 0

# Root folder for your music files on your phone
MUSIC_FOLDER="%INSERT PATH HERE%"
FAVORITES="%INSERT PATH HERE%"

pkg="com.rhmsoft.pulsar"
wd="$(mktemp -d)"

# The playlist exported from pulsar will be saved here
exported="$wd/exported.m3u"
merged="$wd/merged.m3u"

# The old playlist will be copied to here before it is overwritten
backup="$wd/backup.m3u"

restore="$wd/restore.sql"

echo "Starting syncing process in $wd"

# Build abe {{{
# TODO only build once and then copy to cache
cd libs/android-backup-extractor || exit 1
./gradlew
cp build/libs/abe-all.jar "$wd"
# }}}

# Export from phone {{{

cd "$wd" || exit 1

echo "Creating backup please use 1 as the password"
# Set password to 1
adb backup -noapk "$pkg" || exit 1

echo "Encrypting and extracting backup.ab"
# Backup application data from phone, decrypt and extract it
java -jar abe-all.jar unpack "$wd/backup.ab" "$wd/backup.tar" "1"
tar xf backup.tar
cd "apps/$pkg/db" || exit 1

echo "Exporting pulsar favorites to $exported"

# Read the absolute paths of the favorites from the database
# Remove the root music folder from the paths to get the relative paths
# Finally remove leading slashes from the paths, if $MUSIC_FOLDER doesn't end with a slash
sqlite3 player.db 'select data from favorites;' | sed "s|^$MUSIC_FOLDER||" | sed 's/^\///' > "$exported"

cd ../../../ || exit 1

# Append local favorites to the exported ones
cat "$FAVORITES" >> "$exported"

# Remove empty lines
sed -i '/^$/d' "$exported"

# Remove duplicates
awk '!x[$0]++' "$exported" > "$merged"

# Backup old favorites file
cp "$FAVORITES" "$backup"
echo "Old favorites were successfully backed up to $backup"

# Overwrite with new favorites
cp "$merged" "$FAVORITES"

echo -e "\e[0;32mSuccessfully merged favorites into $FAVORITES\e[0m"

# }}}

# Sync to phone {{{

echo "BEGIN TRANSACTION;" > "$restore"

while read -r f ; do
    echo "INSERT INTO 'favorites' ('data') VALUES ('${MUSIC_FOLDER}${f//\'/\'\'}');" >> "$restore"
done < "$FAVORITES"

echo "COMMIT;" >> "$restore"

cd "apps/$pkg/db" || exit 1

sqlite3 player.db 'DELETE FROM favorites' || exit 1

sqlite3 -batch player.db < "$restore" || exit 1

cd ../../../ || exit 1

# Create tar archive of the modified app data
tar --create --file apps.tar apps || exit 1

# We need to create a list of files to be included in the backup file to restore because adb restore doesn't handle
# paths with trailing slashes (representing folders) and the _manifest entry has to be at the beginning
# We exclude any hidden files starting with "."
tar tf apps.tar | grep -F "$pkg" | grep -v "\/\." > package.list || exit 1

# Remove lines that end with a slash (adb restore doesn't like that)
sed -i '/\/$/d' package.list

# The _manifest file needs to be at the start of the archive
manifestLine="$(grep -F "_manifest" < package.list)"
nonManifestLines="$(grep -v -F "_manifest" < package.list)"

echo "$manifestLine" > package.list
echo "$nonManifestLines" >> package.list

# Create tar restore archive from the file list
tar cf restore.tar -T package.list || exit 1

# Repack w/o password
java -jar abe-all.jar pack restore.tar restore.ab "" || exit 1

echo "Restoring updates favorites on phone"
echo "When prompted for a password, leave the password field empty"
adb restore restore.ab || exit 1

echo "Restore finished"
echo "Please check if the data was successfully restored to the phone, if not check for errors with"
echo -e "    \e[1;31madb logcat | grep \"BackupManagerService\"\e[0m"
# }}}

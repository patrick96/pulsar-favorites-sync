#!/usr/bin/env bash

__ScriptVersion="0.0.1"
encryption_pw="1"

# Package name of the android application
pkg="com.rhmsoft.pulsar"

# Root folder for your music files on your phone
MUSIC_FOLDER=""
FAVORITES=""

# Required argument flags
r_flag=0
f_flag=0

function usage() {
    echo -e "Usage: $0 [options]"
    echo -e "Description: Sync favorites from pulsar with a local playlist"
    echo -e "Options:"
    echo -e "    -h                 Display this help message"
    echo -e "    -v                 Display script version"
    echo -e "    -e PW              Set the encryption password to PW"
    echo -e "    -r PATH (required) Set the absolute path to the music folder on your phone"
    echo -e "    -f FILE (required) Location of the local playlist file to sync with"
}

function version() {
    echo "$0 -- Version $__ScriptVersion"
}

function echoerr() {
    echo -e "\e[0;31m$*\e[0m"
}

while getopts ":hve:r:f:" opt; do
    case $opt in
        h)
            usage
            exit 0;
            ;;
        v)
            version
            exit 0;
            ;;
        e)
            encryption_pw="$OPTARG"
            ;;
        r)
            r_flag=1
            MUSIC_FOLDER="$OPTARG"
            ;;
        f)
            f_flag=1
            FAVORITES="$OPTARG"
            ;;
        ?)
            echo "Invalid option: -$OPTARG" >&2
            usage
            exit 1
            ;;
    esac
done
shift $((OPTIND-1))

# Exit on missing required arguments
if [ $r_flag -eq 0 ] || [ $f_flag -eq 0 ]; then

    # Color all subsequent warning red
    echo -en "\e[1;31m"

    if [ $r_flag -eq 0 ]; then
        echo "The -r argument is required"
    fi

    if [ $f_flag -eq 0 ]; then
        echo "The -f argument is required"
    fi

    echo -en "\n\e[0m"

    usage
    exit 1
fi

if [ -z "$MUSIC_FOLDER" ] ||  ! adb shell test -d "$MUSIC_FOLDER"; then
    echoerr "The given music folder \"$MUSIC_FOLDER\" was not found on the phone. Is your phone plugged in?"
    exit 1
fi

if [ -z "$FAVORITES" ]; then
    echoerr "The path to the local playlist file cannot be empty."
    exit 1
fi

if ! [ -f "$FAVORITES" ]; then
    echo "The local favorites playlist file \"$FAVORITES\" does not exist yet, creating..."
    touch "$FAVORITES"
fi

echo -e "Music folder on phone:\n\t$MUSIC_FOLDER"
echo -e "Local playlist:\n\t$(realpath "$FAVORITES")"

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

echo "Creating backup please use \"$encryption_pw\" as the password (without the quotes)"
adb backup -noapk "$pkg" || exit 1

echo "Encrypting and extracting backup.ab"
# Backup application data from phone, decrypt and extract it
java -jar abe-all.jar unpack "$wd/backup.ab" "$wd/backup.tar" "$encryption_pw"
tar xf backup.tar
cd "apps/$pkg/db" || exit 1

echo "Exporting pulsar favorites to $exported"

# Read the absolute paths of the favorites from the database
# Remove the root music folder from the paths to get the relative paths
# Finally remove leading slashes from the paths, if $MUSIC_FOLDER doesn't end with a slash
sqlite3 player.db 'select data from favorites;' | sed "s|^$MUSIC_FOLDER||" | sed 's/^\///' > "$exported"

cd - || exit 1

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

cd - || exit 1

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

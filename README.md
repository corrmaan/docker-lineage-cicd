# LineageOS Docker Build

Forked from [lineageos4microg/docker-lineage-cicd][docker-lineage-cicd]. Check that out for more information on how the builder works.

## Changes
<!-- Applied as user scripts in `USERSCRIPTS_DIR`: -->

I made a few changes for my Pixel 2 (walleye):

 * [Verified boot and support for bootloader locking][rattlesnakeos-stack]
 * [OpenGApps][vendor_opengapps]
    * Looks like only nano is supported right now for Android 11 (lineage-18.1)
 * [Magisk][magisk]
    * If enabled will first build LineageOS without Magisk, then will build it at the very end as an OTA update.
    * Make sure to install the factory image first that gets built first, then apply the Magisk OTA update, or you will probably get bootloops.

Feel free to try on your other devices and submit a PR when you get it working.

## How to Build

Say you clone this to `~/android/docker-lineage-cicd` and your local build directory is in `~/data/lineageos`,

```
$ mkdir -pv \
	${HOME}/data/lineageos/cache \
    ${HOME}/data/lineageos/keys \
    ${HOME}/data/lineageos/local_manifests \
    ${HOME}/data/lineageos/logs \
    ${HOME}/data/lineageos/src \
    ${HOME}/data/lineageos/zips
$ cd ${HOME}/data/lineageos
$ ln -s ${HOME}/android/docker-lineage-cicd/userscripts ./
$ cd ${HOME}/android/lineageos/docker-lineage-cicd
$ docker build -t docker-lineage-cicd .
$ ./docker-lineage-cicd.sh
```

## How to Run

```
$ docker run --privileged --rm \
    -e CCACHE_SIZE=0 \
    -e BRANCH_NAME="lineage-18.1" \
    -e DEVICE_LIST="walleye" \
    -e RELEASE_TYPE='signed' \
    -e USER_NAME='Your Name' \
    -e USER_MAIL='abc@123.com' \
    -e INCLUDE_PROPRIETARY=false \
    -e CLEAN_OUTDIR=false \
    -e CLEAN_AFTER_BUILD=true \
    -e ANDROID_JACK_VM_ARGS="-Dfile.encoding=UTF-8 -XX:+TieredCompilation -Xmx12G" \
    -e SIGN_BUILDS=true \
    -e ZIP_SUBDIR=false \
    -e LOGS_SUBDIR=false \
    -e CLEAN_REPOS=true \
    -e MICROG=false \
    -e GAPPS=true \
    -e MAGISK=true \
    -v "${HOME}/data/lineageos/cache:/srv/ccache" \
    -v "${HOME}/data/lineageos/keys:/srv/keys" \
    -v "${HOME}/data/lineageos/local_manifests:/srv/local_manifests" \
    -v "${HOME}/data/lineageos/logs:/srv/logs" \
    -v "${HOME}/data/lineageos/src:/srv/src" \
    -v "${HOME}/data/lineageos/userscripts:/srv/userscripts" \
    -v "${HOME}/data/lineageos/zips:/srv/zips" \
    docker-lineage-cicd \
    |& tee "${scriptName%.*}-$(date -u '+%F-%H-%M').log"
```

## Next Steps

Follow dan-v's [flashing instructions][ros-flashing].

[docker-lineage-cicd]: https://github.com/lineageos4microg/docker-lineage-cicd
[magisk]: https://github.com/topjohnwu/Magisk 
[ros-flashing]: https://github.com/dan-v/rattlesnakeos-stack/blob/11.0/FLASHING.md
[rattlesnakeos-stack]: https://github.com/dan-v/rattlesnakeos-stack
[ros-flashing]: https://github.com/dan-v/rattlesnakeos-stack/blob/11.0/FLASHING.md
[vendor_opengapps]: https://github.com/opengapps/aosp_build
[vendor_mindthegapps]: https://gitlab.com/MindTheGapps/vendor_gapps

#!/usr/bin/env bash
#
# docker-lineage-cicd pre-build.sh script
# Runs before 
#   brunch $codename
# with the device codename being the first and only argument.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

codename=$1
BRANCH_NAME=$2

if [ "$INCLUDE_PROPRIETARY" = false ] || [ "$GAPPS" = true ] || [ "$MAGISK" = true ]; then
    source build/envsetup.sh > /dev/null
    breakfast $codename
fi

if [ "$GAPPS" = true ]; then
    case "${codename}" in
    walleye)
        # For MindtheGApps
        # echo '$(call inherit-product, vendor/mindthegapps/arm64/arm64-vendor.mk)' >> "device/google/muskie/device-walleye.mk"
        
        # For OpenGApps, had to axe CarrierServices so it would build.
        sed -i '/CarrierServices.apk/d' "device/google/muskie/lineage-proprietary-files.txt"
        sed -i '1s/^/GAPPS_VARIANT := nano\nGAPPS_FORCE_PACKAGE_OVERRIDES := true\n/' "device/google/muskie/device-walleye.mk"
        echo '$(call inherit-product, vendor/opengapps/build/opengapps-packages.mk)' >> "device/google/muskie/device-walleye.mk"
        ;;
    *)
        echo ">> [$(date)] Add GAPPS support for ${codename} to pre-build.sh."
        exit 1
        ;;
    esac
fi

if [ "$INCLUDE_PROPRIETARY" = false ]; then
    # Instructions from https://wiki.lineageos.org/extracting_blobs_from_zips.html
    mkdir -pv /root/factory

    LOS_BUILD_DATE=$(curl https://download.lineageos.org/$codename | grep -o '<a href=[^<]*<\/a>' | head -n5 | tail -n1 | cut -d'>' -f 2 | cut -d'<' -f1 | cut -d'-' -f3)
    LOS_BUILD_ZIP=${BRANCH_NAME}-${LOS_BUILD_DATE}-nightly-${codename}-signed.zip

    if [ -f /root/userscripts/${LOS_BUILD_ZIP} ] && [ -f /root/userscripts/${LOS_BUILD_ZIP}.sha256 ]; then
        cp /root/userscripts/${LOS_BUILD_ZIP}* /root/factory/
    else
        wget -P /root/factory --no-verbose --no-check-certificate "https://lineageos.mirrorhub.io/full/${codename}/${LOS_BUILD_DATE}/${LOS_BUILD_ZIP}"
        curl --output /root/factory/${LOS_BUILD_ZIP}.sha256 "https://mirrorbits.lineageos.org/full/${codename}/${LOS_BUILD_DATE}/${LOS_BUILD_ZIP}?sha256"
        cp -v /root/factory/${LOS_BUILD_ZIP}* /root/userscripts/
    fi
    cd /root/factory
    sha256sum -c ${LOS_BUILD_ZIP}.sha256 || exit 1
    cd -

    case "$codename" in
    walleye)
        DEVICE_DIR=device/google/muskie
        ;;
    *)
        echo ">> [$(date)] Add proprietary blob support for $codename to pre-build.sh."
        exit 1
        ;;
    esac

    unzip -l /root/factory/${LOS_BUILD_ZIP} | grep -q "system.*.dat.*";
    if [ "${PIPESTATUS[1]}" == 0 ]; then
        OTA_TYPE=block
    else
        unzip -l /root/factory/${LOS_BUILD_ZIP} | grep -q " system ";
        if [ "${PIPESTATUS[1]}" == 0 ]; then
            OTA_TYPE=file
        else
            unzip -l /root/factory/${LOS_BUILD_ZIP} | grep -q "payload.bin";
            if [ "${PIPESTATUS[1]}" == 0 ]; then
                OTA_TYPE=payload
            else
                echo ">> [$(date)] Unknown OTA format for ${LOS_BUILD_ZIP}."
                exit 1
            fi
        fi
    fi

    case "${OTA_TYPE}" in
    block)
        add-apt-repository universe
        apt-get update
        apt-get -y install brotli
        git -C /root/factory clone https://github.com/xpirt/sdat2img

        mkdir -pv /root/factory/system_dump/system
        cd /root/factory/system_dump/
        unzip /root/factory/${LOS_BUILD_ZIP} system.transfer.list system.new.dat*
        if [ $(unzip -l /root/factory/${LOS_BUILD_ZIP} | grep -q "vendor.transfer.list" | echo $?) == 0 ]; then
            unzip -l /root/factory/${LOS_BUILD_ZIP} vendor.transfer.list
        fi
        if [ $(unzip -l /root/factory/${LOS_BUILD_ZIP} | grep -q "vendor.new.dat.*" | echo $?) == 0 ]; then
            unzip -l /root/factory/${LOS_BUILD_ZIP} vendor.new.dat*
            mkdir -v vendor
        fi
        if [ -f system.new.dat.br ]; then
            brotli --decompress --output=system.new.dat system.new.dat.br
        fi
        if [ -f vendor.new.dat.br ]; then
            brotli --decompress --output=vendor.new.dat vendor.new.dat.br
        fi
        python /root/factory/sdat2img/sdat2img.py system.transfer.list system.new.dat system.img
        if [ -f vendor.new.dat ]; then
            python /root/factory/sdat2img/sdat2img.py vendor.transfer.list vendor.new.dat vendor.img
        fi
        mount system.img system/
        if [ -f vendor.img ]; then
            mount vendor.img system/vendor/
        fi
        cd -

        cd ${DEVICE_DIR}
        ./extract-files.sh /root/factory/system_dump/
        cd -

        umount -R /root/factory/system_dump/system/
        rm -rf /root/factory/system_dump/
        ;;
    file)
        mkdir -pv /root/factory/system_dump/
        cd /root/factory/system_dump/
        unzip /root/factory/${LOS_BUILD_ZIP} system/*
        cd -

        cd ${DEVICE_DIR}
        ./extract-files.sh /root/factory/system_dump/
        cd -
        
        rm -rf /root/factory/system_dump/
        ;;
    payload)
        apt-get -y install python-dev python-protobuf liblzma-dev
        git -C /root/factory clone git://github.com/peterjc/backports.lzma.git

        cd /root/factory/backports.lzma
        python setup.py install
        cd -

        BRANCH_DIR=$PWD
        mkdir -pv /root/factory/system_dump/system
        cd /root/factory/system_dump/
        unzip /root/factory/${LOS_BUILD_ZIP} payload.bin
        python ${BRANCH_DIR}/lineage/scripts/update-payload-extractor/extract.py payload.bin --output_dir ./
        mount system.img system/
        mount vendor.img system/vendor/
        mount product.img system/product/
        cd -

        cd ${DEVICE_DIR}
        ./extract-files.sh /root/factory/system_dump/
        cd -

        umount -R /root/factory/system_dump/system/
        rm -rf /root/factory/system_dump/
        ;;
    esac
fi

if [ "$MAGISK" = true ]; then
    patch -p1 --verbose < /root/magisk_mkbootfs.patch
fi

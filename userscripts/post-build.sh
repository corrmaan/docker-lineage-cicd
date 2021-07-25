#!/usr/bin/env bash
#
# docker-lineage-cicd post-build.sh script
# Runs after
#   brunch $codename
# with the device codename being the first argument, a boolean
# TRUE/FALSE value being the second argument indicating whether
# or not the build was successful.
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
build_successful=$2

if [ "$build_successful" = true ]; then
    if [ "$SIGN_BUILDS" = true ]; then
        source build/envsetup.sh > /dev/null
        if breakfast $codename; then
            case "$codename" in
            walleye)
                CODENAME_AOSP=walleye
                DEVICE_AOSP=walleye
                AOSP_BUILD="RP1A.201005.004.A1"
                AOSP_BRANCH="android-11.0.0_r25"
                ;;
            *)
                echo ">> [$(date)] Add build signing support for $codename to post-build.sh."
                exit 1
                ;;
            esac

            avb_tool="/root/avbtool.py"
            rm -rf "${avb_tool}"

            if [ ! -f "${avb_tool}" ]; then
                curl --fail -s "https://android.googlesource.com/platform/external/avb/+/refs/tags/${AOSP_BRANCH}/avbtool?format=TEXT" | \
                    base64 --decode > "${avb_tool}"
                if [ ! -s "${avb_tool}" ]; then
                    curl --fail -s "https://android.googlesource.com/platform/external/avb/+/refs/tags/${AOSP_BRANCH}/avbtool.py?format=TEXT" | \
                        base64 --decode > "${avb_tool}"
                fi
                chmod +x "${avb_tool}"
            fi

            if [ -z "$(ls -A "$KEYS_DIR/avb.pem" "$KEYS_DIR/avb_pkmd.bin")" ]; then
                echo ">> [$(date)] SIGN_BUILDS = true but no avb keys in \$KEYS_DIR, generating new keys"
                openssl genrsa -out "$KEYS_DIR/avb.pem" 4096
                "${avb_tool}" extract_public_key --key "$KEYS_DIR/avb.pem" --output "$KEYS_DIR/avb_pkmd.bin"
            else
                for c in avb.pem avb_pkmd.bin; do
                    if [ ! -f "$KEYS_DIR/$c" ]; then
                        echo ">> [$(date)] SIGN_BUILDS = true and not empty \$KEYS_DIR, but \"\$KEYS_DIR/$c\" is missing"
                        exit 1
                    fi
                done
            fi

            # Mostly from https://github.com/dan-v/rattlesnakeos-stack/blob/v11.0.6/templates/build_template.go
            # Copyright (c) 2017 Dan Vittegleo
            echo ">> [$(date)] Starting target-files-package build for $codename"
            if mka target-files-package; then
                echo ">> [$(date)] Starting otatools build for $codename"
                if mka otatools; then
                    echo ">> [$(date)] Starting brillo_update_payload build for $codename"
                    if mka brillo_update_payload; then
                        # From rattlesnakeos-stack:
                        case "$codename" in
                        taimen)
                            DEVICE_FAMILY=taimen
                            DEVICE_COMMON=wahoo
                            AVB_MODE=vbmeta_simple
                            ;;
                        walleye)
                            DEVICE_FAMILY=muskie
                            DEVICE_COMMON=wahoo
                            AVB_MODE=vbmeta_simple
                            ;;
                        crosshatch|blueline)
                            DEVICE_FAMILY=crosshatch
                            DEVICE_COMMON=crosshatch
                            AVB_MODE=vbmeta_chained
                            EXTRA_OTA=(--retrofit_dynamic_partitions)
                            ;;
                        sargo|bonito)
                            DEVICE_FAMILY=bonito
                            DEVICE_COMMON=bonito
                            AVB_MODE=vbmeta_chained
                            EXTRA_OTA=(--retrofit_dynamic_partitions)
                            ;;
                        flame|coral)
                            DEVICE_FAMILY=coral
                            DEVICE_COMMON=coral
                            AVB_MODE=vbmeta_chained_v2
                            ;;
                        sunfish)
                            DEVICE_FAMILY=sunfish
                            DEVICE_COMMON=sunfish
                            AVB_MODE=vbmeta_chained_v2
                            ;;
                        *)
                            echo ">> [$(date)] AVB signing for $codename not supported."
                            exit 1
                            ;;
                        esac

                        echo ">> [$(date)] AVB signing $codename."
                        
                        CFI="/root/clear-factory-images-variables.sh"
                        curl --fail -s "https://android.googlesource.com/device/common/+/refs/tags/${AOSP_BRANCH}/clear-factory-images-variables.sh?format=TEXT" | \
                            base64 --decode > "${CFI}"
                        source "${CFI}"

                        mkdir -pv /root/factory
                        
                        FACTORY_IMG_PREFIX="${CODENAME_AOSP}-$(tr '[:upper:]' '[:lower:]' <<< ${AOSP_BUILD})-factory"
                        if [ -n $(find /root/userscripts/ -name "${FACTORY_IMG_PREFIX}*.zip" -type f) ]; then
                            cp $(find /root/userscripts/ -name "${FACTORY_IMG_PREFIX}*.zip" -type f) /root/factory/
                        else
                            echo ">> [$(date)] Downloading factory image for ${CODENAME_AOSP}-${AOSP_BUILD}"
                            git clone --depth=1 https://github.com/RattlesnakeOS/android-prepare-vendor.git /root/android-prepare-vendor
                            /root/android-prepare-vendor/scripts/download-nexus-image.sh -d ${CODENAME_AOSP} -b ${AOSP_BUILD} -o /root/factory -y
                        fi
                        FACTORY_IMG=$(find /root/factory/ -name "${FACTORY_IMG_PREFIX}*.zip" -type f)
                        
                        BOOTLOADER=$(zip -sf ${FACTORY_IMG} | grep bootloader | cut -d'-' -f4- | awk -F".img" '{print $1}')
                        RADIO=$(zip -sf ${FACTORY_IMG} | grep radio | cut -d'-' -f4- | awk -F".img" '{print $1}')

                        [ -n "$BOOTLOADER" ] && BOOTLOADERFILE=${CODENAME_AOSP}-$(tr '[:upper:]' '[:lower:]' <<< ${AOSP_BUILD})/bootloader-${DEVICE_AOSP}-$BOOTLOADER.img
                        [ -n "$RADIO" ] && RADIOFILE=${CODENAME_AOSP}-$(tr '[:upper:]' '[:lower:]' <<< ${AOSP_BUILD})/radio-${DEVICE_AOSP}-$RADIO.img
                        
                        echo ">> [$(date)] Extracting bootloader and radio images from factory image"
                        unzip ${FACTORY_IMG} ${BOOTLOADERFILE} ${RADIOFILE} -d /root/factory
                        [ -n "$BOOTLOADERFILE" ] && BOOTLOADERFILE="/root/factory/${BOOTLOADERFILE}"
                        [ -n "$RADIOFILE" ] && RADIOFILE="/root/factory/${RADIOFILE}"
                        
                        BUILD="${BRANCH_NAME}-$(date +%Y%m%d)-${RELEASE_TYPE}"                
                        TARGET_FILES="$codename-target_files-${BUILD}.zip"
                        PRODUCT="$codename"
                        VERSION=$(echo "${AOSP_BUILD}" | tr '[:upper:]' '[:lower:]')
                        DEVICE="${CODENAME_AOSP}"

                        # pick avb mode depending on device and determine key size
                        avb_key_size=$(openssl rsa -in "${KEYS_DIR}/avb.pem" -text -noout | grep 'Private-Key' | awk -F '[()]' '{print $2}' | awk '{print $1}')
                        avb_algorithm="SHA256_RSA${avb_key_size}"
                        case "${AVB_MODE}" in
                            vbmeta_simple)
                            # Pixel 2: one vbmeta struct, no chaining
                            AVB_SWITCHES=(--avb_vbmeta_key "${KEYS_DIR}/avb.pem"
                                            --avb_vbmeta_algorithm "${avb_algorithm}")
                            ;;
                            vbmeta_chained)
                            # Pixel 3: main vbmeta struct points to a chained vbmeta struct in system.img
                            AVB_SWITCHES=(--avb_vbmeta_key "${KEYS_DIR}/avb.pem"
                                            --avb_vbmeta_algorithm "${avb_algorithm}"
                                            --avb_system_key "${KEYS_DIR}/avb.pem"
                                            --avb_system_algorithm "${avb_algorithm}")
                            ;;
                            vbmeta_chained_v2)
                            AVB_SWITCHES=(--avb_vbmeta_key "${KEYS_DIR}/avb.pem"
                                            --avb_vbmeta_algorithm "${avb_algorithm}"
                                            --avb_system_key "${KEYS_DIR}/avb.pem"
                                            --avb_system_algorithm "${avb_algorithm}"
                                            --avb_vbmeta_system_key "${KEYS_DIR}/avb.pem"
                                            --avb_vbmeta_system_algorithm "${avb_algorithm}")
                            ;;
                        esac

                        croot

                        echo ">> [$(date)] Running sign_target_files_apks for $codename"
                        "sign_target_files_apks" \
                            -o -d "${KEYS_DIR}" \
                            -k ./build/target/product/security/networkstack=${KEYS_DIR}/networkstack "${AVB_SWITCHES[@]}" \
                            ${OUT}/obj/PACKAGING/target_files_intermediates/lineage_$codename-target_files-eng.root.zip \
                            "${OUT}/${TARGET_FILES}"

                        echo ">> [$(date)] Running ota_from_target_files for $codename"
                        "ota_from_target_files" \
                            --block -k "${KEYS_DIR}/releasekey" "${EXTRA_OTA[@]}" "${OUT}/${TARGET_FILES}" \
                            "${OUT}/$codename-ota_update-${BUILD}.zip"

                        echo ">> [$(date)] Running img_from_target_files for $codename"
                        sed -i 's/zipfile\.ZIP_DEFLATED/zipfile\.ZIP_STORED/' "./build/tools/releasetools/img_from_target_files.py"
                        "img_from_target_files" \
                            "${OUT}/${TARGET_FILES}" "${OUT}/$codename-img-${BUILD}.zip"

                        GFI="/root/generate-factory-images-common.sh"
                        curl --fail -s "https://android.googlesource.com/device/common/+/refs/tags/${AOSP_BRANCH}/generate-factory-images-common.sh?format=TEXT" | \
                            base64 --decode > "${GFI}"
                        echo ">> [$(date)] Running generate-factory-images for $codename"
                        cd "${OUT}" || exit
                        sed -i 's/tar zcvf/tar cvf/' "${GFI}"
                        sed -i 's/factory\.tgz/factory\.tar/' "${GFI}"
                        sed -i 's/zip -r/tar cvf/' "${GFI}"
                        sed -i 's/factory\.zip/factory\.tar/' "${GFI}"
                        sed -i '/^mv / d' "${GFI}"
                        source "${GFI}"
                        mv "$codename-${VERSION}-factory.tar" "$codename-factory-${BUILD}.tar"
                        rm -f "$codename-factory-${BUILD}.tar.xz"

                        echo ">> [$(date)] Running compress of factory image with multi-threaded xz for $codename"
                        time xz -v -T 0 -9 -z "$codename-factory-${BUILD}.tar"

                        if [ "$ZIP_SUBDIR" = true ]; then
                            zipsubdir=$codename
                        else
                            zipsubdir=
                        fi
                        echo ">> [$(date)] Moving signed artifacts for $codename to '$ZIP_DIR/$zipsubdir'"
                        for build in $codename-*-${BUILD}.*; do
                            if [ -f "$build" ]; then
                                sha256sum "$build" > "$ZIP_DIR/$zipsubdir/$build.sha256sum"
                                cp -v system/build.prop "$ZIP_DIR/$zipsubdir/$build.prop"
                            fi
                        done
                        find . -maxdepth 1 -name "$codename-*-${BUILD}.*" -type f -exec mv {} "$ZIP_DIR/$zipsubdir/" \;
                        
                        echo ">> [$(date)] Removing unsigned artifacts for $codename from '$ZIP_DIR/$zipsubdir'"
                        find "$ZIP_DIR/$zipsubdir/" -maxdepth 1 -name "lineage*$codename.zip*" -type f -exec rm -f {} \;
                        find "$ZIP_DIR/$zipsubdir/" -maxdepth 1 -name "lineage*$codename-recovery.img" -type f -exec rm -f {} \;

                        echo ">> [$(date)] Removing unneeded artifacts for $codename from '$ZIP_DIR/$zipsubdir'"
                        find "$ZIP_DIR/$zipsubdir/" -maxdepth 1 -name "$codename-img-${BUILD}.*" -type f -exec rm -f {} \;
                        find "$ZIP_DIR/$zipsubdir/" -maxdepth 1 -name "$codename-target_files-${BUILD}.*" -type f -exec rm -f {} \;
                        find "$ZIP_DIR/$zipsubdir/" -maxdepth 1 -name "$codename-factory-*.prop" -type f -exec rm {} \;

                        if [ "$MAGISK" = true ]; then
                            # A lot of this is just what happens in
                            # https://github.com/topjohnwu/Magisk/blob/master/scripts/flash_script.sh
                            # and
                            # https://github.com/topjohnwu/Magisk/blob/master/scripts/boot_patch.sh
                            croot
                            cd /root

                            curl -s https://api.github.com/repos/topjohnwu/Magisk/releases | grep "Magisk-v.*.apk" | grep https | head -n 1 | cut -d : -f 2,3 | tr -d "\"" | wget -i -

                            MAGISK_ZIP=$(ls Magisk-v*.apk)
                            MAGISK_DIR="${MAGISK_ZIP%.*}"
                            MAGISK_VER="${MAGISK_DIR##*v}"

                            unzip "${MAGISK_ZIP}" -d "${MAGISK_DIR}"
                            cd -
                            
                            cd /root/${MAGISK_DIR}/lib/x86
                                for file in lib*.so; do mv "$file" "${file:3:${#file}-6}"; done
                                chmod +x magisk*
                            cd -
                            
                            cd /root/${MAGISK_DIR}/lib/armeabi-v7a
                                for file in lib*.so; do mv "$file" "${file:3:${#file}-6}"; done
                                rm busybox
                                chmod +x magisk*
                                ../x86/magiskboot compress=xz magisk32 magisk32.xz
                                ../x86/magiskboot compress=xz magisk64 magisk64.xz
                            cd -

                            mkdir -pv ${OUT}/obj/PACKAGING/target_files_intermediates/lineage_$codename-target_files-eng.root/BOOT/RAMDISK/.backup
                            mkdir -pv ${OUT}/obj/PACKAGING/target_files_intermediates/lineage_$codename-target_files-eng.root/BOOT/RAMDISK/overlay.d/sbin
                            cp -anv ${OUT}/obj/PACKAGING/target_files_intermediates/lineage_$codename-target_files-eng.root/BOOT/RAMDISK/{init,.backup/init}
                            rm -fv ${OUT}/obj/PACKAGING/target_files_intermediates/lineage_$codename-target_files-eng.root/BOOT/RAMDISK/init

                            cp -v /root/$MAGISK_DIR/lib/armeabi-v7a/magiskinit ${OUT}/obj/PACKAGING/target_files_intermediates/lineage_$codename-target_files-eng.root/BOOT/RAMDISK/init
                            cp -v /root/$MAGISK_DIR/lib/armeabi-v7a/magisk32.xz ${OUT}/obj/PACKAGING/target_files_intermediates/lineage_$codename-target_files-eng.root/BOOT/RAMDISK/overlay.d/sbin/magisk32.xz
                            cp -v /root/$MAGISK_DIR/lib/armeabi-v7a/magisk64.xz ${OUT}/obj/PACKAGING/target_files_intermediates/lineage_$codename-target_files-eng.root/BOOT/RAMDISK/overlay.d/sbin/magisk64.xz

                            cat > ${OUT}/obj/PACKAGING/target_files_intermediates/lineage_$codename-target_files-eng.root/BOOT/RAMDISK/.backup/.magisk <<-EOF
							KEEPFORCEENCRYPT=true
							KEEPVERITY=true
							RECOVERYMODE=false
							EOF

                            cat <<EOF | sed -i '/^ 0 0 755 selabel=u:object_r:rootfs:s0 capabilities=0x0$/ r /dev/stdin' out/target/product/$codename/obj/PACKAGING/target_files_intermediates/lineage_$codename-target_files-eng.root/META/boot_filesystem_config.txt
.backup 0 0 000 selabel=u:object_r:rootfs:s0 capabilities=0x0
.backup/.magisk 0 0 000 selabel=u:object_r:rootfs:s0 capabilities=0x0
.backup/init 0 2000 750 selabel=u:object_r:init_exec:s0 capabilities=0x0
EOF
                            cat <<EOF | sed -i '/^oem 0 0 755 selabel=u:object_r:oemfs:s0 capabilities=0x0$/ r /dev/stdin' out/target/product/$codename/obj/PACKAGING/target_files_intermediates/lineage_$codename-target_files-eng.root/META/boot_filesystem_config.txt
overlay.d 0 0 750 selabel=u:object_r:rootfs:s0 capabilities=0x0
overlay.d/sbin 0 0 750 selabel=u:object_r:rootfs:s0 capabilities=0x0
overlay.d/sbin/magisk32 0 0 644 selabel=u:object_r:rootfs:s0 capabilities=0x0
overlay.d/sbin/magisk64 0 0 644 selabel=u:object_r:rootfs:s0 capabilities=0x0
EOF

                            case "$codename" in
                            walleye)
                                # Retrieve extract-dtb script that will allow us to separate already compiled binary and the concatenated DTB files
                                git clone https://github.com/PabloCastellano/extract-dtb.git /root/extract-dtb

                                # Separate kernel and separate DTB files
                                cd out/target/product/$codename/obj/PACKAGING/target_files_intermediates/lineage_$codename-target_files-eng.root/BOOT/

                                python3 /root/extract-dtb/extract_dtb/extract_dtb.py kernel

                                # Decompress the kernel
                                lz4 -d dtb/00_kernel dtb/uncompressed_kernel

                                # Hexpatch the kernel
                                /root/$MAGISK_DIR/lib/x86/magiskboot hexpatch dtb/uncompressed_kernel \
                                    49010054011440B93FA00F71E9000054010840B93FA00F7189000054001840B91FA00F7188010054 \
                                    A1020054011440B93FA00F7140020054010840B93FA00F71E0010054001840B91FA00F7181010054
                                /root/$MAGISK_DIR/lib/x86/magiskboot hexpatch dtb/uncompressed_kernel \
                                    821B8012 E2FF8F12
                                /root/$MAGISK_DIR/lib/x86/magiskboot hexpatch dtb/uncompressed_kernel \
                                    736B69705F696E697472616D667300 \
                                    77616E745F696E697472616D667300

                                # Recompress kernel
                                lz4 -f -9 dtb/uncompressed_kernel dtb/00_kernel
                                rm dtb/uncompressed_kernel
                                # Concatenate back kernel and DTB files
                                rm kernel
                                for file in dtb/*
                                do
                                    cat $file >> kernel
                                done
                                rm -rf dtb

                                cd -
                                ;;
                            esac

                            # Remove target files zip
                            rm -f ${OUT}/obj/PACKAGING/target_files_intermediates/lineage_$codename-target_files-eng.root.zip

                            # Rezip target files
                            cd ${OUT}/obj/PACKAGING/target_files_intermediates/lineage_$codename-target_files-eng.root
                            zip --symlinks -r ../lineage_$codename-target_files-eng.root.zip *
                            cd -
                            
                            find "$ZIP_DIR/$zipsubdir/" -maxdepth 1 -name "$codename-ota_update-${BUILD}.*" -type f -exec rm -f {} \;

                            BUILD="${BRANCH_NAME}-$(date +%Y%m%d)-${RELEASE_TYPE}-magisk"                
                            TARGET_FILES="$codename-target_files-${BUILD}.zip"

                            echo ">> [$(date)] Running sign_target_files_apks for $codename"
                            "sign_target_files_apks" \
                                -o -d "${KEYS_DIR}" \
                                -k ./build/target/product/security/networkstack=${KEYS_DIR}/networkstack "${AVB_SWITCHES[@]}" \
                                ${OUT}/obj/PACKAGING/target_files_intermediates/lineage_$codename-target_files-eng.root.zip \
                                "${OUT}/${TARGET_FILES}"

                            echo ">> [$(date)] Running ota_from_target_files for $codename"
                            "ota_from_target_files" \
                                --block -k "${KEYS_DIR}/releasekey" "${EXTRA_OTA[@]}" "${OUT}/${TARGET_FILES}" \
                                "${OUT}/$codename-ota_update-${BUILD}.zip"

                            echo ">> [$(date)] Moving signed artifacts for $codename to '$ZIP_DIR/$zipsubdir'"
                            sha256sum "${OUT}/$codename-ota_update-${BUILD}.zip" > "$ZIP_DIR/$zipsubdir/$codename-ota_update-${BUILD}.zip.sha256sum"
                            cp -v ${OUT}/system/build.prop "$ZIP_DIR/$zipsubdir/$codename-ota_update-${BUILD}.zip.prop"
                            mv "${OUT}/$codename-ota_update-${BUILD}.zip" "$ZIP_DIR/$zipsubdir/"

                            echo ">> [$(date)] Removing unneeded artifacts for $codename from '$ZIP_DIR/$zipsubdir'"
                            find "$ZIP_DIR/$zipsubdir/" -maxdepth 1 -name "$codename-target_files-${BUILD}.*" -type f -exec rm -f {} \;
                        fi
                    else
                        echo ">> [$(date)] Failed brillo_update_payload build for $codename"
                    fi
                else
                    echo ">> [$(date)] Failed otatools build for $codename"
                fi
            else
                echo ">> [$(date)] Failed target-files-package build for $codename"
            fi
        else
            echo ">> [$(date)] Failed breakfast build for $codename"
        fi
    fi
fi
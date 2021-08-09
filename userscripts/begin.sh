#!/usr/bin/env bash
#
# docker-lineage-cicd begin.sh script
# Runs after
#   cd "$SRC_DIR"
# for no particular device codename.
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

apt-get update
apt-get -y upgrade

if [ "$SIGN_BUILDS" = true ]; then
  apt-get -y install xxd
fi

rm -rf "$LMANIFEST_DIR"/lineageos4microg-prebuilts.xml
if [ "$MICROG" = true ]; then
  # From https://github.com/lineageos4microg/docker-lineage-cicd
  cat > "$LMANIFEST_DIR"/lineageos4microg-prebuilts.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <project name="lineageos4microg/android_prebuilts_prebuiltapks" path="prebuilts/prebuiltapks" remote="github" revision="master" />
</manifest>
EOF
fi

rm -rf "$LMANIFEST_DIR"/gapps.xml
if [ "$GAPPS" = true ]; then
#  # From https://gitlab.com/MindTheGapps/vendor_gapps
#   cat > "$LMANIFEST_DIR"/gapps.xml <<'EOF'
# <?xml version="1.0" encoding="UTF-8"?>
# <manifest>
#   <remote name="mindthegapps" fetch="https://gitlab.com/MindTheGapps/"  />
#   <project path="vendor/mindthegapps" name="vendor_gapps" revision="rho" remote="mindthegapps" />
# </manifest>
# EOF

  curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | bash
  apt-get -y install git-lfs
  git lfs install

  # From https://github.com/opengapps/aosp_build
  cat > "$LMANIFEST_DIR"/gapps.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <remote name="opengapps" fetch="https://github.com/opengapps/"  />
  <remote name="opengapps-gitlab" fetch="https://gitlab.opengapps.org/opengapps/"  />

  <project path="vendor/opengapps/build" name="aosp_build" revision="master" remote="opengapps" />

  <project path="vendor/opengapps/sources/all" name="all" clone-depth="1" revision="master" remote="opengapps-gitlab" />

  <!-- arm64 depends on arm -->
  <project path="vendor/opengapps/sources/arm" name="arm" clone-depth="1" revision="master" remote="opengapps-gitlab" />
  <project path="vendor/opengapps/sources/arm64" name="arm64" clone-depth="1" revision="master" remote="opengapps-gitlab" />

  <project path="vendor/opengapps/sources/x86" name="x86" clone-depth="1" revision="master" remote="opengapps-gitlab" />
  <project path="vendor/opengapps/sources/x86_64" name="x86_64" clone-depth="1" revision="master" remote="opengapps-gitlab" />
</manifest>
EOF
fi

if [ "$MAGISK" = true ]; then
  # From https://github.com/CaseyBakey/chaosp/blob/10-testing/patches/0004_allow_dot_files_in_ramdisk.patch
  cat > /root/magisk_mkbootfs.patch <<'EOF'
diff --git a/system/core/cpio/mkbootfs.c b/system/core/cpio/mkbootfs.c
index e52762e9b..1a4259d9c 100644
--- a/system/core/cpio/mkbootfs.c
+++ b/system/core/cpio/mkbootfs.c
@@ -179,9 +179,12 @@ static void _archive_dir(char *in, char *out, int ilen, int olen)
     }
 
     while((de = readdir(d)) != 0){
+        if(strcmp(de->d_name, ".backup") == 0 || strcmp(de->d_name, ".magisk") == 0)
+            goto let_magisk;
             /* xxx: feature? maybe some dotfiles are okay */
         if(de->d_name[0] == '.') continue;
 
+let_magisk:
             /* xxx: hack. use a real exclude list */
         if(!strcmp(de->d_name, "root")) continue;
 
EOF
fi
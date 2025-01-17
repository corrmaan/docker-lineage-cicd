#!/usr/bin/env bash
#
# docker-lineage-cicd before.sh script
# Runs after
#   source build/envsetup.sh
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

echo ">> [$(date)] Syncing opengapps repository"
for i in {1..10}; do
    repo forall -c git lfs pull && break
done

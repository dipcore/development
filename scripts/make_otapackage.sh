#!/bin/bash

SOURCE_FILE=build/envsetup.sh
source $SOURCE_FILE
if [ -z "$TARGET_PRODUCT" ]; then
    lunch
fi

read -p "Please Input Build System Version(BUILD_NUMBER)? (example:2.4.1.a4) :" BUILD_NUMBER_USER
if [ -z "$BUILD_NUMBER_USER" ]; then
    BUILD_NUMBER_USER=$(get_build_var BUILD_NUMBER)
fi

printf "Build System Version : $BUILD_NUMBER_USER\n";

TARGET_DEVICE=$(get_build_var TARGET_DEVICE)
BOARDCONFIG=$ANDROID_BUILD_TOP/device/mstar/$TARGET_DEVICE/BoardConfig.mk
BOARDCONFIG_BK=$ANDROID_BUILD_TOP/device/mstar/$TARGET_DEVICE/BoardConfig.mk-bk
BOARDCONFIGCOMMON=$ANDROID_BUILD_TOP/device/mstar/$TARGET_DEVICE/BoardConfigCommon.mk
BOARDCONFIGCOMMON_BK=$ANDROID_BUILD_TOP/device/mstar/$TARGET_DEVICE/BoardConfigCommon.mk-bk

#backup the files
mv $BOARDCONFIG $BOARDCONFIG_BK
mv $BOARDCONFIGCOMMON $BOARDCONFIGCOMMON_BK


echo "Please Select The Type Of Make Ota Package"
echo "1) make full otapackage,include all partition"
echo "2) make full otapackage,only include os"
echo "3) make full otapackage,only include tvconfig partition"
echo "4) make incremental otapackage,include all partition"
echo "5) make incremental otapackage,only include os"
echo "6) make incremental otapackage,only include tvconfig partition"
temp=1;
read -p "Please Select The Type Of Make Ota Package:" temp

TVCONCIG_ROOT_FILE_LIST=tvconfig
TVCONCIG_ROOT_FILE_LIST_DEL=tvconfig_delete

if [ "$temp" == "1" ] || [ "$temp" == "3" ]; then
    #OTA_PACKAGE_WITH_TVCONFIG_TYPE
    # 0: OTA package not include tvconfig.img
    # 1: build Full OTA package (include tvconfig.img)
    # 2: build Incremental OTA package (update files/directory of tvconfig)
    OTA_PACKAGE_WITH_TVCONFIG_TYPE=1
elif [ "$temp" == "2" ] || [ "$temp" == "5" ]; then
    OTA_PACKAGE_WITH_TVCONFIG_TYPE=0
elif [ "$temp" == "4" ] || [ "$temp" == "6" ]; then
    OTA_PACKAGE_WITH_TVCONFIG_TYPE=2
fi

if [ "$temp" == "3" ] || [ "$temp" == "6" ]; then
    #OTA_PACKAGE_WITH_TVDATA_TVSERVICE_TYPE
    # 0:OTA package not include tvdatabase.img tvservice.img
    # 1:OTA package  include tvdatabase.img tvservice.img
    OTA_PACKAGE_WITH_TVDATA_TVSERVICE_TYPE=0
else
    OTA_PACKAGE_WITH_TVDATA_TVSERVICE_TYPE=1
fi

#amend BoardConfig.mk
sed \
    -e "s/OTA_WITH_TVCONFIG .*/OTA_WITH_TVCONFIG := $OTA_PACKAGE_WITH_TVCONFIG_TYPE/" \
    -e "s/OTA_WITH_TV .*/OTA_WITH_TV := $OTA_PACKAGE_WITH_TVDATA_TVSERVICE_TYPE/" \
    $BOARDCONFIGCOMMON_BK >$BOARDCONFIGCOMMON
#amend BoardConfigCommon.mk
sed \
    -e "s/BUILD_NUMBER .*/BUILD_NUMBER := $BUILD_NUMBER_USER/" \
    -e "s/OTA_TVCONFIG_IMAGE_LIST .*/OTA_TVCONFIG_IMAGE_LIST := $TVCONCIG_ROOT_FILE_LIST/" \
    -e "s/OTA_TVCONFIG_DELETE_LIST .*/OTA_TVCONFIG_DELETE_LIST := $TVCONCIG_ROOT_FILE_LIST_DEL/" \
    $BOARDCONFIG_BK > $BOARDCONFIG

if [ "$temp" == "1" ] || [ "$temp" == "2" ] || [ "$temp" == "3" ]; then
    MAKE_OTA_CMD_TYPE=0
else
    MAKE_OTA_CMD_TYPE=1
fi

# make Android otapackage
source $SOURCE_FILE
lunch $TARGET_PRODUCT-$TARGET_BUILD_VARIANT
if [ "$MAKE_OTA_CMD_TYPE" == "0" ]; then
    make otapackage
else
    make incrementalotapackage
fi

mv $BOARDCONFIG_BK $BOARDCONFIG
mv $BOARDCONFIGCOMMON_BK $BOARDCONFIGCOMMON
#!/bin/bash

ADDON_NAME="DreamFisher"

echo "WOW_DIR     : $WOW_DIR"
echo "WOW_ACCOUNT : $WOW_ACCOUNT"
echo "ADDON_NAME  : $ADDON_NAME"

rm -f $WOW_DIR/_retail_/WTF/Account/$WOW_ACCOUNT/SavedVariables/$ADDON_NAME.lua

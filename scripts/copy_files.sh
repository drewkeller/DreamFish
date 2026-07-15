#!/bin/bash

ADDON_NAME="DreamFish"

if [[ $WOW_DIR == "" ]]; then
  echo "Please set the WOW_DIR environment variable."
  exit 1
fi

if [[ -d $WOW_DIR ]]; then
  ADDONS_DIR="$WOW_DIR/_retail_/Interface/AddOns"
  ADDON_DIR="$ADDONS_DIR/$ADDON_NAME"
else
  echo "The directory specified in WOW_DIR does not exist."
  exit 1
fi

# Copy the main addon files to the addon directory
cp -f DreamFish.lua DreamFish.toc Bindings.xml  \
  "$ADDON_DIR"

# Copy the addon subdirectories to the addon directory
cp -rf audio buff core fishing ui Libs "$ADDON_DIR"

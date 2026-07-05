#!/bin/bash

for test_name in audio_ducking autoloot bag_space \
    buff_timing casting_modes focus_fade toy_selector treasure_alert ui_info_message
do
    lua "$PWD/tests/${test_name}_test.lua"
done

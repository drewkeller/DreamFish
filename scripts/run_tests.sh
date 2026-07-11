#!/bin/bash

for test_file in ./tests/*_test.lua; do
    lua "$PWD/$test_file"
done

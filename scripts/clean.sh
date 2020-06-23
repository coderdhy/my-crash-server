#! /bin/bash

echo "this is clean.sh"

find ./ -type f -name "*.pyc" -exec rm {} \;
rm -rf ./google-breakpad/ ./build/ ./breakpad/ breakpad.tar.gz
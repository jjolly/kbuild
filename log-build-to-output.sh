#!/bin/bash

set -e

if [ ! -d "/output" ] || [ ! -w "/output" ]; then
  echo "Error: /output directory is not writable"
  exit 1
fi

BUILD_LOG_FILENAME="kernel-build-log.txt"
if [ "x$ARCH" != "x" ]; then
  BUILD_LOG_FILENAME="kernel-build-log-${ARCH}.txt"
fi

./build-kernel.sh 2>&1 | tee -a "/output/${BUILD_LOG_FILENAME}"

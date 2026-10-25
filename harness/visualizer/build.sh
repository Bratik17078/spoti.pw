#!/bin/sh
set -eu
cd "$(dirname "$0")"
mkdir -p build
clang -x c -std=c11 -O2 -Wall -Wextra -Werror -I../../tweak/Sources \
    main.c ../../tweak/Sources/Shared/AudioVisualization/SGSpectrum.m -lm -o build/visualizer
./build/visualizer

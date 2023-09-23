#!/bin/sh
cd $(dirname $(realpath $0))
mkdir -p build
g++ main.cpp lib/*.cpp -lcurl -o build/main
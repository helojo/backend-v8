#!/bin/bash

VERSION=$1
NEW_WRAP=$2

[ -z "$GITHUB_WORKSPACE" ] && GITHUB_WORKSPACE="$( cd "$( dirname "$0" )"/.. && pwd )"

ver_major=$(echo "$VERSION" | cut -d. -f1)
ver_minor=$(echo "$VERSION" | cut -d. -f2)
if [[ $ver_major -gt 9 ]] || ([[ $ver_major -eq 9 ]] && [[ $ver_minor -ge 0 ]]); then
    VERSION_GE_9_0=true
else
    VERSION_GE_9_0=false
fi

if [ "$VERSION_GE_9_0" = true ]; then
    sudo apt-get install -y \
        pkg-config \
        git \
        subversion \
        curl \
        wget \
        build-essential \
        python3 \
        ninja-build \
        xz-utils \
        zip
        
    pip install virtualenv
else
    sudo apt-get install -y \
        pkg-config \
        git \
        subversion \
        curl \
        wget \
        build-essential \
        python \
        xz-utils \
        zip
fi

sudo apt-get update
sudo apt-get install -y libatomic1-i386-cross
sudo rm -rf /var/lib/apt/lists/*
#export LD_LIBRARY_PATH=”LD_LIBRARY_PATH:/usr/i686-linux-gnu/lib/”
echo "/usr/i686-linux-gnu/lib" > i686.conf
sudo mv i686.conf /etc/ld.so.conf.d/
sudo ldconfig

cd ~
echo "=====[ Getting Depot Tools ]====="	
git clone -q https://chromium.googlesource.com/chromium/tools/depot_tools.git
if [ "$VERSION_GE_9_0" = false ]; then
    cd depot_tools
    git reset --hard 8d16d4a
    cd ..
fi
export DEPOT_TOOLS_UPDATE=0
export PATH=$(pwd)/depot_tools:$PATH
gclient
~/depot_tools/ensure_bootstrap


mkdir v8
cd v8

echo "=====[ Fetching V8 ]====="
fetch v8
echo "target_os = ['android']" >> .gclient
cd ~/v8/v8
if [ "$VERSION_GE_9_0" = false ]; then
./build/install-build-deps-android.sh
fi
git checkout refs/tags/$VERSION

echo "=====[ fix DEPS ]===="
node -e "const fs = require('fs'); fs.writeFileSync('./DEPS', fs.readFileSync('./DEPS', 'utf-8').replace(\"Var('chromium_url') + '/external/github.com/kennethreitz/requests.git'\", \"'https://github.com/kennethreitz/requests'\"));"

gclient sync


# echo "=====[ Patching V8 ]====="
# git apply --cached $GITHUB_WORKSPACE/patches/builtins-puerts.patches
# git checkout -- .

if [ "$VERSION" == "11.6.189" ]; then 
  node $GITHUB_WORKSPACE/node-script/do-gitpatch.js -p $GITHUB_WORKSPACE/patches/android_enable_16kb_v11.6.189.patch
fi

CXX_SETTING="use_custom_libcxx=false"

if [ "$NEW_WRAP" == "with_new_wrap" ]; then 
  echo "=====[ wrap new delete ]====="
  CXX_SETTING="use_custom_libcxx=true"
fi

# node $GITHUB_WORKSPACE/node-script/patchs.js . $VERSION $NEW_WRAP

# 公共配置
COMMON_ARGS="
    target_os=\"android\"
    is_debug=false
    v8_enable_i18n_support=false
    v8_use_external_startup_data=false
    is_component_build=false
    v8_monolithic=true
    v8_static_library=true
    strip_debug_info=true
    symbol_level=0
    $CXX_SETTING
    use_custom_libcxx_for_host=true
    v8_enable_sandbox=false
    android32_ndk_api_level=21
    android64_ndk_api_level=21
    v8_enable_test_features=false
    v8_enable_extras=false
    use_lld=true
    thin_lto_enable=true
"

echo "=====[ Building V8 arm64 ]====="

gn gen out.gn/arm64.release --args="$COMMON_ARGS
    target_cpu=\"arm64\"
    v8_target_cpu=\"arm64\"
    v8_enable_webassembly=false"

ninja -C out.gn/arm64.release -t clean
ninja -v -C out.gn/arm64.release v8_monolith

mkdir -p output/v8/Lib/Android/arm64-v8a
if [ "$NEW_WRAP" == "with_new_wrap" ]; then
  export PATH="$(pwd)/third_party/llvm-build/Release+Asserts/bin:$PATH"
  bash $GITHUB_WORKSPACE/rename_symbols_posix.sh arm64 output/v8/Lib/Android/arm64-v8a/
fi
cp out.gn/arm64.release/obj/libv8_monolith.a output/v8/Lib/Android/arm64-v8a/
mkdir -p output/v8/Bin/Android/arm64-v8a
find out.gn/ -type f -name v8cc -exec cp "{}" output/v8/Bin/Android/arm64-v8a \;
find out.gn/ -type f -name mksnapshot -exec cp "{}" output/v8/Bin/Android/arm64-v8a \;

echo "=====[ Building V8 arm ]====="
gn gen out.gn/arm.release --args="$COMMON_ARGS
    target_cpu=\"arm\"
    v8_target_cpu=\"arm\"
    v8_enable_webassembly=false"
ninja -C out.gn/arm.release -t clean
ninja -v -C out.gn/arm.release v8_monolith

mkdir -p output/v8/Lib/Android/armeabi-v7a
if [ "$NEW_WRAP" == "with_new_wrap" ]; then 
  export PATH="$(pwd)/third_party/llvm-build/Release+Asserts/bin:$PATH"
  bash $GITHUB_WORKSPACE/rename_symbols_posix.sh arm output/v8/Lib/Android/armeabi-v7a/
fi

cp out.gn/arm.release/obj/libv8_monolith.a output/v8/Lib/Android/armeabi-v7a/
mkdir -p output/v8/Bin/Android/armeabi-v7a
find out.gn/ -type f -name v8cc -exec cp "{}" output/v8/Bin/Android/armeabi-v7a \;
find out.gn/ -type f -name mksnapshot -exec cp "{}" output/v8/Bin/Android/armeabi-v7a \;

echo "=====[ Building V8 x64 ]====="
gn gen out.gn/x64.release --args="$COMMON_ARGS
    target_cpu=\"x64\"
    v8_target_cpu=\"x64\"
    v8_enable_webassembly=false"
ninja -C out.gn/x64.release -t clean
ninja -v -C out.gn/x64.release v8_monolith

mkdir -p output/v8/Lib/Android/x86_64
if [ "$NEW_WRAP" == "with_new_wrap" ]; then 
  export PATH="$(pwd)/third_party/llvm-build/Release+Asserts/bin:$PATH"
  bash $GITHUB_WORKSPACE/rename_symbols_posix.sh x64 output/v8/Lib/Android/x86_64/
fi
cp out.gn/x64.release/obj/libv8_monolith.a output/v8/Lib/Android/x86_64/
mkdir -p output/v8/Bin/Android/x64
find out.gn/ -type f -name v8cc -exec cp "{}" output/v8/Bin/Android/x86_64 \;
find out.gn/ -type f -name mksnapshot -exec cp "{}" output/v8/Bin/Android/x86_64 \;

echo "=====[ Building V8 x86 ]====="
if [ "$VERSION" == "11.6.189"  ]; then 
    gn gen out.gn/x86.release --args="$COMMON_ARGS
    target_cpu=\"x86\"
    v8_target_cpu=\"x86\""
else
    gn gen out.gn/x86.release --args="$COMMON_ARGS
    target_cpu=\"x86\"
    v8_target_cpu=\"x86\"
    v8_enable_webassembly=false"
fi
ninja -C out.gn/x86.release -t clean
ninja -v -C out.gn/x86.release v8_monolith

mkdir -p output/v8/Lib/Android/x86
if [ "$NEW_WRAP" == "with_new_wrap" ]; then 
  export PATH="$(pwd)/third_party/llvm-build/Release+Asserts/bin:$PATH"
  bash $GITHUB_WORKSPACE/rename_symbols_posix.sh x86 output/v8/Lib/Android/x86/
fi
cp out.gn/x86.release/obj/libv8_monolith.a output/v8/Lib/Android/x86/
mkdir -p output/v8/Bin/Android/x86
find out.gn/ -type f -name v8cc -exec cp "{}" output/v8/Bin/Android/x86 \;
find out.gn/ -type f -name mksnapshot -exec cp "{}" output/v8/Bin/Android/x86 \;


#!/usr/bin/env bash

manifestJsonFile="/tmp/workdir/generated_build_manifest.json"
manifestJsonVersionsFile="/tmp/workdir/generated_build_manifest_versions.json"

extract_tarball() {
    local tarball_name=$1
    # grab the extension of the tarball
    local extension="${tarball_name##*.}"
    # tar extraction args: -z, -j, -J, --lzma  Compress archive with gzip/bzip2/xz/lzma
    if [ "$extension" == "gz" ]; then
        tar -zx --strip-components=1 -f ${tarball_name}
    elif [ "$extension" == "bz2" ]; then
        tar -jx --strip-components=1 -f ${tarball_name}
    elif [ "$extension" == "zx" ]; then
        tar -Jx --strip-components=1 -f ${tarball_name}
    else
        echo "Error while extract_tarball, got an unknown extension: $extension"
    fi
}

# read_data_from_manifest() {
#     local lib_name=$1
#     local data=$(jq -r '.[] | select(.library_name == "'$lib_name'")' $manifestJsonFile)
#     local build_dir=$(echo "$data" | jq -r '.build_dir')
#     local tarball_name=$(echo "$data" | jq -r '.tarball_name')
#     echo "$build_dir $tarball_name"
# }

build_libopencore-amr() {
    ./configure --prefix="${PREFIX}" --enable-shared && \
    make && \
    make install
}

build_libx264() {
    ./configure --prefix="${PREFIX}" --enable-shared --enable-pic --disable-cli && \
    make && \
    make install
}

build_libx265() {
    cd build/linux && \
    sed -i "/-DEXTRA_LIB/ s/$/ -DCMAKE_INSTALL_PREFIX=\${PREFIX}/" multilib.sh && \
    sed -i "/^cmake/ s/$/ -DENABLE_CLI=OFF/" multilib.sh && \
    ./multilib.sh && \
    make -C 8bit install && \
    rm -rf ${DIR}
    cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="${PREFIX}" -DENABLE_SHARED=on -DENABLE_PIC=on . && \
    make && \
    make install
}

build_libogg() {
    ./configure --prefix="${PREFIX}" --enable-shared && \
    make && \
    make install
}

build_libopus() {
    ./configure --prefix="${PREFIX}" --enable-shared && \
    make && \
    make install
}

build_libvorbis() {
    ./configure --prefix="${PREFIX}" --with-ogg="${PREFIX}" --enable-shared && \
    make && \
    make install
}

build_libvpx() {
    ./configure --prefix="${PREFIX}" --enable-vp8 --enable-vp9 --enable-vp9-highbitdepth --enable-pic --enable-shared \
    --disable-debug --disable-examples --disable-docs --disable-install-bins  && \
    make && \
    make install
}

build_libwebp() {
    ./configure --prefix="${PREFIX}" --enable-shared && \
    make && \
    make install
}

build_libmp3lame() {
    ./configure --prefix="${PREFIX}" --bindir="${PREFIX}/bin" --enable-shared --enable-nasm --disable-frontend && \
    make && \
    make install
}

build_libxvid() {
    ./configure --prefix="${PREFIX}" --bindir="${PREFIX}/bin" && \
    make && \
    make install
}

build_libfdk-aac() {
    autoreconf -fiv && \
    ./configure --prefix="${PREFIX}" --enable-shared --datadir="${DIR}" && \
    make && \
    make install
}

build_openjpeg() {
    cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${PREFIX}" . && \
    make && \
    make install
}

build_freetype() {
    ./configure --prefix="${PREFIX}" --disable-static --enable-shared && \
    make && \
    make install
}

build_libvidstab() {
    cmake -DCMAKE_INSTALL_PREFIX="${PREFIX}" . && \
    make && \
    make install
}

build_fribidi() {
    sed -i 's/^SUBDIRS =.*/SUBDIRS=gen.tab charset lib bin/' Makefile.am && \
    ./bootstrap --no-config --auto && \
    ./configure --prefix="${PREFIX}" --disable-static --enable-shared && \
    make -j1 && \
    make install
}

build_fontconfig() {
    ./configure --prefix="${PREFIX}" --disable-static --enable-shared && \
    make && \
    make install
}

build_libass() {
    ./autogen.sh && \
    ./configure --prefix="${PREFIX}" --disable-static --enable-shared && \
    make && \
    make install
}

build_kvazaar() {
    ./autogen.sh && \
    ./configure --prefix="${PREFIX}" --disable-static --enable-shared && \
    make && \
    make install
}

# aom is a git clone ( to get source, so not in the loop using the callback function)
build_aom(){
    local dir = "/tmp/aom"
    local aom_version=$(jq -r '.["aom"]' $manifestJsonVersionsFile)  # Access value with key "aom"
    echo "Building aom-${aom_version}"
    git clone --branch ${aom_version} --depth 1 https://aomedia.googlesource.com/aom ${dir} ; \
    cd ${dir} ; \
    mkdir -p ./aom_build ; \
    cd ./aom_build ; \
    cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="${PREFIX}" -DBUILD_SHARED_LIBS=1 -DENABLE_NASM=on ..; \
    make && \
    make install
}

build_libsvtav1() {
    cd Build && \
    cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="${PREFIX}"  -DCMAKE_BUILD_TYPE=Release -DBUILD_DEC=OFF -DBUILD_SHARED_LIBS=OFF ..; \
    make && \
    make install
}

build_xorg-macros() {
    dir=${1}
    ./configure --srcdir=${dir} --prefix="${PREFIX}" && \
    make && \
    make install
}

build_xproto() {
    dir=${1}
    # I don't think we need the config.guess anymore
    # cp /usr/share/misc/config.guess . && \
    ./configure --srcdir=${dir} --prefix="${PREFIX}" && \
    make && \
    make install
}

build_libxau() {
    dir=${1}
    ./configure --srcdir=${dir} --prefix="${PREFIX}" && \
    make && \
    make install
}

build_libpthread-stubs() {
    ./configure --prefix="${PREFIX}" && \
    make && \
    make install
}

build_libxml2() {
    ./autogen.sh --prefix="${PREFIX}" --with-ftp=no --with-http=no --with-python=no && \
    make && \
    make install
}

build_libbluray() {
    ## libbluray - Requires libxml, freetype, and fontconfig
    ./configure --prefix="${PREFIX}" --disable-examples --disable-bdjava-jar --disable-static --enable-shared && \
    make && \
    make install
}

build_libzmq() {
    ./autogen.sh && \
    ./configure --prefix="${PREFIX}" && \
    make && \
    make check && \
    make install
}

# another special, code clone situation ( actually currently using the tarball build approach )
build_libpng() {
    local dir = "/tmp/png"
    local libpng_version=$(jq -r '.["libpng"]' $manifestJsonVersionsFile)  # Access value with key "libpng"
    # git clone https://git.code.sf.net/p/libpng/code ${dir} -b v${libpng_version} --depth 1 && \
    ./autogen.sh && \
    ./configure --prefix="${PREFIX}" && \
    make check && \
    make install
}

build_libaribb24() {
    autoreconf -fiv && \
    ./configure CFLAGS="-I${PREFIX}/include -fPIC" --prefix="${PREFIX}" && \
    make && \
    make install
}

build_zimg() {
    ./autogen.sh && \
    ./configure --prefix="${PREFIX}" --enable-shared  && \
    make && \
    make install
}

build_libtheora() {
    # add sym link for sdl-config
    # ln -s /usr/bin/sdl2-config /usr/bin/sdl-config && \
    # currently build does not find sdl-config, and thus no playback support is enabled (probably exacly, the way it was before)
    # Note: consider installing doxygen so that the api documentation is built
    #       right now, I did not, so we can keep everything small.
    # disable examples to advoid the libjpeg sizeof error still in the example code.
    ./configure --prefix="${PREFIX}" --with-ogg="${PREFIX}" --enable-shared --disable-examples && \
    make && \
    make install
}

build_libsrt() {
    # requires libssl-dev
    cmake -DCMAKE_INSTALL_PREFIX="${PREFIX}" . && \
    make && \
    make install
}

build_libvmaf() {
    mkdir ./libvmaf/build && \
    cd ./libvmaf/build && \
    meson setup -Denable_tests=false -Denable_docs=false --buildtype=release --default-library=static .. --prefix "${PREFIX}" && \
    ninja && \
    ninja install
}

build_ffmpeg() {
    # export PKG_CONFIG_PATH=${PKG_CONFIG_PATH}
    ./configure %%FFMPEG_CONFIG_FLAGS%% && \
    make && \
    make install && \
    make tools/zmqsend && cp tools/zmqsend ${PREFIX}/bin/ && \
    make distclean && \
    hash -r && \
    cd tools && \
    make qt-faststart && cp qt-faststart ${PREFIX}/bin/

}


build_support_libraries() {
    local librariesRaw="$(jq -r '.[] | .library_name' $manifestJsonFile)"
    local libs=( $librariesRaw )
    for i in "${!libs[@]}"; do
        lib_name=${libs[$i]}
        # handle the clone source case's ( there are only two )
        if [ "$lib_name" == "libsvtav1" ]; then
            echo "Building 'aom' before we build $lib_name"
            build_aom
        fi
        # currently using the tarball approach for libpng
        # if [ "$lib_name" == "libaribb24" ]; then
        #     echo "Building 'libpng' before we build $lib_name"
        #     build_libpng
        # fi
        local data=$(jq -r '.[] | select(.library_name == "'${lib_name}'")' $manifestJsonFile)
        build_dir=$(echo "$data" | jq -r '.build_dir')
        tarball_name=$(echo "$data" | jq -r '.tarball_name')
        sha256sum=$(echo "$data" | jq -r '.sha256sum')

        echo "Building $lib_name: in [${build_dir}] from [$tarball_name] source"
        cd $build_dir
        extract_tarball $tarball_name
        if [ -n "$sha256sum" ] && [[ "$sha256sum" != "null" ]]; then
            echo "Checking sha256sum for $tarball_name"
            echo $sha256sum | sha256sum --check
        fi
        # make a callback function to build the library
        # if anything fails, we will exit with a non-zero status
        build_${lib_name} ${build_dir}
    done
}

build_support_libraries

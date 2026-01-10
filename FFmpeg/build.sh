rm -rf $PWD/build
./configure \
  --prefix=$PWD/build \
  --disable-shared \
  --enable-static \
  --disable-programs \
  --disable-doc \
  --disable-debug \
  --enable-pic \
  --enable-videotoolbox \
  --enable-swresample \
  --enable-swscale \
  --enable-avformat \
  --enable-avcodec \
  --enable-avutil \
  --disable-gpl \
  --disable-nonfree \
  --cc=clang
make -j$(sysctl -n hw.logicalcpu)
make install

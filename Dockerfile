FROM Fedora-Docker-Base-22_Beta-20150415.x86_64
MAINTAINER Hamish.K.Mackenzie@gmail.com

RUN dnf -y install sudo && dnf clean all

ENV WINE wine
ENV WINEDEBUG -all
ENV WINEPATH_U winepath -u

RUN sudo dnf -y --enablerepo updates-testing update && \
    sudo dnf clean all

RUN sudo dnf -y --enablerepo updates-testing install \
                           wine.x86_64 \
                           wine.i686 \
                           mingw64-webkitgtk3.noarch \
                           mingw64-gtksourceview3.noarch \
                           mingw32-winpthreads \
                           wget \
                           tar \
                           make \
                           p7zip \
                           unzip \
                           cabal-install \
                           git \
                           msitools && \
    sudo dnf clean all

# Install pkg-config for using in Wine and Windows
RUN wget http://pkgconfig.freedesktop.org/releases/pkg-config-0.28.tar.gz && \
    tar -xzf pkg-config-0.28.tar.gz && \
    cd pkg-config-0.28 && \
    mingw64-configure && \
    make && \
    sudo make install && \
    make clean && \
    rm -rf pkg-config-0.28.tar.gz pkg-config-0.28

# Fix the broken pkg-config files (it is important to use ${prefix} or they will not work
# when used on Windows or in Wine:
RUN grep -lZ '^Cflags:.*-I/usr/x86_64-w64-mingw32/sys-root/mingw' /usr/x86_64-w64-mingw32/sys-root/mingw/lib/pkgconfig/*.pc | xargs -0 -l sudo sed -i.bak -e '/^Cflags:/ s|-I/usr/x86_64-w64-mingw32/sys-root/mingw|-I${prefix}|g'

# Initialize Wine and set use `wine regedit` to add a `Path` to `HKEY_CURRENT_USER\Environment`:
ADD win32/Environment*.reg leksah/win32/
RUN wineboot && wine cmd /C echo "Wine OK" && wineserver -w && \
    wineserver -p1 && wine regedit leksah/win32/Environment.reg && wineserver -w && \
    ( export WINEPREFIX=~/.wine32 && export WINEARCH=win32 && \
      wineboot && wine cmd /C echo "Wine 32 OK" && wineserver -w && \
      wineserver -p1 && wine regedit leksah/win32/Environment32.reg && wineserver -w \
    )

# Install Windows version of GHC (but not the old mingw that comes with it:
RUN cd ~/.wine/drive_c && \
    wget https://www.haskell.org/ghc/dist/7.10.1/ghc-7.10.1-x86_64-unknown-mingw32.tar.xz && \
    tar -xJf ghc-7.10.1-x86_64-unknown-mingw32.tar.xz && \
    rm -rf ghc-7.10.1/mingw && \
    rm ghc-7.10.1-x86_64-unknown-mingw32.tar.xz

# Replace the MinGW that comes with GHC:
RUN cd ~/.wine/drive_c/ghc-7.10.1 && \
    wget http://sourceforge.net/projects/mingw-w64/files/Toolchains%20targetting%20Win64/Personal%20Builds/mingw-builds/4.9.2/threads-posix/seh/x86_64-4.9.2-release-posix-seh-rt_v4-rev2.7z && \
    7za x x86_64-4.9.2-release-posix-seh-rt_v4-rev2.7z && \
    mv mingw64 mingw && \
    rm -rf x86_64-4.9.2-release-posix-seh-rt_v4-rev2.7z

# Install WiX Toolset:
RUN mkdir ~/.wine32/drive_c/bin && \
    cd ~/.wine32/drive_c/bin && \
    wget -O wix.zip 'http://download-codeplex.sec.s-msft.com/Download/Release?ProjectName=wix&DownloadId=1421697&FileTime=130661188723230000&Build=20999' && \
    unzip wix.zip && \
    rm wix.zip

# Install 64bit Windows version of cabal-install:
RUN mkdir ~/.wine/drive_c/bin && \
    cd ~/.wine/drive_c/bin && \
    wget http://leksah.org/packages/cabal-mingw64.7z && \
    7za x cabal-mingw64.7z && \
    rm cabal-mingw64.7z

# Run `cabal update` and install some packages we will need.
# Some packages need us to run `mingw64-configure` manually (after `wine cabal configure` fails):
RUN wineserver -p1 && \
    cabal update && \
    wine cabal update && \
    wine cabal install old-locale && \
    cabal unpack network && \
    cd network-2.6.1.0 && \
    (wine cabal configure || true) && \
    mingw64-configure && \
    wine cabal build && \
    wine cabal copy && \
    wine cabal register && \
    cd .. && \
    cabal unpack old-time && \
    cd old-time-1.1.0.3 && \
    (wine cabal configure || true) && \
    mingw64-configure && \
    wine cabal build && \
    wine cabal copy && \
    wine cabal register && \
    cd .. && \
    wine cabal install Cabal alex happy && \
    wine cabal install gtk2hs-buildtools && \
    wine cabal install regex-tdfa-text --ghc-options=-XFlexibleContexts && \
    wineserver -w && \
    rm -rf network-2.6.1.0 old-time-1.1.0.3

# Add Leksah files to Docker:
ADD leksah.cabal LICENSE LICENSE.rtf Readme.md Setup.lhs SetupLocale.lhs sources.txt leksah/

# Docker has no way to COPY or ADD two directories at once!?!?
ADD bew leksah/bew
ADD data leksah/data
ADD doc leksah/doc
ADD gtk leksah/gtk
ADD language-specs leksah/language-specs
ADD linux leksah/linux
ADD main leksah/main
ADD osx leksah/osx
ADD pics leksah/pics
ADD po leksah/po
ADD scripts leksah/scripts
ADD src leksah/src
ADD tests leksah/tests
ADD vendor leksah/vendor

# Install fonts to bundle with Leksah
RUN sudo dnf -y install \
                   dejavu-sans-fonts \
                   dejavu-serif-fonts \
                   dejavu-sans-mono-fonts \
                   dejavu-lgc-sans-fonts \
                   dejavu-lgc-serif-fonts \
                   dejavu-lgc-sans-mono-fonts && \
    sudo dnf clean all && \
    mkdir -p ~/.wine32/drive_c/dejavu-fonts/ttf && \
    ln -s /usr/share/fonts/dejavu/* ~/.wine32/drive_c/dejavu-fonts/ttf

# Install grep to bundle with Leksah:
RUN mkdir grep && \
    cd grep && \
    wget http://sourceforge.net/projects/mingw/files/MSYS/Base/grep/grep-2.5.4-2/grep-2.5.4-2-msys-1.0.13-bin.tar.lzma && \
    tar --lzma -xvf grep-2.5.4-2-msys-1.0.13-bin.tar.lzma && \
    sudo cp bin/*grep.exe /usr/x86_64-w64-mingw32/sys-root/mingw/bin && \
    rm grep-2.5.4-2-msys-1.0.13-bin.tar.lzma

# Add the remaining Leksah files to Docker:
ADD win32 leksah/win32

# Build leksah and make the MSI file:
RUN wineserver -p1 && \
    cd leksah && \
    ./win32/makeinstaller.sh && \
    wineserver -w


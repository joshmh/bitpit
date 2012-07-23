#!/bin/bash -Eu

trap onexit 1 2 3 15 ERR
CURDIR=`pwd`

#--- onexit() -----------------------------------------------------
#  @param $1 integer  (optional) Exit status.  If not set, use `$?'
# Writes the last completed step for later continuation to a hidden file.
# Schreibt den letzten abgeschlossen Schritt in eine versteckte Datei,
# um später fortsetzen zu können

function onexit() {
    local exit_status=${1:-$?}
    echo Exiting $0 with $exit_status
    echo STEP=$STEP > $CURDIR/.upr-build.tmp
    for dir in mnt extract-cd/live edit/dev edit/sys edit/proc; do
        [ -d $CURDIR/$dir ] && sudo -H umount -l $CURDIR/$dir || continue
    done
    exit $exit_status
}

# Give basic help
# Einfache Hilfefunktion

function usage() {
    cat << EOF
    Usage: $0 [-c] [-n] [-s /path/to/sources.list] [-u <Name of ISO>]
        [-V] [-H] [-v]
    This scripts tries to build a Ubuntu Privacy Remix CD from scratch.
    Options:
    -h  This help
    -c  continue an interrupted build
    -n  Don't download anything, assumes you have downloaded
        * The Ubuntu CD image
        * The UPR support files archive
        * The linux-source-2.6.32 package
        * the Truecrypt sources
        * The PKCS11 header files from
          ftp://ftp.rsasecurity.com/pub/pkcs/pkcs-11/v2-20/,
          place them in /usr/local/include
        NOTE: you will most likely need a local Ubuntu mirror, accessible
        from within the chroot. Your local sources.list will be copied and
        used.
    If this will not work, specify a sources.list to use with -s
    -V  skip verification of gpg signatures and checksums
    For successful verification, you need to manually download and verify
    these keys:
    * Ubuntu Privacy Remix signing key (2E887042)
    * TrueCrypt Foundation (F0D6B1E0)
    * Ubuntu CD Image Automatic Signing Key (FBB75451)
    * if dualboot ISO with TAILS wanted TAILS developers signing key (BE2CD9C1)
    -s  path of the sources.list to use within the chroot
    -u  The name of the Ubuntu image to download/use
    -H  Generate hybrid ISO image, which can also be written to USB drive
    (requires SYSLINUX 4 installed)
    -T    Create a dualboot image with TAILS Live-CD
    -v  Verbose output
EOF
}
   
CDIMAGE="ubuntu-10.04.4-desktop-i386.iso"
TAILSIMAGE="tails-i386-0.9.iso"
NODOWNLOAD=0
NOVERIFY=0
SOURCESLIST=
HYBRID=0
TAILS=0
STEP=0

while getopts ":hcnu:vs:VHT" OPTION; do
    case $OPTION in
    h)
        usage
        exit 0
        ;;
    c)
        test -f .upr-build.tmp && source .upr-build.tmp
        ;;
    n)
        NODOWNLOAD=1
        ;;
    u)
        CDIMAGE=$OPTARG
        ;;
    v)
        set -x
        ;;
    s)
        SOURCESLIST=$OPTARG
        ;;
    V)
        NOVERIFY=1
        ;;
    H)
    HYBRID=1
    ;;
    T)
    TAILS=1
    ;;
    esac
done

echo "Note: you will most likely be required to enter your sudo password \
multiple times while this script runs. If you do not like this, increase \
the timeout in /etc/sudoers (man sudoers(5))."
sleep 3

# Install required tools
# Benötigte Tools auf dem Ubuntu-Arbeitssystem installieren:
if [ $STEP -lt 1 ]; then
    sudo -H apt-get -y install squashfs-tools genisoimage
    STEP=1
fi

# Load the squashfs module
# Das squashfs Modul laden

sudo -H modprobe squashfs

# Download the Image "Ubuntu 10.04 Desktop", its SHA1 sum and verify it.
# Das ISO-Image von "Ubuntu 10.04 Desktop"  hier herunterladen, SHA1-Summe und
# Signatur prüfen.
if [ $STEP -lt 2 ]; then
    test $NODOWNLOAD -ne 1 && wget -N http://de.archive.ubuntu.com/ubuntu-releases/10.04/$CDIMAGE
    test $NODOWNLOAD -ne 1 && wget -N http://de.archive.ubuntu.com/ubuntu-releases/10.04/SHA1SUMS
    test $NODOWNLOAD -ne 1 && wget -N http://de.archive.ubuntu.com/ubuntu-releases/10.04/SHA1SUMS.gpg
    test $NOVERIFY -ne 1 && gpg --verify SHA1SUMS.gpg SHA1SUMS
    test $NOVERIFY -ne 1 && grep "$CDIMAGE" SHA1SUMS | sha1sum -c
    STEP=2
fi


# Mount .iso
# Das .iso mounten:
if [ $STEP -lt 3 ]; then
    mkdir -p $CURDIR/mnt
    sudo -H mount -o loop $CDIMAGE $CURDIR/mnt

# Extract contents of the iso except filesystem.squashfs to 'extract-cd'
# Inhalt des .iso nach 'extract-cd' extrahieren (außer filesystem.squashfs) :
    mkdir -p extract-cd
    rsync --exclude=/casper/filesystem.squashfs -a --no-p --chmod=ugo=rwX mnt/ extract-cd
    sudo umount $CURDIR/mnt
    STEP=3
fi

# Extract the squashfs contents to 'edit'
# Das squashfs nach 'edit' entpacken:
if [ $STEP -lt 5 ]; then
    sudo -H mount -o loop $CDIMAGE $CURDIR/mnt
    sudo -H unsquashfs -f -d $CURDIR/edit $CURDIR/mnt/casper/filesystem.squashfs
    sudo -H umount $CURDIR/mnt
    STEP=5
fi

# Download our 'support files' archive, verify it and extract it from 'live'
# Unser Archiv "Support Files" herunterladen, Signatur prüfen und vom
# Verzeichnis 'live' aus entpacken:
if [ $STEP -lt 6 ]; then
    test $NODOWNLOAD -ne 1 && wget -N https://www.privacy-cd.org/download/upr-support-files-10.04r2.tar.bz2
    test $NODOWNLOAD -ne 1 && wget -N https://www.privacy-cd.org/download/upr-support-files-10.04r2.tar.bz2.sig
    test $NOVERIFY -ne 1 && gpg --verify upr-support-files-10.04r2.tar.bz2.sig upr-support-files-10.04r2.tar.bz2
    sudo -H tar --overwrite --preserve-permissions --same-owner --overwrite -jxf upr-support-files-10.04r2.tar.bz2
    # Make the network accessible from within the chroot
    # Anpassungen um Netzwerkverbindungen im chroot zu ermöglichen:
    sudo -H cp -f /etc/resolv.conf $CURDIR/edit/etc/resolv.conf
    sudo -H cp -f /etc/hosts $CURDIR/edit/etc/hosts
    # Make /dev, /proc and /sys available inside the chroot
    # Das /dev, /proc und /sys des Host für das chroot verfügbar machen:
    sudo -H mount --bind /dev/ $CURDIR/edit/dev
    sudo -H chroot $CURDIR/edit mount -t proc none /proc
    sudo -H chroot $CURDIR/edit mount -t sysfs none /sys

    # copy sources.list
    # sources.list kopieren
    if [ ! -z $SOURCESLIST ]; then
        sudo -H cp -f $SOURCESLIST $CURDIR/edit/etc/apt/
    else
        cat > $CURDIR/sources.list <<EOF
deb http://archive.ubuntu.com/ubuntu lucid main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu lucid-security main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu lucid-updates main restricted universe multiverse
EOF
        sudo -H chown root.root $CURDIR/sources.list
        sudo mv -f $CURDIR/sources.list $CURDIR/edit/etc/apt/
    fi

    STEP=6
fi

# Create custom UPR kernel - kernel configuration
# Angepassten Kernel erstellen - Kernel-Konfiguration erstellen
if [ $STEP -lt 7 ]; then
sudo -H apt-get -y install libncurses5-dev kernel-package
#test $NODOWNLOAD -ne 1 && apt-get download linux-source-2.6.32
test $NODOWNLOAD -ne 1 && sudo -H DEBIAN_FRONTEND=noninteractive chroot $CURDIR/edit aptitude update
test $NODOWNLOAD -ne 1 && sudo -H DEBIAN_FRONTEND=noninteractive chroot $CURDIR/edit aptitude download linux-source-2.6.32
test $NODOWNLOAD -ne 1 && sudo -H mv $CURDIR/edit/linux-source-2.6.32*deb $CURDIR/
sudo -H dpkg -i linux-source-2.6.32*deb
tar --overwrite -jvxf /usr/src/linux-source-2.6.32.tar.bz2
cd linux-source-2.6.32
sudo cp -f $CURDIR/edit/tmp/.config .
sudo patch -N -p0 -d drivers/ata -i $CURDIR/edit/tmp/libata-patch.diff
sudo patch -N -p0 -d ubuntu/omnibook -i $CURDIR/edit/tmp/omnibook.diff

CONCURRENCY_LEVEL=`grep -c 'model name' /proc/cpuinfo`
let CONCURRENCY_LEVEL*=2
export CONCURRENCY_LEVEL
sudo -H CONCURRENCY_LEVEL=$CONCURRENCY_LEVEL make-kpkg --Revision 1 --append-to-version "-upr" configure
sudo -H CONCURRENCY_LEVEL=$CONCURRENCY_LEVEL make-kpkg --Revision 1 --append-to-version "-upr" --initrd kernel_image
sudo -H cp -f ../linux-image-2.6.32*deb $CURDIR/edit/tmp/
cd ..
    STEP=7
fi

if [ $STEP -lt 9 ]; then
export LC_ALL=C 

# Software customization
# Modifikationen Software
# Make the network accessible from within the chroot
# Anpassungen um Netzwerkverbindungen im chroot zu ermöglichen:
sudo -H cp -f /etc/resolv.conf $CURDIR/edit/etc/resolv.conf
sudo -H cp -f /etc/hosts $CURDIR/edit/etc/hosts
# disable update-initramfs inside the chroot
# update-initramfs "kaltstellen"
sudo -H chroot $CURDIR/edit dpkg-divert --add --rename --quiet /usr/sbin/update-initramfs
cat > $CURDIR/update-initramfs <<EOF
#! /bin/sh
echo "update-initramfs is disabled since running inside chroot"
exit 0
EOF
sudo -H chown root.root $CURDIR/update-initramfs
sudo -H chmod 0755 $CURDIR/update-initramfs
sudo -H mv -f $CURDIR/update-initramfs $CURDIR/edit/usr/sbin/

# Remove unneeded packages
# Software entfernen: nicht benötigte Programme.
sudo -H DEBIAN_FRONTEND=noninteractive chroot $CURDIR/edit aptitude update
sudo -H DEBIAN_FRONTEND=noninteractive chroot $CURDIR/edit aptitude -y --without-recommends purge adium-theme-ubuntu aisleriot alacarte anacron app-install-data app-install-data-partner apparmor apparmor-utils apport apport-gtk apport-symptoms apt-transport-https apt-xapian-index aptdaemon apturl apturl-common at avahi-autoipd avahi-daemon avahi-utils bcmwl-modaliases bind9-host binutils bluez bluez-alsa bluez-cups bluez-gstreamer bogofilter bogofilter-bdb bogofilter-common brltty brltty-x11 byobu cdparanoia checkbox checkbox-gtk command-not-found command-not-found-data compiz compiz-core compiz-fusion-plugins-main compiz-gnome compiz-plugins compizconfig-backend-gconf computer-janitor computer-janitor-gtk couchdb-bin cron dc desktopcouch dhcp3-client dhcp3-common dmraid dnsmasq-base dnsutils empathy empathy-common erlang-base erlang-crypto erlang-inets erlang-mnesia erlang-public-key erlang-runtime-tools erlang-ssl erlang-syntax-tools erlang-xmerl evolution-couchdb evolution-exchange evolution-indicator evolution-webcal example-content f-spot fglrx-modaliases friendly-recovery ftp gbrainy gcalctool gcc gcc-4.4 gdb gdebi gdebi-core gdm-guest-session geoip-database gnome-bluetooth gnome-codec-install gnome-games-common gnome-mag gnome-mahjongg gnome-nettool gnome-orca gnome-session-canberra gnome-sudoku gnome-user-share gnome-themes-ubuntu gnome-system-tools gnomine gparted grub-common grub-pc guile-1.8-libs gvfs-bin gvfs-fuse gwibber gwibber-service hal hal-info humanity-icon-theme ibus ibus-gtk indicator-me indicator-messages iproute iptables iputils-arping iputils-ping iputils-tracepath jockey-common jockey-gtk language-pack-bn language-pack-bn-base language-pack-gnome-bn language-pack-gnome-bn-base language-pack-gnome-pt language-pack-gnome-pt-base language-pack-gnome-xh language-pack-gnome-xh-base language-pack-pt language-pack-pt-base language-pack-xh language-pack-xh-base language-selector launchpad-integration lftp libatm1 libavahi-core6 libavahi-gobject0 libbind9-60 libbrlapi0.5 libbsd0 libc6-dev libcanberra-pulse libclutter-1.0-0 libclutter-gtk-0.10-0 libcompizconfig0 libcouchdb-glib-1.0-2 libcurl3 libdaemon0 libdebconfclient0 libdebian-installer4 libdesktopcouch-glib-1.0-2 libdmraid1.0.0.rc16 libdns64 libdotconf1.0 libedit2 libevent-1.4-2 libflickrnet2.2-cil libfs6 libgadu3 libgail-gnome-module libgc1c2 libgeoip1 libglitz-glx1 libglitz1 libgnome-bluetooth7 libgnome-keyring1.0-cil libgnome-mag2 libgnomepanel2.24-cil libgoocanvas3 libgoocanvas-common libgtk-vnc-1.0-0 libgtkspell0 libgstfarsight0.10-0 libibus1 libindicate4 libindicate-gtk2 libisc60 libisccc60 libisccfg60 libjs-jquery liblaunchpad-integration1.0-cil libloudmouth1-0 liblouis0 liblwres60 libmeanwhile1 libmono-addins-gui0.2-cil libmono-addins0.2-cil libmtp8 libmusicbrainz4c2a libnl1 libnm-glib2 libnm-util1 libnss-mdns libnunit2.4-cil liboobs-1-4 libopenobex1 libparted0 libpcap0.8 libprotobuf5 libprotoc5 libpurple-bin libpurple0 libsasl2-modules libsdl1.2debian libsilc-1.1-2 libsilcclient-1.1-3 libspeechd2 libtelepathy-farsight0 libthelepathy-glib0 libxml-xpath-perl libxp6 libzephyr4 linux-generic linux-headers-2.6.32~n linux-headers-generic linux-image-2.6.32~n linux-image-generic linux-libc-dev logrotate manpages-dev memtest86+ mobile-broadband-provider-info modemmanager mtr-tiny nautilus-actions nautilus-sendto nautilus-sendto-empathy nautilus-share netcat-openbsd network-manager network-manager-gnome network-manager-pptp network-manager-pptp-gnome ntpdate nvidia-173-modaliases nvidia-96-modaliases nvidia-common obex-data-server obexd-client openoffice.org-emailmerge openssh-client parted pitivi popularity-contest ppp pppconfig pppoeconf pptp-linux protobuf-compiler python-apport python-aptdaemon python-avahi python-configglue python-couchdb python-desktopcouch python-desktopcouch-records python-egenix-mxdatetime python-egenix-mxtools python-fstab python-gnupginterface python-gtkspell python-launchpad-integration python-launchpadlib python-lazr.restfulclient python-lazr.uri python-mako python-newt python-oauth python-openssl python-pam python-papyon python-problem-report python-protobuf python-pyatspi python-pycurl python-pygoocanvas python-pyinotify python-serial python-simplejson python-speechd python-software-properties python-telepathy python-twisted-core python-ubuntuone-storageprotocol python-vde python-wadllib python-webkit python-ubuntuone-client python-xapian python-zope.interface quadrapassel rdate rdesktop rhythmbox rhythmbox-plugin-cdrecorder rhythmbox-plugins rhythmbox-ubuntuone-music-store samba-common samba-common-bin smbclient software-center software-properties-gtk speech-dispatcher ssh-askpass-gnome synaptic tasksel tasksel-data tcpd tcpdump telepathy-butterfly telepathy-gabble telepathy-haze telepathy-idle telepathy-mission-control-5 telepathy-salut telnet tomboy totem-mozilla transmission-common transmission-gtk tsclient ubiquity ubiquity-casper ubiquity-frontend-gtk ubiquity-slideshow-ubuntu ubiquity-ubuntu-artwork ubufox ubuntu-desktop ubuntu-keyring ubuntu-minimal ubuntu-standard ubuntu-wallpapers ubuntuone-client ubuntuone-client-gnome ufw unattended-upgrades update-manager update-manager-core update-notifier update-notifier-common usb-creator-gtk usb-creator-common vinagre vino w3m whois wireless-tools wpasupplicant x11-apps x11-xfs-utils xbitmaps xorg xscreensaver-gl xterm libpolkit-gtk-1-0 libtelepathy-glib0 libubuntuone-1.0-1 light-themes nautilus-actions python-ibus python-twisted-bin python-ubuntuone python-vte ubuntu-artwork ubuntu-mono ibus-m17n ibus-table python-aptdaemon-gtk python-brlapi python-farsight python-indicate python-louis python-twisted-names python-twisted-web os-prober wireless-crda popularity-contest python-apport python-aptdaemon python-aptdaemon-gtk python-avahi python-configglue python-couchdb python-egenix-mxdatetime python-egenix-mxtools python-fstab python-gnupginterface python-ibus python-launchpad-integration python-launchpadlib python-lazr.restfulclient python-lazr.uri python-mako python-newt python-oauth python-openssl python-pam python-problem-report python-protobuf python-pyatspi python-pycurl python-pyinotify python-serial python-simplejson python-software-properties python-telepathy python-twisted-bin python-twisted-core python-twisted-names python-twisted-web python-ubuntuone-client python-ubuntuone-storageprotocol python-vte python-wadllib python-webkit python-xapian python-zope.interface rdesktop rhythmbox rhythmbox-plugin-cdrecorder samba-common samba-common-bin smbclient software-properties-gtk synaptic tasksel tasksel-data tcpd telnet totem-mozilla transmission-common tsclient ubiquity-casper ubiquity-slideshow-ubuntu ubiquity-ubuntu-artwork ubuntu-keyring ubuntu-wallpapers ubuntuone-client ubuntuone-client-gnome unattended-upgrades update-manager update-manager-core update-notifier update-notifier-common usb-creator-common usb-creator-gtk whois wireless-tools x11-apps xbitmaps xscreensaver-gl xterm

# System update
sudo -H DEBIAN_FRONTEND=noninteractive chroot $CURDIR/edit aptitude -y full-upgrade

# Add required packages
# Benötigte Software hinzufügen
sudo -H DEBIAN_FRONTEND=noninteractive chroot $CURDIR/edit aptitude -y --without-recommends install a2ps acl beagle blt ca-certificates-java cdrdao conky-all deborphan default-jre-headless deskbar-applet dialog exiv2 fastjar foo2zjs fpm2 gcalctool gcj-4.3-base gcj-4.4-base gcj-4.4-jre gcj-4.4-jre-headless gcj-4.4-jre-lib gij-4.3 gimp gimp-help-de gimp-help-en gimp-help-es gimp-help-it gimp-help-fr gnome-themes gnome-user-guide-de gnome-user-guide-en gnome-user-guide-es gnome-user-guide-it gnome-user-guide-fr gnupg-agent gnupg2 gparted gtkrsync grsync hamster-applet hpijs-ppds hunspell-de-at hunspell-de-ch hunspell-de-de icedtea-6-jre-cacao icoutils java-common khelpcenter4 language-pack-it language-pack-gnome-it language-support-de language-support-es language-support-it language-support-fr language-support-writing-de language-support-writing-es language-support-writing-it language-support-writing-fr libaccess-bridge-java libaccess-bridge-java-jni libao2 libaudio2 libavahi1.0-cil libchm1 libgcj-common libgcj10 libgcj10-awt libgcj9-0 libgcj9-jar libgmime-2.0-2a libgmime2.2a-cil libgnomecups1.0-1 libgnomeprint2.2-0 libgnomeprint2.2-data libgnomeprintui2.2-0 libgnomeprintui2.2-common libhsqldb-java libid3tag0 libimage-exiftool-perl libimlib2 libjline-java libksba8 liblua5.1-0 libmng1 libmono0 libnotify-bin libpam-pwdfile libqt3-mt libqt4-dbus libqt4-designer libqt4-network libqt4-qt3support libqt4-script libqt4-sql libqt4-xml libqtcore4 libqtgui4 libservlet2.5-java libstlport4.6-dev libtaglib2.0-cil libwxgtk2.8-0 lsscsi lxde-icon-theme min12xxw m2300w mono-gmcs nautilus-filename-repairer nautilus-image-converter openjdk-6-jre openjdk-6-jre-headless openjdk-6-jre-lib openoffice.org openoffice.org-base openoffice.org-filter-binfilter openoffice.org-filter-mobiledev openoffice.org-help-de openoffice.org-help-es openoffice.org-help-it openoffice.org-help-fr openoffice.org-help-en-gb openoffice.org-hyphenation openoffice.org-hyphenation-de openoffice.org-hyphenation-en-us openoffice.org-hyphenation-es openoffice.org-hyphenation-it openoffice.org-hyphenation-fr openoffice.org-java-common openoffice.org-l10n-common openoffice.org-l10n-de openoffice.org-l10n-en-gb openoffice.org-l10n-en-za openoffice.org-l10n-es openoffice.org-l10n-it openoffice.org-l10n-fr openoffice.org-officebean openoffice.org-report-builder-bin openoffice.org-thesaurus-de openoffice.org-thesaurus-de-ch openoffice.org-thesaurus-en-au openoffice.org-thesaurus-en-us openoffice.org-thesaurus-it openoffice.org-thesaurus-fr openprinting-ppds-extra parted patch p7zip-full pinentry-gtk2 planner psutils python-beagle python-bugbuddy python-daemon python-evince python-evolution python-gnome2-desktop python-gnomedesktop python-gnomeprint python-gtop python-magic python-mediaprofiles python-metacity python-nautilus python-parted python-rsvg python-tk python-totem-plparser pxljr rhino scribus scribus-doc scribus-template secure-delete splix syslog-ng tcl8.5 tellico tk8.5 ttf-dejavu ttf-dejavu-extra ttf-sil-gentium ttf-sil-gentium-basic tzdata-java unrtf usb-imagewriter vym wngerman language-pack-fr language-pack-gnome-fr wogerman wswiss libsasl2-modules virtuoso-nepomuk python-dmidecode expect ssss

# Install our own packages, which were placed into /tmp by unpacking the
# support files archive, as well as the kernel.
# Our custom software is:
# * a backported version of dosfsutils 3.0.9, which fixes a problem with
#   setting the label on vfat volumes
# * a backported version of gtkrsync 1.0.4, which fixes several bugs
# * our own GPG frontend, which we need to document in detail. For now, see
#   the corresponding chapters in the UPR guide
# * a small workaround around a lucid bug for mounting floppy disks 
# * a patched version of nautilus which disables the use of beagle for the
#   internal search function
# * a nautilus extension which allows printing of files through the
#   context menu
# * a nautilus extension which allows changing a volume's label through
#   the context menu
# * a small split-off from the original seahorse package, to keep the
#   possibility of importing gpg keys by double-clicking
# * our own TrueCrypt "frontend"
# * a backported version of unrtf, which fixes problem with umlauts
#   (required by beagle)
# * X-Tile, a small app for arranging windows
# Installiere unsere eigenen Pakete, die durch Auspacken des "Support Files"
# Archivs in /tmp abgelegt wurden, sowie den Kernel
# Unsere eigenen Pakete sind:
# * eine zurüc portierte Version von dosfsutils 3.0.9, die einen Fehler
#   beim Umbenennen von VFAT-Datenträgern behebt.
# * eine zurück portierte Version von gtkrsync 1.0.4, die Fehler behebt.
# * unser eigenes GPG-Frontend, welches noch mehr Dokumentation benötigt.
#   Im Moment bitte im UPR-Handbuch nachsehen.
# * Ein kleiner workaround zum Einhängen von Disketten, was in Lucid nicht
#   richtig funktioniert.
# * Eine gepatchte Version von Nautilus, in der die Verwendung von Beagle
#   für die interne Suchfunktion deaktiviert ist.
# * Eine Nautilus-Erweiterung, die das Drucken aus dem Kontextmenü heraus
#   ermöglicht
# * Eine Nautilus-Erweiterung, die das Umbenennen von Datenträgern aus
#   dem Kontextmenü heraus ermöglicht.
# * Eine kleine Abspaltung des originalen Seahorse-Pakets, damit das Importieren
#   von GPG-Schlüsseln mit Doppelklick weiterhin möglich ist.
# * Unser eigenes TrueCrypt-"Frontend".
# * Eine zurück portierte Version von unrtf, die Probleme mit Umlauten behebt
#   (wird von beagle benötigt).
sudo -H chroot $CURDIR/edit find /tmp/ -name "*.deb" -exec dpkg -i {} \;
sudo -H rm $CURDIR/edit/tmp/*.deb
STEP=9
fi

# Customizations to configuration data
# Einstellungen anpassen
if [ $STEP -lt 10 ]; then

# Install Electrum bitcoin client
sudo -H cp -rf /usr/local/lib/python2.6/dist-packages/ $CURDIR/edit/usr/local/lib/python2.6/
sudo -H cp -f /usr/local/bin/electrum $CURDIR/edit/usr/local/bin

# Install bitpit custom scripts
sudo -H cp -f $CURDIR/scripts/* $CURDIR/edit/usr/local/bin
sudo -H chmod 755 $CURDIR/edit/usr/local/bin/*.sh
sudo -H chmod 755 $CURDIR/edit/usr/local/bin/cw
sudo -H chmod 755 $CURDIR/edit/usr/local/bin/tx

# Reasonable settings for beagle
# Sinnvolle Voreinstellungen für Beagle
sudo -H cp -f $CURDIR/edit/tmp/Daemon.xml $CURDIR/edit/etc/beagle/config-files/Daemon.xml
sudo -H rm -f $CURDIR/edit/etc/xdg/autostart/beagled-autostart.desktop
sudo -H rm -f $CURDIR/edit/etc/xdg/autostart/beagle-search-autostart.desktop
cd $CURDIR
sudo su -c 'echo "fs.inotify.max_user_watches = 65535" >> edit/etc/sysctl.conf'

# Customizations for casper, enable Boot-to-RAM
# Anpassungen für casper, ermögliche Boot-to-RAM
sudo -H patch -N -d $CURDIR/edit/usr/share/initramfs-tools/scripts -p0 -i $CURDIR/edit/tmp/casper.diff
sudo -H patch -N -d $CURDIR/edit/usr/share/initramfs-tools/scripts/casper-bottom -p0 -i $CURDIR/edit/tmp/10adduser.diff

# Customizations for GPG-Agent, make it start without a gpg.conf
# Anpassungen für GPG-Agent, soll auch ohne gpg.conf starten
sudo -H patch -N -d $CURDIR/edit/etc/X11/Xsession.d -p0 -i $CURDIR/edit/tmp/90gpg-agent.diff

# Change gnome theme and window borders to "glossy"
# Gnome-Theme und Fensterränder ändern auf "glossy"
sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults/ \
--type string --set /desktop/gnome/interface/gtk_theme "Glossy"

# Change theme
# Theme anpassen
sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults/ \
--type string --set /apps/metacity/general/theme "ClearlooksWithACherryOnTop"

sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults/ \
--type string --set /desktop/gnome/interface/gtk_theme "ClearlooksClassic"

export COLORSCHEME="`cat <<cc
fg_color:#000000000000
bg_color:#edede9e9e3e3
text_color:#000000000000
base_color:#ffffffffffff
selected_fg_color:#ffffffffffff
selected_bg_color:#969690908f8f
tooltip_fg_color:#000000000000
tooltip_bg_color:#ffffffffbfbf
cc
`"

sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults/ \
--type string --set /desktop/gnome/interface/gtk_color_scheme "$COLORSCHEME"

sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults/ \
--type integer --set /apps/panel/toplevels/bottom_panel_screen0/background/opacity "12434"

sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults/ \
--type string --set /apps/panel/toplevels/bottom_panel_screen0/background/type "color"

sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults/ \
--type integer --set /apps/panel/toplevels/top_panel_screen0/background/opacity "12434"

sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults/ \
--type string --set /apps/panel/toplevels/top_panel_screen0/background/type "color"

sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults/ \
--type string --set /desktop/gnome/background/picture_options "zoom"

# Window buttons on the right
# Buttons rechts anordnen:
sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults/ \
--type string --set /apps/metacity/general/button_layout "menu:minimize,maximize,close"

# Disable event sounds, enerving
# Sounds abschalten, nervt
sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults/ \
--type bool --set /desktop/gnome/sound/event_sounds false

# Set icons to nuoveXT
# Iconsatz ändern auf nuoveXT
sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults/ \
--type string --set /desktop/gnome/interface/icon_theme "nuoveXT2"

# GDM background color set to #1188D4
# GDM-Hintergrundfarbe ändern auf #1188D4:
sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults \
--type string --set /desktop/gnome/background/primary_color "#1188D4"

# Change wallpaper
# Hintergrundbild ändern:
# Copy bitpit bg image
sudo -H cp -f $CURDIR/images/bitpit.png $CURDIR/edit/usr/local/share/backgrounds/bitpit-bg.png
sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults \
--type string --set /desktop/gnome/background/picture_filename \
"/usr/local/share/backgrounds/bitpit-bg.png"

# Set nautilus to list view
# Nautilus auf Listenansicht umstellen:
sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults \
--type string --set \
/apps/nautilus/preferences/default_folder_viewer "list_view"

# Disable visual effects for increased compatibility
# „Visuelle Effekte“ ausschalten zur verbesserten Kompatibilität mit manchen
# Grafikkarten.
sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults \
--type string --set \
/desktop/gnome/applications/window_manager/default \
"/usr/bin/metacity"

# Shortcut for re-starting the gnome panel (necessary on some old graphics
# cards).
# Shortcut für das Neustarten des GNOME-Panels
# (auf manchen älteren Grafikkarten leider notwendig)
sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults --set \
/desktop/gnome/keybindings/custom0/action \
--type string "killall gnome-panel"
sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults --set \
/desktop/gnome/keybindings/custom0/binding \
--type string "<Control><Alt>k"
sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults --set \
/desktop/gnome/keybindings/custom0/name \
--type string "Restore GNOME Panel"

# File-rolle should default to creating ZIP archives
# File-Roller standardmäßig auf ZIP umstellen
sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults --set \
/apps/file-roller/dialogs/batch.add/default_extension \
--type string ".zip"

# Configure X-Tile
sudo -H cp -f $CURDIR/edit/usr/share/applications/x-tile.desktop \
$CURDIR/edit/etc/xdg/autostart/
sudo su -c 'echo "X-GNOME-Autostart-Phase=Applications" >> edit/etc/xdg/autostart/x-tile.desktop'
sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults --set \
/apps/x-tile/language --type string "default"
sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults --set \
/apps/x-tile/0/exit_after_tile --type string "True"
sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults --set \
/apps/x-tile/0/only_curr_desk --type string "True"
sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults --set \
/apps/x-tile/0/systray_enable --type string "True"
sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults --set \
/apps/x-tile/0/systray_start --type string "True"
sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults --set \
/apps/x-tile/0/exit_after_tile --type string "True"
sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults --set \
/apps/x-tile/0/not_minimized --type string "True"

# Remove Firefox, Evolution and Java WebStart from the gnome panel and the
# "Internet" submenu. Clean up "Places", make menu entries for onBoard
# visibile
# Firefox, Evolution und Java WebStart aus Gnome Panel und "Internet"-
# Submenü entfernen. Orte-Menü aufräumen. onBoard-Menüeinträge sichtbar machen
sudo -H rm -f $CURDIR/edit/usr/share/applications/evolution-mail.desktop
sudo -H rm -f $CURDIR/edit/usr/share/applications/openjdk-6-javaws.desktop
sudo -H rm -f $CURDIR/edit/usr/share/applications/network-scheme.desktop
sudo -H rm -f $CURDIR/edit/usr/bin/nautilus-connect-server

sudo -H sed -i 's/DOWNLOAD=.*/DOWNLOAD=Desktop/' \
$CURDIR/edit/etc/xdg/user-dirs.defaults

sudo -H sed -i 's/DOCUMENTS=.*/DOCUMENTS=Desktop/' \
$CURDIR/edit/etc/xdg/user-dirs.defaults

sudo -H sed -i 's/MUSIC=.*/MUSIC=Desktop/' \
$CURDIR/edit/etc/xdg/user-dirs.defaults

sudo -H sed -i 's/PICTURES=.*/PICTURES=Desktop/' \
$CURDIR/edit/etc/xdg/user-dirs.defaults

sudo -H sed -i 's/VIDEOS=.*/VIDEOS=Desktop/' \
$CURDIR/edit/etc/xdg/user-dirs.defaults

sudo -H sed -i 's/TEMPLATES=.*/TEMPLATES=Desktop/' \
$CURDIR/edit/etc/xdg/user-dirs.defaults

sudo -H sed -i 's/PUBLICSHARE=.*/PUBLICSHARE=Desktop/' \
$CURDIR/edit/etc/xdg/user-dirs.defaults

sudo -H sed -i 's/Categories=Application;Internet;Network;WebBrowser;/Categories=Application;Utility;/' \
edit/usr/share/applications/firefox.desktop

sudo -H sed -i 's/Categories=GNOME;GTK;Utility;Accessibility;X-GNOME-PersonalSettings;/Categories=GNOME;GTK;Utility;/' \
edit/usr/share/applications/onboard.desktop

sudo -H sed -i 's/Categories=Qt;KDE;Education;/Categories=Application;Office;/' \
edit/usr/share/applications/vym.desktop

sudo -H sed -i 's/NoDisplay=true/NoDisplay=false/' $CURDIR/edit/usr/share/applications/onboard.desktop

sudo -H sed -i 's/Categories=GNOME;GTK;Utility;Accessibility;X-GNOME-PersonalSettings;/Categories=GNOME;GTK;Settings;DesktopSettings;/' \
$CURDIR/edit/usr/share/applications/onboard-settings.desktop

sudo -H sed -i 's/NoDisplay=true/NoDisplay=false/' \
edit/usr/share/applications/onboard-settings.desktop

sudo -H sed -i 's/NoDisplay=true/NoDisplay=false/' \
$CURDIR/edit/usr/share/applications/file-roller.desktop

sudo -H sed -i 's/Categories=GTK;Utility;/Categories=GTK;Security;/' \
$CURDIR/edit/usr/share/applications/fpm2.desktop

# Remove gnome-network-properties
sudo -H rm -f $CURDIR/usr/share/applications/gnome-network-properties.desktop

# Enable lock-screen password protection
sudo -H sed -i 's/ACTIVE_CONSOLES=.*/ACTIVE_CONSOLES=""/' \
$CURDIR/edit/etc/default/console-setup
sudo -H rm -f $CURDIR/edit/etc/init/tty*.conf
sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults --set \
/desktop/gnome/lockdown/disable_user_switching \
--type bool true
sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults --set \
/apps/gnome-screensaver/user_switch_enabled \
--type bool false
sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults --set \
/apps/gnome-screensaver/lock_enabled \
--type bool false
sudo su -c 'echo "kernel.sysrq = 176" >> edit/etc/sysctl.conf'
sudo -H sed -i "s/echo 'RUNNING_UNDER_GDM=\"yes\"'.*$//" $CURDIR/edit/usr/share/initramfs-tools/scripts/casper-bottom/10adduser
sudo -H rm -f $CURDIR/edit/usr/share/initramfs-tools/scripts/casper-bottom/22screensaver
sudo -H rm -f $CURDIR/edit/usr/share/initramfs-tools/scripts/casper-bottom/22gnome_panel_data

# Create a new submenu "Security" for FPM, TrueCrypt and the GPG frontend
# FPM, TrueCrypt und das GPG frontend in einer neuen Gruppe "Security" bündeln
sudo -H cat $CURDIR/edit/etc/xdg/menus/applications.menu | awk '/<!-- End System Tools -->/ { $0 = $0 "\n  <!-- Security -->\n  <Menu>\n    <Name>Security</Name>\n    <Directory>Security.directory</Directory>\n    <Include>\n      <Or>\n        <Category>Security</Category>\n        <Category>Encryption</Category>\n      </Or>\n    </Include>\n  </Menu>   <!-- End Security -->\n  <!-- Help -->\n  <Menu>\n    <Name>Help</Name>\n    <Directory>Help.directory</Directory>\n    <Include>\n      <Or>\n        <Category>Documentation</Category>\n        <Category>Help</Category>\n      </Or>\n    </Include>\n  </Menu>  <!-- End Help -->" } 1' > $CURDIR/applications.menu
sudo -H mv -f $CURDIR/applications.menu $CURDIR/edit/etc/xdg/menus/applications.menu

# Create menu entries for UPR Help under System
sudo -H patch -N -p0 -d $CURDIR/edit/etc/xdg/menus -i $CURDIR/edit/tmp/settings.diff

# Hamster defaults
# Hamster-Voreinstellungen
sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults \
--type bool --set /apps/hamster-applet/general/stop_on_shutdown \
true

# Make logs readable
sudo -H sed -i 's/FileGroup adm/FileGroup users/' $CURDIR/edit/etc/rsyslog.conf

# Lock CD-ROM when necessary
sudo -H chroot $CURDIR/edit update-rc.d lock-cdrom.sh start 99 S .

# Configure Tellico
sudo -H sed -i 's/*.tc;//' $CURDIR/edit/usr/share/mimelnk/application/x-tellico.desktop
sudo -H sed -i '/*.tc/d' $CURDIR/edit/usr/share/mime/packages/tellico.xml
sudo -H chroot edit update-mime-database /usr/share/mime
sudo -H rm -f $CURDIR/edit/usr/share/applications/kde4/kpackagekit.desktop

# Configure syslog-ng
sudo -H sed -i 's!# destinations!# destinations\ndestination df_logwatcher { unix-stream("/tmp/logwatcher.socket"); };!' \
$CURDIR/edit/etc/syslog-ng/syslog-ng.conf
sudo -H sed -i 's!# filters!# filters\nfilter f_faterr { match("FAT: Filesystem error") or match("EXT3-fs error") or match("Found open truecrypt volumes"); };!' $CURDIR/edit/etc/syslog-ng/syslog-ng.conf
sudo -H sed -i 's!# logs!# logs\nlog { source(s_all); filter(f_faterr); destination(df_logwatcher); };!' $CURDIR/edit/etc/syslog-ng/syslog-ng.conf

# Workaround for USB 3.0 preventing suspend
sudo su -c "echo SUSPEND_MODULES=\"xhci\" > $CURDIR/edit/etc/pm/config.d/00sleep_module"

# Disable suspend by default since this often turns off usb ports
# which UPR is running from
sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults \
--type int --set \
/apps/gnome-power-manager/timeout/sleep_computer_ac 0
sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults \
--type int --set \
/apps/gnome-power-manager/timeout/sleep_computer_battery 0
sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults \
--type string --set \
/apps/gnome-power-manager/buttons/lid_ac "blank"
sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults \
--type string --set \
/apps/gnome-power-manager/buttons/lid_battery "blank"
sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults \
--type string --set \
/apps/gnome-power-manager/buttons/suspend "nothing"
sudo -H chroot $CURDIR/edit gconftool-2 --direct --config-source \
xml:readwrite:/etc/gconf/gconf.xml.defaults \
--type string --set \
/apps/gnome-power-manager/actions/critical_battery "nothing"
STEP=10
fi

# Complete kernel installation
# Kernel-Installation abschließen
if [ $STEP -lt 11 ]; then
sudo -H rm -f $CURDIR/edit/usr/sbin/update-initramfs
sudo -H chroot $CURDIR/edit mv /usr/sbin/update-initramfs.distrib /usr/sbin/update-initramfs
sudo -H chroot $CURDIR/edit update-initramfs -c -k `basename $CURDIR/edit/lib/modules/2.6.32*upr`
STEP=11
fi

# Incorporate the kernel into the live CD
# Den Kernel in die Live-CD integrieren
if [ $STEP -lt 12 ]; then
sudo -H mv $CURDIR/edit/boot/initrd.img-2.6.32*-upr $CURDIR/extract-cd/casper/initrd.gz
sudo -H mv $CURDIR/edit/boot/vmlinuz-2.6.32*-upr $CURDIR/extract-cd/casper/vmlinuz

sudo -H su -c "gunzip -c $CURDIR/extract-cd/casper/initrd.gz | lzma -9 -c - > $CURDIR/extract-cd/casper/initrd.lz"
sudo -H rm $CURDIR/extract-cd/casper/init*.gz

# Clean up inside the chroot
# Im chroot Aufräumen:
sudo -H rm -f $CURDIR/edit/usr/share/applications/mimeinfo.cache
sudo -H rm -f $CURDIR/edit/usr/share/applications/desktop.*.cache
sudo -H rm -f $CURDIR/edit/usr/local/share/applications/mimeinfo.cache
sudo -H rm -f $CURDIR/edit/usr/local/share/applications/desktop.*.cache
sudo -H chroot $CURDIR/edit update-desktop-database
sudo -H chroot $CURDIR/edit update-mime-database /usr/share/mime
sudo -H chroot $CURDIR/edit aptitude clean
sudo -H rm -rf $CURDIR/edit/tmp/*
sudo -H rm -f $CURDIR/edit/etc/resolv.conf
sudo -H rm -f $CURDIR/edit/var/cache/apt/*.bin
sudo -H umount -l $CURDIR/edit/proc
sudo -H umount -l $CURDIR/edit/sys
sudo -H umount -l $CURDIR/edit/dev
STEP=12
fi

# Build CD
# CD zusammenbauen

# re-create manifest, which contains a list of all packages installed within
# the squashfs.
# manifest neu erstellen: Die Datei filesystem.manifest enthält alle im squashfs
# installierten Pakete.
if [ $STEP -lt 13 ]; then
chmod +w extract-cd/casper/filesystem.manifest*
sudo -H chroot $CURDIR/edit dpkg-query -W --showformat='${Package} ${Version}\n' > \
extract-cd/casper/filesystem.manifest
sudo -H cp extract-cd/casper/filesystem.manifest \
extract-cd/casper/filesystem.manifest-desktop
sudo -H sed -i '/ubiquity/d' extract-cd/casper/filesystem.manifest-desktop

# Create squashfs filesystem
# Squashfs-Dateeisystem neu erzeugen:
sudo -H rm -f extract-cd/casper/filesystem.squashfs
sudo -H mksquashfs $CURDIR/edit extract-cd/casper/filesystem.squashfs
STEP=13
fi

# Adapt names for the image:
# Namen für Image anpassen:
if [ $STEP -lt 14 ]; then
sudo -H sed -i 's/^#define DISKNAME .*$/#define DISKNAME  Ubuntu Privacy Remix (BTC) 10.04r2 "Locked Lynx" - Release i386/' extract-cd/README.diskdefines

# Remove unneeded crap
# Unnötigen Krempel entfernen
sudo -H rm -rf extract-cd/dists extract-cd/pool extract-cd/pics extract-cd/preseed extract-cd/wubi.exe extract-cd/autorun.inf

# Recalculate md5 and sha1 sums.
# md5 und sha1 summen neu berechnen:
cd $CURDIR/extract-cd
sudo -H rm -f {md5sum,sha1sum}.{txt,txt.sig}
sudo su -c "find . -not -name md5sum.txt* -and -not -name boot.cat -and \
-not -name isolinux.bin -and -not -name sha1sum.txt* -type f -print0 | xargs -0 \
md5sum > md5sum.txt"
sudo su -c "find . -not -name md5sum.txt* -and -not -name boot.cat -and \
-not -name isolinux.bin -and -not -name sha1sum.txt* -type f -print0 | xargs -0 \
sha1sum > sha1sum.txt"
STEP=14
fi

# create iso
# iso erstellen
if [ $STEP -lt 15 ]; then
if [ $TAILS -eq 1 ]; then
    test $NODOWNLOAD -ne 1 && wget -N http://dl.amnesia.boum.org/tails/stable/tails-i386-0.9/$TAILSIMAGE
    test $NODOWNLOAD -ne 1 && wget -N http://dl.amnesia.boum.org/tails/stable/tails-i386-0.9/$TAILSIMAGE.pgp
    test $NOVERIFY -ne 1 && gpg --verify $CURDIR/$TAILSIMAGE.pgp $CURDIR/$TAILSIMAGE
    sudo -H mount -o loop $CURDIR/$TAILSIMAGE $CURDIR/mnt
    sudo -H mkdir -p $CURDIR/extract-cd/live
    sudo -H mount --bind $CURDIR/mnt/live $CURDIR/extract-cd/live
    [ -d $CURDIR/extract-cd/isoupr ] || sudo -H mv $CURDIR/extract-cd/isolinux $CURDIR/extract-cd/isoupr
    [ -d $CURDIR/extract-cd/isotails ] || sudo -H cp -af $CURDIR/mnt/isolinux $CURDIR/extract-cd/isotails
    sudo -H cp -af $CURDIR/isolinux-dualboot $CURDIR/extract-cd/isolinux
fi
cd $CURDIR/extract-cd
sudo -H mkisofs -r -V "UPR_10.04r2" -cache-inodes -J -l -b isolinux/isolinux.bin -c \
isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o ../bitpit-0.1.iso .

if [ $TAILS -eq 1 ]; then
    sudo -H umount $CURDIR/extract-cd/live
    sudo -H umount $CURDIR/mnt
fi

STEP=15
fi

# make it hybrid (optional, required SYSLINUX 4. Known not to work on all
# machines).
# Optional ein Hybrid-ISO erstellen (benötigt SYSLINUX 4, läuft nicht auf allen
# Rechnern).
if [ $STEP -lt 16 ]; then
    cd $CURDIR
    if [ $HYBRID -eq 1 ]; then
        if [ -x /usr/bin/isohybrid ]; then
            sudo -H isohybrid --entry 4 --type 1c -v $CURDIR/bitpit.0.1.iso
        else
            echo "isohybrid not found, cannot make hybrid image!"
        fi
    fi
fi

STEP=0

onexit

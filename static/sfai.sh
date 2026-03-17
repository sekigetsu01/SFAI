#!/bin/sh
# SFAI - Sekigetsu's Fedora Auto Installer
# Run as root on a fresh Fedora Everything installation.
# Configures the existing user — no new user is created.


DOTFILES="https://github.com/sekigetsu01/fedora-dotfiles.git"
PROGSFILE="https://raw.githubusercontent.com/sekigetsu01/SFAI/main/static/progs.csv"
BRANCH="main"

export TERM=ansi


pkg()  { dnf install -y "$1" >/dev/null 2>&1; }
die()  { printf "%s\n" "$1" >&2; exit 1; }
info() { whiptail --title "SFAI" --infobox "$1" 8 70; }

get_target_user() {
	if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
		printf "%s" "$SUDO_USER"
	else
		ls /home | head -n1
	fi
}


welcome() {
	whiptail --title "Welcome to SFAI!" \
		--msgbox "Welcome to Sekigetsu's Fedora Auto Installer.\n\nThis script will automatically set up a full desktop environment on your existing Fedora installation.\n\n-Sekigetsu" 11 60

	whiptail --title "Before we begin..." \
		--yes-button "Ready!" --no-button "Go back" \
		--yesno "This script will configure the user account: '$TARGET_USER'\n\nDotfiles will be deployed to /home/$TARGET_USER.\nConflicting configs will be overwritten — personal files are left untouched.\n\nMake sure you have an active internet connection." 12 65
}

confirm_install() {
	whiptail --title "Ready to install" \
		--yes-button "Let's go!" --no-button "Cancel" \
		--yesno "Everything is set. The installation will now run automatically.\n\nThis may take a while. Sit back and relax." 10 60 \
		|| { clear; exit 1; }
}


configure_dnf() {
	info "Configuring DNF..."
	grep -q "^fastestmirror"  /etc/dnf/dnf.conf || echo "fastestmirror=True"        >> /etc/dnf/dnf.conf
	grep -q "^max_parallel"   /etc/dnf/dnf.conf || echo "max_parallel_downloads=10" >> /etc/dnf/dnf.conf
	grep -q "^defaultyes"     /etc/dnf/dnf.conf || echo "defaultyes=True"           >> /etc/dnf/dnf.conf
	grep -q "^color"          /etc/dnf/dnf.conf || echo "color=always"              >> /etc/dnf/dnf.conf
}

enable_rpmfusion() {
	info "Enabling RPM Fusion repositories..."
	pkg "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
	pkg "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
	dnf groupupdate core -y >/dev/null 2>&1
}

enable_flathub() {
	info "Enabling Flathub..."
	pkg flatpak
	flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1
}

system_update() {
	info "Updating system packages..."
	dnf upgrade -y >/dev/null 2>&1
}


_infobox() { whiptail --title "SFAI – Installing ($n/$total)" --infobox "$1\n$2" 8 70; }

dnf_install() {
	_infobox "dnf: $1" "$2"
	pkg "$1"
}

flatpak_install() {
	_infobox "flatpak: $1" "$2"
	flatpak install flathub "$1" -y >/dev/null 2>&1
}

pipx_install() {
	_infobox "pipx: $1" "$2"
	[ -x "$(command -v pipx)" ] || pkg pipx
	sudo -u "$TARGET_USER" pipx install "$1" >/dev/null 2>&1
	sudo -u "$TARGET_USER" pipx ensurepath >/dev/null 2>&1
}

copr_install() {
	repo="${1%%:*}"
	package="${1#*:}"
	_infobox "copr ($repo): $package" "$2"
	dnf copr enable -y "$repo" >/dev/null 2>&1
	pkg "$package"
}

repo_install() {
	package="${1##*:}"
	source="$(printf '%s' "${1%:*}" | tr ';' ',')"
	_infobox "repo: $package" "$2"
	case "$source" in
		repofile:*)
			dnf config-manager addrepo --from-repofile="${source#repofile:}" >/dev/null 2>&1
			pkg "$package"
			;;
		repofrompath:*)
			dnf install -y --nogpgcheck --repofrompath "${source#repofrompath:}" "$package" >/dev/null 2>&1
			;;
		*)
			die "repo_install: unknown source format '$source'"
			;;
	esac
}

git_install() {
	name="$(basename "$1" .git)"
	_infobox "git: $name" "$2"
	dnf install -y freetype-devel cairo-devel pango-devel wayland-devel \
		libxkbcommon-devel harfbuzz meson scdoc wayland-protocols-devel \
		ninja-build >/dev/null 2>&1
	tmpdir=$(mktemp -d)
	git clone --depth 1 -q "$1" "$tmpdir/$name" >/dev/null 2>&1
	meson setup "$tmpdir/$name/build" "$tmpdir/$name" >/dev/null 2>&1
	ninja -C "$tmpdir/$name/build" install >/dev/null 2>&1
	rm -rf "$tmpdir"
}

installation_loop() {
	([ -f "$PROGSFILE" ] && cp "$PROGSFILE" /tmp/progs.csv) \
		|| curl -Ls "$PROGSFILE" | sed '/^#/d' > /tmp/progs.csv

	total=$(wc -l < /tmp/progs.csv)
	n=0

	while IFS=, read -r tag program comment; do
		n=$((n + 1))
		comment=$(printf '%s' "$comment" | sed -E 's/(^"|"$)//g')
		case "$tag" in
			F) flatpak_install "$program" "$comment" ;;
			P) pipx_install    "$program" "$comment" ;;
			C) copr_install    "$program" "$comment" ;;
			R) repo_install    "$program" "$comment" ;;
			G) git_install     "$program" "$comment" ;;
			*) dnf_install     "$program" "$comment" ;;
		esac
	done < /tmp/progs.csv
}


install_dotfiles() {
	info "Installing dotfiles for '$TARGET_USER'..."
	tmpdir=$(mktemp -d)
	chown "$TARGET_USER":wheel "$tmpdir" 2>/dev/null \
		|| chown "$TARGET_USER":"$TARGET_USER" "$tmpdir"
	sudo -u "$TARGET_USER" git clone --depth 1 --single-branch --no-tags -q \
		--recurse-submodules -b "$BRANCH" "$DOTFILES" "$tmpdir" \
		|| die "Failed to clone dotfiles repo. Check the DOTFILES URL and your internet connection."
	sudo -u "$TARGET_USER" cp -rfT "$tmpdir" "/home/$TARGET_USER"
	rm -rf "$tmpdir"
}

configure_shell() {
	info "Setting default shell to zsh..."
	pkg zsh
	chsh -s /bin/zsh "$TARGET_USER" >/dev/null 2>&1
	sudo -u "$TARGET_USER" mkdir -p "/home/$TARGET_USER/.cache/zsh"
}

configure_system() {
	# Silence the PC speaker beep.
	rmmod pcspkr 2>/dev/null
	echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf

	# Allow non-root users to read kernel logs.
	mkdir -p /etc/sysctl.d
	echo "kernel.dmesg_restrict = 0" > /etc/sysctl.d/dmesg.conf

	# Create GnuPG directory with correct permissions.
	export GNUPGHOME="/home/$TARGET_USER/.local/share/gnupg"
	sudo -u "$TARGET_USER" mkdir -p "$GNUPGHOME"
	chmod 0700 "$GNUPGHOME"
}

configure_sudo() {
	echo "%wheel ALL=(ALL:ALL) ALL" \
		> /etc/sudoers.d/00-wheel-sudo

	echo "%wheel ALL=(ALL:ALL) NOPASSWD: \
/usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,\
/usr/bin/mount,/usr/bin/umount,\
/usr/bin/dnf upgrade,/usr/bin/dnf upgrade -y" \
		> /etc/sudoers.d/01-passwordless-cmds

	echo "Defaults editor=/usr/bin/nvim" \
		> /etc/sudoers.d/02-visudo-editor
}

create_directories() {
	info "Creating home directories..."
	for dir in Downloads Pictures github applications unsafe-pdfs cleaned-pdfs; do
		mkdir -p "/home/$TARGET_USER/$dir"
		chown "$TARGET_USER":"$TARGET_USER" "/home/$TARGET_USER/$dir"
	done
}

cleanup() {
	info "Cleaning up..."
	dnf autoremove -y >/dev/null 2>&1
	dnf clean all >/dev/null 2>&1
	rm -f /tmp/progs.csv
	rm -rf "/home/$TARGET_USER/.cache/zsh"
	sudo -u "$TARGET_USER" mkdir -p "/home/$TARGET_USER/.cache/zsh"
}


[ "$(id -u)" -eq 0 ] || die "Run this script as root (or via sudo)."

TARGET_USER=$(get_target_user)
[ -n "$TARGET_USER" ]       || die "Could not determine target user. Set \$SUDO_USER or run via sudo."
[ -d "/home/$TARGET_USER" ] || die "Home directory /home/$TARGET_USER does not exist."

dnf install -y newt >/dev/null 2>&1 \
	|| die "Failed to install newt (whiptail). Check your internet connection."

welcome         || die "Aborted."
confirm_install || die "Aborted."

configure_dnf
enable_rpmfusion
enable_flathub
system_update

for dep in curl git zsh pipx; do
	info "Installing dependency: $dep..."
	pkg "$dep"
done

create_directories
installation_loop
install_dotfiles
configure_shell
configure_system
cleanup
configure_sudo

whiptail --title "All done!" \
	--msgbox "Installation complete!\n\nLog out and back in as '$TARGET_USER' to launch your desktop.\n\n.t Sekigetsu" 10 65

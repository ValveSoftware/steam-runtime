#!/bin/bash

SCRIPT="$(readlink -f "$0")"
SCRIPTNAME="$(basename "$SCRIPT")"
BOOTSTRAP_SCRIPT="$(dirname "$0")"/scripts/bootstrap-runtime.sh
LOGFILE="$(mktemp --tmpdir steam-runtime-setup-chroot-XXX.log)"
CHROOT_PREFIX="steamrt_scout_"
CHROOT_DIR="/var/chroots"
BETA_ARG=""

# exit on any script line that fails
set -o errexit
# bail on any unitialized variable reads
set -o nounset

# Output helpers
COLOR_OFF=""
COLOR_ON=""
if [[ $(tput colors 2>/dev/null || echo 0) -gt 0 ]]; then
  COLOR_ON=$'\e[93;1m'
  COLOR_OFF=$'\e[0m'
fi

sh_quote() { local quoted="$(printf '%q ' "$@")"; [[ $# -eq 0 ]] || echo "${quoted:0:-1}"; }

prebuild_chroot()
{
	# install some packages
	echo -e "\n${COLOR_ON}Installing debootstrap schroot...${COLOR_OFF}"
	sudo -E apt-get install -y debootstrap schroot

	# Check if there are any active schroot sessions right now and warn if so...
	schroot_list=$(schroot --list --all-sessions | head -n 1)
	if [ $schroot_list ]; then
		tput setaf 3
		echo -e "\nWARNING: Schroot says you have a currently active session!\n"
		tput sgr0
		echo "  ${schroot_list}"
		echo ""
		read -p "Are you sure you want to continue (y/n)? "
		if [[ "$REPLY" != [Yy] ]]; then
			echo -e "Cancelled...\n"
			exit 1
		fi
	fi

	STEAM_RUNTIME_SPEW_WARNING=
	for var in "$@"; do
		dirname="${CHROOT_DIR}/${CHROOT_PREFIX}${var/--/}"
		if [ -d "${dirname}" ]; then
			tput setaf 3
			STEAM_RUNTIME_SPEW_WARNING=1
			echo -e "About to remove ${dirname} and re-install..."
			tput sgr0
		fi
	done

	if [[ "$STEAM_RUNTIME_SPEW_WARNING" == "1" ]]; then
		read -p "  This ok (y/n)? "
		if [[ "$REPLY" != [Yy] ]]; then
			echo -e "Cancelled...\n"
			exit 1
		fi
	fi
}

build_chroot()
{
	# Check that we are running in the right environment
	if [[ ! -x $BOOTSTRAP_SCRIPT ]]; then
		echo >&2 "!! Required helper script not found: \"$BOOTSTRAP_SCRIPT\""
	fi

	case "$1" in
		"--i386" )
			pkg="i386"
			personality="linux32"
			;;
		"--amd64" )
			pkg="amd64"
			personality="linux"
			;;
		* )
			echo "Error: Unrecognized argument: $1"
			exit 1
			;;
	esac

	CHROOT_NAME=${CHROOT_PREFIX}${pkg}

	# blow away existing directories and recreate empty ones
	echo -e "\n${COLOR_ON}Creating ${CHROOT_DIR}/${CHROOT_NAME}..."
	sudo rm -rf "${CHROOT_DIR}/${CHROOT_NAME}"
	sudo mkdir -p "${CHROOT_DIR}/${CHROOT_NAME}"

	# Create our schroot .conf file
	echo -e "\n${COLOR_ON}Creating /etc/schroot/chroot.d/${CHROOT_NAME}.conf...${COLOR_OFF}" 
	printf "[${CHROOT_NAME}]\ndescription=Ubuntu 12.04 Precise for ${pkg}\ndirectory=${CHROOT_DIR}/${CHROOT_NAME}\npersonality=${personality}\ngroups=sudo\nroot-groups=sudo\npreserve-environment=true\ntype=directory\n" | sudo tee /etc/schroot/chroot.d/${CHROOT_NAME}.conf

	# Add the Ubuntu GPG key to apt
	# Fingerprint 0x40976EAF437D05B5
	( cat <<'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQGiBEFEnz8RBAC7LstGsKD7McXZgd58oN68KquARLBl6rjA2vdhwl77KkPPOr3OYeSBH/vo
UsqausJfDNuTNivOfwceDe50lbhq52ODj4Mx9Jg+4aHn9fmRkIk41i2J3hZiIGPACY/FsSlR
q1AhBH2wZG1lQ45W/p77AeARRehYKJP9HY+1h/uihwCgrVE2VzACJLuZWHbDsPoJaNQjiFcE
AKbUF1rMyjd1xJM7bZeXbs8c+ohUo/ywSI/OIr8nOfUswy08tsCof1KU0JBGLBCn0lHAYkAA
cSr2pQ+k/odwdLQSjgm/JcUbi2ll16Wy7qFbUAUJ5xO+iP61vL3z4pJGcK1pMH6kBLA4CPBc
hJU/hh3f7vtX2oFdWw8tWqvmm/W7BACE7h0p86OP2G3ZJBjNYNQTK1LFYa+3G0spsVi9wl+I
h49ImPbSsUc2CSMAfDlGpYU8FuUKCgQnS3UZz6e0NwrHbZTHBy0ksRwT9jf7qSAEKEN2ECxf
wR5i1dU+Yi4owkqGPhTLAbwkYdZZMcqfGgTXbiU4uy8DzMH/VhqP5wxdwbQ7VWJ1bnR1IEFy
Y2hpdmUgQXV0b21hdGljIFNpZ25pbmcgS2V5IDxmdHBtYXN0ZXJAdWJ1bnR1LmNvbT6IRQQQ
EQIABgUCSul+HAAKCRA3PEl7GQyF8U8VAJ9W+Dmm4haDuCd+epJesWe5H70O1gCXXthnFKmw
9XJNeQ+EhXb/wU56WohGBBARAgAGBQJDvqyGAAoJEOiGpyRl+8eiA6YAoJBJoovXmOrRO+NZ
atyO9C84N2AyAJ92RvcluyDmWIzR50miFZ/KHN8YgYhGBBARAgAGBQJD+0vhAAoJEOTtaoD7
OAfbeFUAn1anJYKckgc1BUcfj9XySpqm1stDAJ9A3n+S60DJemuO1T5bay2fYdXikohGBBAR
AgAGBQJEyijsAAoJEP5Ube0ZLkFcYq4An1xfFjpOrHAi3qRMhKHLKQe6JrsqAJ0dhiW75qSH
w9gECUXhG8aUiSqbKIhGBBARAgAGBQJFB8LqAAoJEFsYwIFsM98IOwYAoI7fXecCWG78WCDI
h3sgbzJe0JrZAKC5YjpYKnS/iPIAgDYsr/Mps2UNwIhGBBARAgAGBQJFG87gAAoJEOAvm200
Cu2ojQsAniK/C2BT2DqGfpOxt6PNpulLsksAAJ4soGQt8/KYleVukKPOxq/2ol1mEYhGBBAR
AgAGBQJFG88wAAoJEJEDtXmH5IZfPw4AnRq6zzS4kPG2V+VQMPUHWIRw70QxAKCUx/LKzlpu
j+HpmJxOnZYiGn0gEIhGBBARAgAGBQJFG89CAAoJEAs5CGDLp2YZFpMAnAkUKAOyQHMh6oIQ
5EsC0toEkIueAJ4nOPN/gDwbVmFLf1j9iTstBgHdoYhGBBARAgAGBQJFG89gAAoJEC6slpCl
UOeEoiIAoNrOJLXHdJkg5LyniJUZVjjcpg7sAJ9169YUHcEtuYsoH3GysfTSxp80lYhGBBAR
AgAGBQJFZ9p8AAoJEJXiB61+S1yXVHwAnjHwcj8Y8hykc24nw9SUkq+NI5jVAJ43yCWq4Ic/
t31fIF7injWjRZ1sCohGBBARAgAGBQJFoAEpAAoJEFmBudKHS+vIKgoAn38pgc8EbAa5HhZH
xla6Muoi573YAJ9WTkaFMKPyyOQLbzfkE6ZZ0+JrfIhGBBARAgAGBQJFtB0dAAoJEH1G1jzt
47VlPgAAn2o4G6ymRXGP17CUm0U9l/MqRHKkAJ4z9ZWnD7avPtQdUAZdhmlaeqObBohGBBAR
AgAGBQJF+TG/AAoJED474O3/AxWA7l8AoMR1TBoaXqx3ylLY3l/4V2bbkRZBAJ0Tyn0Wyr5D
aUDabexsSAfeBr7M8YhGBBARAgAGBQJGrvadAAoJEPbdMwIQ+kzRfJ4An0IZnUw0dRiwm/Zl
2nM+p1zbcRboAJ0QN+TkyeQBhfaL16gQ9qugxE1zH4hGBBARAgAGBQJIIH/NAAoJEHgy30BN
oi3+O8gAoKXEz9CLobSvgrS0BahsJk93YBCfAJ9nLCQAOTKejH4QgKgpKgziCNdNdohGBBAR
AgAGBQJKR8XOAAoJEMu8siKtrSrCJIQAn3yiDESkQzzuqy/Qv2MTuXvaJs8LAKDRu1BieX0E
hzeCMpNulx4RsPsTVIhGBBARAgAGBQJKWiF/AAoJEKBj5RB4CquwosQAn0fzrKBrS3Cwg/8G
AUPhkPJAa/k/AJ96PPFdNVirfSu3Pm+W+VYnYFlK24hGBBARAgAGBQJK14lcAAoJEO4XEi2w
eCC7CiQAn0mJtQcnwv6gIUYK521Hib+ySdqPAJ9LovbihW39I0AhlB2V+aPVSjOW7ohGBBAR
AgAGBQJK+SDvAAoJEF983kDxix2bSAkAmwVp0C3pxuKQFwBnKzKYp975deZyAJ9pyRJiUC9N
Xj/J+SSDfiobB8xIQohGBBARAgAGBQJLnV4BAAoJELaF/8v1ph3IKhwAn0D7whlVdLthAAVz
3XTvhDy43ia0AJ0TMHFiTf05E5VX3cJMnu4kNM21uIhGBBARAgAGBQJLnV4NAAoJEK2TkXqe
2MfqWC8An3p+mcPuOBhTXcbFTPTcimirEBp/AKCglxh58POp/Ge0x6d6eS0r3tiD04hGBBAR
AgAGBQJLxAIGAAoJEOX3G1zkL/TwYfEAnjLNXClc4ZblJstkuh/qKlRWsWLAAJ9JF0MoU879
48YfYEmLE5b7G7RDSohGBBARAgAGBQJMIipDAAoJEBo87FlhbpS2BA8AnjXMkHAFBur07+id
2j0Bl+NwiZIMAJ4l8t3qlh5rmkgDxU9/8f3fiJkzqohGBBARAgAGBQJMjP2/AAoJEFXf5aQA
2rj0w34AoLPXroTWWTwCtbXz89cWSHMvTAjCAJ0V4D0ge0d65bz4FJcoyxw4cV2s3ohGBBAR
AgAGBQJMuprtAAoJEIX3JjEnociaLrUAoJUx3N7v7E0mNkalxeCJjxdujXOzAKCBCtNPqxuJ
M0fN4QShs12s+ERIr4hGBBIRAgAGBQJJmIU8AAoJEBvYl6El+lxWBn8Anj48qGf14uyUV4CG
mO5grGxc97+jAKC9IzKHz3Aw4mXWWq/vbEWOFDNdDIhGBBMRAgAGBQJCnYW+AAoJEDBrVUTG
kTz2DgsAn1Nj2XIPe7x5deJUTXXPDbSW8iieAJ9R8uE4T6gsyZQDCgKwKlVPE2GdG4hGBBMR
AgAGBQJCnZy/AAoJEFDXJjzhHXgTXP0AoIbYjZ6denuugGIiixWLvqHHgN32AKCzbWEam9Cq
i4uzo7P1NtDgI6qtP4hJBBARAgAJBQJFm3DAAgcAAAoJEAeNJY2yIK3GIoEAn0ovsu2RmJU1
yPyQkn27j5BfTQuwAKCElUmmNcLlDgR4Z/LObgwgJ/YxWohJBBARAgAJBQJIHzSLAgcAAAoJ
EAHicSIQ7QdJkvsAoMxVCKIU6h0LcdXivpy5cyOSw6GuAJ40WCEaMq6m06hHZj0F4y8WfHTC
oIheBBARCAAGBQJMImjCAAoJEOvvgzFXGVgw13oA/iZ1ISi/+OAq21wHryd28Qw2/aLauZUI
expEbR+3Dh2CAQCizd0ZeYRlHCEpPUI6uFt4zfCyuZkCcSDFHTuGNIu9uIheBBARCAAGBQJQ
FXKiAAoJENf+iug0FDwCf1IA/3d9euMACXVCDXtdg7w+cnW7i8OnyHAuqGcqstHkmgE+AP95
EsvOlYmFpJk4n1B8orbiqumHAMq+lx2AwTqTq2/0XYheBBMRAgAeBQJBRJ8/AhsDBgsJCAcD
AgMVAgMDFgIBAh4BAheAAAoJEECXbq9DfQW1JM0An1PBEEj391ceqzLHkuRas/HI7YfvAJ9c
NjvsefBIre1OonMLiboq4N1GF4h1BBARCAAdFiEEFcG2krcS3EvwPMG6yXLv/be2aooFAlra
4b8ACgkQyXLv/be2aor7fwD5AYxdZpCBNzHzhSKn3y/acVTcgr4l74Odx9oW++fDMqEA/0KR
8dZAiV6uBvu5vHehS+LHzjQI7O7nwp2RDjvLRLQ2iHUEEBEIAB0WIQQVwbaStxLcS/A8wbrJ
cu/9t7ZqigUCWtzp0AAKCRDJcu/9t7ZqirkLAP9P43UppJrfbhJhN6xZ4kyifYEYD+1sUjOR
pJIT4d0v4QEAg2osP/GWLvag0s0rWNiZXhFQqQK+DUkTlL8JSr0mr2qJARwEEAECAAYFAkm4
6xEACgkQ9oeK7Kuu7mag7QgAummJNQ6K62Wn5I3ww76QqL0XSap6dqv4DE27zJYi9z5K/C9s
69Potq2rboNySxKdJ9Yq4X+sr1VS3ZoqL4fcilImBPeTiOJD1Y8HWYmUZD6InbCf41GIbQ/x
LFanCkqSqLrAbF5y43cW94eFid1InrMLjOxRonZuCcsrYq7heL0KGrPdPOZNbFDiJ4QAe9dH
fDlY04z3QRPzQSVtdnuz9SB68CwZ/oTuaxVSkXPk/m7JWMgWnZUS84xAV8lLfxGLH7eBuaas
FhwJzOdN7dXWEuTuxK3GepiSlGuWTsFMX+zIcvqj9wWGRsFCI/IvoQYnPoarmAEVJAGBmOtQ
j3LzVYkBHAQQAQIABgUCScbwLAAKCRD2h4rsq67uZhatB/9i0COWN+b1ELjpdSth3jo5Mk/B
tBWRIry6CbP9oZRx5bFS83xLwh5jcI/sozRMESSOov6t89eBQeoQ4ca6gMcs/JVeoKyNwX/k
1V4vgiGwOKw5mfUvzjzbDD4UFl3eLtR9fDBcCy8FbxMcg9teaq9loCrHQkExM8HVac8Y0ptr
CPM578oCdLfbqrztldyifiZPks1ei3v6TlgMTM8JY6iFI4oJIkhYU20U3F3dF1g6K+sIOqgy
TdqOmeU+OP1NC9SGgTn1MinwrqWz7opwhLou6UbEcnagvTHRIHK34mLPcBazVkzo1TOKs4Ry
cXa+IgLDmKgk8Bl3PYofM0VBEUPCiQEcBBABAgAGBQJNUeWFAAoJEBwrtoQ2Ia06rQkH/1fF
MuT8rKgfd1uejWRupxlBXDiIxmHiWErNonhqsPk6CHxKke0XqQDXZEPAcasrO+qwoS0Cmw98
ujKlk9Qm/lItUwSnxbCkqjMhs90R8+tyyHU4Zf/awxKmj6Jp1XXLlrUFaviWW/v6n9Eb5y8g
U1P1fawp8Hj6mgkm+7e4bdXu8alYyposPgcFFd1xL06evxWrp3/UhbYw0w9oVrHPQhkteIiP
QgQohnhCeeUMpwQRcWxCP5lcxsszoDzl3o6wY79LvjuMjIrtIENGxjHGLv9P8aXxElXP+ZV9
+f0yeudi7lrrrWsWaTsNlD1RyQVOnerkarpdAfMLiIKfsaOO2lGJARwEEAECAAYFAlBZ7BQA
CgkQqxCci3grVM0MFwgAkLqUcoHpGhabd79Y4A0r/93TtJjXiG6CaVjUyS/kDbPO2amswNGT
QkgeWceQ03kG+fVMDaM19k4pLWrGff4M6Mw/fL/M6CTlWk+9hOYp8ZhH54OwsTRvoYHuftqt
2eIq0DiRCai8QxZAxnRx9eY0868cKVw4fEeZQDn0QFjFNV1aw1r9vASRQONjaktfK1+OumkC
YxYFndpEPmKY2SWv1PAqza3NyMzh81bjQPJ0GuZ2yH9J13RWSKk5p2eWuj6PxvR7IW7TqMjn
Nfa84Ee8Xe0fOVUJwTgfE64ZX54wDCVJavVBAKxVk99ziEnOkjG/Nxp4/1krRe0ZWEncfVaz
EYkBHAQQAQIABgUCUK6PPwAKCRDnV9Ldju+zE086B/wMklak42lKspNsgQg3fuJLx0GcFVDu
4n7rFu3hLE/RguNHFC+bYhIhO0+XeMur5tuvWvs0RNVSHFR6Rx+oAGLtNtGDZ2ilA1eEjkFO
KeEywQeGbFhGNxkbosoZK9G6cJrFgo7a+15zRPKJcgkARBs/63kOWDensbws//J58sw3VM6A
AMqf3/wQnhJP3PKUh2gH+qcgEJJhrQnWQUn44Uv1Fizi8ky0Q3nipBEMMjenAV3nUsNOyjHy
+gr3UrpIse6M5qcgg7gvwGdTUwTaB/wQUJbS/cEblBuuu6jaJEra9sf1cP9koLmRGXW1I88O
DeT+/c4/v4R4zHswBtUZLIvhiQEcBBABCAAGBQJUU2i7AAoJEFy5uzsSFmSKJtQH/3RfRb1+
7Ls8DuY5byJz/vprP/xTEkZT6fiZVQizHMr5ebFNv+W1z65WHigNAPxA/WUVwjSq94O3PfX9
8AZrEaoeDFpfJa+lwWyUzotnQt83S9VKw0Vz14OOykK5am+VxiDfBVWREQC95gY/Ot31MLtX
MsMUOOP7rgRDFdSI0GcNnLVCtUJKhMPXtZ715Ah5aa5g8i1xuYC5eqGdWagA27KCYWGSBjok
k8JPww0nVIMPrT3kvvhI1DCLBmrhxo73hDfMca2WT2PhIs7MWjO/mBjpgwqFKRLf2RAtD35t
yOBoZc8o+71Q7ULmoY5lKPNKQNVcYuVAlmdsI8gd2e3ETu+JARwEEAEIAAYFAlq3Bd0ACgkQ
eRivLdN0XALOjAf8Dgh5kwEWPX+bGPaAn/IvnFbHuUElF1IRXYqnKDbbI9R6U8uimGE3TO0H
qvUONsldJ9x15pX/m/hkzLVi4PBXheyqGUEHGzUVgSvNmbh+iBifbytlb1C+7rYg8xi6C1ft
A1xg7BMniX96Zizm6R1nxz5R8ImkVuo2HrRAz1gioB0yLdPecM5XS1O5mAQDS5j6Lm+z4cVk
NyotCgD1ose5U+0QoOB5Z3/Uvf/EozDR4hB1ji8dwjWt82P+PQwhjNPSdOUxzuPd196Wojf3
BGkFJmY85odzxyJMV2TrMM+ZOIlkmXNkjwYUu1owDGJ2nILAstRprn1CCZJ+bemiVtddR4kB
nAQQAQgABgUCVzopvgAKCRCg8hPxRutYH6foC/987mpsixDm+26QfOj9x/CfB8TF9AYIyTQL
OY1PpilGBKHNebhFQZ5OPGT2ZWMAfJOIpDiqsH65w8PqXX0/M2jbIVGFwzV6dL35QTHTpNHh
/cCGbJDK2QCtk3QMdlOoUBpMjRsYWyYNmNPlQwWsMZJOAr8pDHnTiUbr7K4u+NTEPqVKCO+h
zbNQ98SJdEby9rHinekLRWDGAFn73YYhzhX3c8dgVZhBPMUfSo20bFbq63WdhOm/CHazA3Nc
iRYxide3hG+szQq1c5da89qPqThoPlqN7r/xKrPUC3fBq0f9lzbaKOTmbAaKF6tjEIV64ZVM
DgFEBJPeV3BzJoJ6Fs8lUvyU65Pmtz5Yso2Vl5Yv8VJ8TgcEBjOocl+1+/O2SlqCaTduvYHb
bsl3inrq3Nb3eZc89ScZL0QD1G69iODU6s+eq+aDVWZ/I9E9uNXVnXTzL9mP3P3tRpx7EjtC
YnTZtit1CCkHJT7zbWx0kPW/7BSxVmqn2YL1HelF+qy8fBaJAZwEEQEKAAYFAk6povwACgkQ
oPIT8UbrWB8LlAv+ILe5UtN/3Kbod/KSJVBJWrTqLQFo+8yykHzICxBzO5ZU+T6/1i4ze9tr
2m8bCVR7N09JhOMZZDFhIUCDUG68IBRnt7HwveZxiqnV46BzirakK9DWzLFAk1MCZTa1479H
I0ymVCAOnIIkCz3wylQp5cehsVON399DWvmQiRTqsX1T++JVsGdFTWmggLLaK/3IRIrp56en
0H5lQLth8CpR2GX/zoKAbem0hL83YsW7SBRMi5bzj+DyrVvqb6sqk4Wi0FYjgsfkabZv/LJJ
8W5hRB1V60GfA9fyg0/77GGLRLTbiv6XP20FoxAZrOeBbD9OGwtTpvSzfw4wvMGy922iFLRh
dAdJQFJV8BYYUCUueFmHOomv7YCtNNyjHCeUSTA3y6exCr2ulJhnb04s+jAPgOACDrV7sKSU
g17wAaWuNRiimufJM3qYBk1F0VX8lQpUE4/dnF+uZjDfGbvrKaV2GBOALJyucgDHX6vQ4DWg
LuHWW8ed5NNbvLm6sD5Wo5c1iQGiBBEBCgAMBQJMbWv0BYMB4TOAAAoJEP+UA7GDzxT5na0M
AJ0U5LFp+iNm1if5kGz18mEXx3UdIVp74dGwTTP3mLvfYVJj3Bm666FvOZLoZyKzYqJ1UsZR
uBZp5olWMelMvTeiR69CRNyMjH0fsFJ3ZMyy/Qh/ArIfc8Im3sDmus1XbnbFnToyBp3Y4DXx
EYnlPRp+Ve/59t9euvL7yUXm7k6ECl+P5h6d8dGRrEE3FzaZ8NsdOwelr9tSMhke5o2ZEWY4
54gLd/+0isr4Ra3FprqaY+3ZCHd1rqCfWrgUPV906RDMLkjmQTEN0LZWVuI8gZQJLyXBuHnJ
tg5SDb8gkIG+YrBsYCAKNX65ENun3eoABwtK0gzONQbc3hg65LC4JO6suMiDUYiHbB+M6OTj
zT4j/vy+Zf0aHq+dNoJtutCsLlE7agGA+PrR6gWwr1GmWxKErfcVZXwk4yWoRXCbmATYbUVU
9cmIm1wHiKbjUBw3shoLtuf/0I3pTKVCyhYGpu2+pgb8vm9k+7t8xWCRoJ595tZIM5mIbYZq
amP0WR+6E4kCHAQQAQIABgUCRzTGlQAKCRAL+4R/PycvWxSsEACwsZcN5n9AfJh9Yc+umH4A
sL3jGZuV9K7xD8FEPT1XI+KaehG1I0dnDBtOnfzKxVT0b2ajeWBDTsdA/pfGgQOvDjawtSmc
QJQym2vV7rqGXK+Ti6sxWMYSzgUKkDfBG4NRi4jgxykHWZHNiokRhnZsaX0xY34UYQTqgUcK
8lRQAQNWPt6cI3X6i4rD5Z+CKSLUGo9Yah9OuPYb+y3yGfYuEGCiYIO2dvXiBFIUe8g0750O
v3pCNVcaD35ZKvaIhV4gdLxBZY6ljCCK3XoMrRKBfGUgxcyRw2kOixqTrf0MXrDBFO9WgwZy
vk4Ru1QjbcY53Jf1FOtYIQKZRy1q32+mt3Hp7Sdthu32NiF5UHNMIwYK1zWlVK41yw8FTcUp
mUyrrIf0Ps85A8dqYpxl1GEYq1HS9Bp0q3dsxlA/bfWlQx0Kn1rIgyMuONfsQOgU7qIKp666
oFrSq6LPtnqcC9NaQYcdeN3nnmIiuRPPV+Cx6zTk/0EeR8+ac4fnlvfe/KinPncDvhXPpK60
5RNCLQxpcBg2xfQDnluM1vd+bou64sCQ5kBHXB9IzURxvmvJk/72QXqj3NIZxDayMbdvukYW
1DO3DNco1QI4jgi/3fYh4P073nDmiZdlVqFMZDw16wUd2YTCrr1oQY6rcTertDPWkCBmyPY3
7ouYTcufau50pYkCHAQQAQIABgUCRzTGlQAKCRAL+4R/PycvWxSsEACwsZcN5n9AfJh9Yc+u
mH4AsL3jGZuV9K7xD8FEPT1XI+KaehG1I0dnDBtOnfzKxVT0b2ajeWBDTsdA/pfGgQOvDjaw
tSmcQJQym2vV7rqGXK+Ti6sxWMYSzgUKkDfBG4NRi4jgxykHWZHNiokRhnZsaX0xY34UYQTq
gUcK8lRQAQNWPt6cI3X6i4rD5Z+CKSLUGo9Yah9OuPYb+y3yGfYuEGCiYIO2dvXiBFIUe8g0
750Ov3pCNVcaD35ZKvaIhV4gdLxBZY6ljCCK3XoMrRKBfGUgxcyRw2kOixqTrf0MXrDBFO9W
gwZyvk4Ru1QjbcY53Jf1FOtYIQKZRy1q32+mt3Hp7Sdthu32NiF5UHNMIwYK1zWlVK41yw8F
TcUpmUyrrIf0Ps85A8dqYpxl1GEYq1HS9Bp0q3dsxlA/bfWlQx0Kn1rIgyMuONfsQOgU7qIK
p666oFrSq6LPtnqcC9NaQYcdeN3nnmIiuRPPV+Cx6zTk/0EeR8+ac4fnlvfe/KinPncDvhXP
pK605RNCLQxpcBg2xfQDnluM1vd+bou64sCQ5kBHXB9IzURxvmvJk/72QXqj3NIZxDayMbdv
ukYW1DO3DNco1QI4jgi/3fYh4P073v//////////////////////////////////////////
/////////////////4kCHAQQAQIABgUCS6DimgAKCRC5byMArRHL7gOyD/9qGP546A1FKPZa
sXMKZyMO9Waom8LOkKjApY5R3Ze3Ww8m2DRPMG5B3yeH/7xkAVWhtga0Y5V49AE7248YLeFJ
jZ0ZJ5uU46X9kGJge5hNcw1jr5vAQePVHA7+yJQOAPcz2pIJ1XCNN1m8BAB9TN7ImYXkZZn9
RmaCAd9iop+LzLazgk3dHEqbuuTDWaobRSHxTUw4fTmxYThh5ngxA6T4Shq/4d9hvzYZs69O
WmdLT5E2kEsZbyqYbxkagd8+tJ48yljU5GPFOEusty9HAo3v6vc1yX1/t05ufAXeW5pUNRvV
lZld6VfhyQ+McP/PP3Gpz9/EkBicnlN/rxyFi6N2KGhJegKdsTO7/2ts7YuzZ2yhCqwCWUEJ
FfIad8rtWUkoQn03A2qrwGWiIiCg1z2rYPgThWrz2BEWh5xPlpMBdw/U6y+LU6VvddPyKYTf
thut8s8H07tbAFOk2tesaLJd9DSKf1d/JHB84IerVOil49hfIHu8L4hTbkYSHbBhinyIzErY
WaiLJ4O/s5tPEqHbnbkxu5yUFlHNwM48H1PofIGXXDO+klMpyVEuF8WOqTn3IoFUkehlC906
xVW4or1QeFLxjqG5a9QkE1huje/qmZHy+JprX0snPLN0e4rqdz2x/XYJYHLutzpU0pnyb0Zb
fwlY+YWCF35xmFBe+i9cy4kCHAQQAQIABgUCTR38LQAKCRC5byMArRHL7vkwEADBBa62NtQg
VZIN0eSXm9O+VQd7VBnpNbUkeEDradq/0ffd43nQf7C5cL7tjmL2Au0tcE4JhAz9kLFaYm/h
uV6IVmbbeLvLBPk1MjZuXp8MGyVhKLUMWJhSOi3ZUiL5XikkFlS4QiPhKBPX7nxPWlc2naMN
cWga7CZeL7F7gV+pImw5QCix8Lvx1p9NmaDHL7ftkx7Ooc2b4uh8vZJKQrnE/vFhcdoG1sEh
QaC+l964SJs3KTz8ozjITzLY85y3Jr9vBgJxKAoxJx3BDm+87xrXF8t456jKa45kLPjK/hLl
6Lo/1XoC2KHopt1/3oWhOvOZ7CQmXYDTJFPM7dir2EFeyUnr/wFHjI5QyFQbjem8zTBZIE1Q
CWfz+0CR0zUwpfGFvi2paPbBSTVRArF0qlTRfBs7P+nNikQk12pxIHb1sOL3wz0rijc1tbiv
xffjkYSbnKtmzbEgpEbroGPnmttSl5EaOb8+djpA3Fqw2/O2vecnyOGArk6LY++QUfcVttaP
l65uMx3a9M+Zz+lphrvxfNhpLG0G5V5QLeM7te3u0Q7u5Hbt3c1+V4B/+6wxzNwJRkl9Nm1X
HjZjtUM2BBZwiBz2xmlDhbCgWEsXPh+BnQXnKTE6pP5/mMT0ji78qDGKg+1HJl/3RhBzd8fy
UQ9kWb9xdVDdpR/7eNOKzkljZ4kCHAQQAQIABgUCWt/N1wAKCRCY5BffeM16qnq2EACsaib/
Ps8op/lueef2AOVXWbhDSjmapF3qEaxCU0I+qUpBEhjGEMPkh+UVC/wvoDjFXudag+I71Rbr
a4rKx4RJiPkLqvnse9Af3+JMqPGHa0VrvncSS5+R1L+rIMPnT8rkpbflG4pjwXJaUKUmd58b
U5jG+qYLT7otHp+PsHrgDWRcHPeW7asHuOvOqC858CUrKh4vaCDD0vkb10LgrJXFINbQeoVs
+txbkYoOQ5mVaVVrFHnRnOb1StYAf7xGf9BtAmbvo3PGB3Xh6KP8+UGcdctGYpN7XuNvTnlG
0hxfzdWQTq07xrmuFd5enNthUyq9hpz+g9g+s3Ai9//OcSGsjnniEl8mHU6Z0T2G+diwEM2O
SYIcL5HR6hiC/Stq5i8kQ6Wqsi/nZmruIZO/mD6b+WRicMDdkwSV40fNuBrtt2H1NHY4cX2F
tXir4yjtUpAsHra8aFXWBHWsPErFZcsLzyJiFNYzYKEuqWLoeRFfs234Nr92yQm0a4WUZ0z7
E21YdLE1blzcjMHcwKtEzEKcGkwz8vHIb22a4wuuoNfxd/XTg44h6d0I4eriWBZ/xyqtEJVO
6qNYdmVhAzQWDNe0w0YscBREo/g3MHhgmN3UCjccRPUVgy4g7XYy5hNF8dGcrcP7/1e0KQ23
KqWmJBxcTH0QOEWf0RYOhiV3I0KXnokCHAQQAQgABgUCSnQF2QAKCRA5NYfZfYZQCzReD/sG
jBTk9758+mzsbDI+/9DmitLaOZf2a834vnVXLqyKAdWe2a7MQ/nuvMZ5BXrnReakDczzV/Aw
l5TfFTGAe2kSIWNLHRhnkAeAVAj0hFOmVCB4rXEZi21fffZF7SdnCzKw1Kmxjxdk556nY6sI
pyvFYU1xOa3Mwq2FtdcL6gfP4YB1Ax5FL2coy/T0lolLQVT1YxYC5khvaipWO1wBMfYTQmTv
hKW3th9wy1JWz2zkMYcJpzXLNKzmO/qzrj97Bo8BJaBPFm/8NZcDXOldxl13fh0wBvjW1YZV
8On3ngdFZRvocOB9AleLYWWTtJv7DdYyXb0W5MQj5F+orNl+ZWg3DDc3Uqaja9KXqRyUYDIQ
euupA2Af9DNPayAndGVYb42z/ddaruy77dnfdD63Nj2uf8eIq33C7QyZAjmajmj6EPcR7BIs
VltLr6d9lbB3n+PMt3FBSN1cM+HoedvVFSiBCBEu1+CHHBJHGyyLYIbIwaq9jAurmdwnXn21
zUcVsHOIWcRkiU+Gl0C2l+hgdAg4LrnCAr+rAFWSDNNvDTToj6cQ2VgpVJgARbCwINYTdRFw
hXUjmpwnYrY7JUuaxYcvD1tnqQ+VQPlGKsio8XVBfqd9o6SEjljwn297pGScw1II52gENiV9
X0TVNXr5xhlbfeloP4TqgxuhPH3JR+kgp4kCHAQQAQgABgUCWriCBwAKCRBYhK1oeWe2lxjY
D/4sIZQgB658hERZ4smF7DtG+YSHX0nD7SEQHiMJKdo4JfnQd6fTe3WMpgBGTpi+5e8kNgvC
PFkVpnUVXJrghN3sVmXzGN8RGSbJQQWykcUJPuT7L4Bh8NoLy9g7oYGuuokxJbk5SgLg8UR5
VFGApf+E+2UUIBYH6rIwkCrUJn6dp0ZUUQoQL0g7m4RIeKa76QA3yQH/zEAmxJwx3t9pRoTG
dIWbFSZvTvQAd471JJ1ySv1xUJI2HbdWqtf73TbVGsTX91673uMUoCvtXaQQLKKVMM9cfZj+
22cAa6LPWImHwi268mUlCLkZL8hpbJA9FUOM2cl9zc2KOFBzXUXBEX9rgZBUgMos09DXoy6v
OIhVQOIMviNQAVLQV02WCe9axTNGh7AGr01j4CZmJSHBjldOH/m4cakHd018733e8o27xQvU
PezWe2QqCsgw0mZZ4GozhAJCUM/rWqqdEBaEFFUsRhOfhvRN0QB4BBNcqiIevECzkxQwCXN3
Eam1tECB5vc6WG+Z8SImvsFvd11wVN1w5A1u4eYTPOQOQbHCPoLBm2mWX5spCFOqFaKqvniH
z6+UmhhaI8jHIJW4HmGL+eV+U1+fFiPmk9ddYn7ETXDxNB/w7ZVr9Or8KRIGreWdwnTaHH8G
uAhO5IpWYP/2/PdWsmEhvVliI3xE+p5NK6gQwIkCHAQTAQIABgUCQVFn3wAKCRDXw/ExqyqR
9X3CEACPmxLNMcMh1gKZtly6ZMeWKapLzyb7Qd7qOQbmPoONCr/EZaDsH+y8b6Y8ITgr/Ngb
cIDQbSVOAkkpCDqBxSChClqIrbaAsbm2NU5BFFoTG74U0oX2S9JgVsTCmfQ4RKxE+Ot1LZFi
kaNj4Msc9oHTpj+FC8xIKHrtl4OYstPBAXMXREBQe3BT61T+Ce+uTuST/I8Oq2PncnrO4B/z
plcZGWYkJMNgn/JehiWbizPQTVcA2t3C1QaJzQ8XWAkh7tkCeoxW9EYLECs1PW2HzfC6mmMj
j+sasW21tBQ9vRxfJeFKY1q5EyKJf+WuOqOi6T0NfwLJVAb+ZOCOsosAwFk4n8ibcPfeM50R
YhppUBU6Y56PdLyzffNxYBRhumqD7XSLc7hJ9Vgfzy2YSeZfeapjbUHt+Qcc5VcX/j+wLN+3
oSToTnu8iHSLs+OetNYE7b92XvMnJlmju3Lh/r0HXFRk0KUFk9eBhaaHrzPlKDJ9jn838KZ+
ewfq7m8dJGmbTf02vggU1ESRqaReXYYI9sCuRkiSp0Z2tfUR9bD9+yd0eocrCs8YdchZZuhl
PVkPHjw/7zbl9UyDg3Zyvzsy/UrsT+GAePEnp55yIkWJzgZPX30NmFr7UazsVFe8Jr6w4Y//
0m5n79L5O/vWwg+ZGoOuvptIEf8TrIErPuO/jYY7yIkCMwQQAQoAHRYhBCbC4mSQ4cKZmlA6
JV+x60qkZkGHBQJa2t7OAAoJEF+x60qkZkGHcnsQAJDteKKrH2U7kOwGuER8f3y/sMSSWmLB
D0/xe5BtCJSwIqvMcYqKSjotx291EAKI1U6rcEJ8+E9x9wn2MoGifYBHqSBfvkXCBQ29Jdnu
oSqudLIBUsTH142KQAQ9anqK4nusPI2pkfBPk1UZbiS7PG/Fd9rRvIfLo/kicQnnIa4+FeSp
oxDTllfWqHy7w7RYsRtKLWoA2zXysUO0V/CTFugFYNHLNpTi/mmjypRX2HsUKFAIbF9zQETV
ZIOzzwV591ETwGyjXUfGIo9dtWV2npJYy7eAX+mFLi2t4IYNInPeUg1WJdbMT7mW0kDIYwSN
T0RmsbSVIObZJFtZ2r3B9iYp6TbuwDlyxPiikPLQKkAnZvoU0ubyedx0U5bOX4rhYWe+9RSQ
hu78Coi8kXOCoCEJ4LGs0mLHy83AiwlAdxrTNGNKhB9UG7xYezyJkGgCQDXWP5uxGq5KRkzZ
89QFlMIozZEZYAD3H3Pl0AxG9zd9HdQ9+vGq75/Q7ZtL9xhYALmsFsa3XKv/ANqStwlzS2O/
k8kcqlTNIUSetrqG6XbI8hHaB1IAN52w9hZidUk7j4CRldLfFssG0yGlIAJ8VGZocCR+b1Hs
y1RdxSKkqkF4Hx+tcPNUadY66r+NP6jMqDG3TIbaQ/kJoMUT0QTajasbOKwyY5j5PEDlPzsi
c5QpiQIzBBABCgAdFiEEZdIaGBBel/u053N0OHcu4P3Mq8UFAlrhCk4ACgkQOHcu4P3Mq8Wv
GA//Uql0CyUqaOp3U9NVxnY3zVWOb8/WL0wF32PNLBUnKBMrFz8dWyzs+Eg+RwMSjHR4MqVw
AX6HYPrnNOgcdKSssO9R+ryOhuQKcUbZjhxyph/cnwAPztg6m+Eluxrazukacy4OpLbeZg/0
gTDhXfOV+EriFZvkcJ26hE5kaNo2jFbyrkhcaX/OyjrWxHMufWGTpmp4sxHW87Le9HeX9QzM
vhgBRJ4RqK6wv9cvT11ML+oVLJXbeU7NesReNlnNcuw2sZO+aNtsaUnidD5519lzS8gdfs+P
aQuSRTknTFoyROqLd6oWyAKR3SJkn9JFuk18HY56MBsTEKviw+gdzjia2bIkIxp6FLrbvggn
0YkgaZqeeKO0YJmA/ubBwdkQJkWHHqfTVjFgHEa/t/aW9IcZD1aw0PABkkQg7rUfqpwr/olk
KRcnYIYQ2BBTIE4nUFh6lv5+QO7ccFO8c0RlV65dkL5lTipuzqvz4YAJM+IxQdwKVfOSEqC9
VQXVvZaM99eqcvBzgEyIf42rZ74tjLEjh+jGnWYL4jXAlUaQZY62ryGhK2SDtXmrCs12ca0t
wdtsobZUeckYd5kGMLFUhi3HL3mlrs3MccbDL1t6AUgucorPrW1KZeS1C1SXtdiQwCBmgVO2
yt8fdovGSMw6i+iR7Om7XrOAG31K75DbGrz0woOJAjMEEAEKAB0WIQR6kjzvmDp2DsnZxACn
RhDU5noZ8AUCWuDpawAKCRCnRhDU5noZ8BE5D/4ltry0RZiF1sCpfcfA6z3K9jW7zRX0ewha
GAeDaVdiY9FxODvNw47Iq10F12Jw6FNMsYuBKHUCpiFoG5WwGQtCVqN9vf9OiE03oSzY5eFg
uHA59uxRH3j/rroEvizFFq+tGotN3w3s2uhR6MimU5d/zFkcv9InAHUNtGKNGxhS005hRWRu
dUuxtRrR1FeS5TLeHn8EjzwALteKBYeJnB4Ol/hXibzlqFCo9ItmIXYa29wdRqdc8pQAVcAp
9Q4vb7tjVX2aMeabY44TXUPfBK+N1VDxDI0nVe2zgXN4NIHhE+3OosMADWURRs+ZZoAHzkc0
6XOK0ftGYENdWzRq/y4+6GCtvMy7FNuBAvbOPQQ7ruPWIJvIATU2sugJPG9IfK+fZILrRxya
EGYBBNCWAa193xX6ZkNPp4UTpyKHPc+oLeWRF5Nqst6E8L9WklGoXoUfShDss+AigR/HkmX1
5EJobKQDdboJ+Vv+8YQyIw2+q1KnOXuo/t3OQUG+38+nL6KtvtAPBB8LvFcfcTru7smDyGq/
U806TAib8TrEetkm+w2l+OVYI5hHOHfBv6wfXgJd2j9bOc2k9uY0flhlvKQgDFnE2T43oi0f
kSWSv8PCJz7gK17nJ9AeBoL/zsWbR+WMYnMFfu1LIJSdQHVwg6PU2m4GLMlgmiS7kCjgCbgs
SokCMwQQAQoAHRYhBM/eWGzQ2UtHehiBjipiFpjSPZI6BQJa2scjAAoJECpiFpjSPZI6k7UP
/0vNkhnyZYU1+LwkFVYc5VH4D3VGlJFRgS9iUMJa0RV8GJBa0F3J6IzPgcAW3AxC331UWoyR
Sh7Q4vB02WjBVzt2jFAJtRUkM7TS1K/KHlsnCX3zRBvy3JuS9HAJ7fyxi56xlOmMPasFBkYZ
k1UdK8Q7qm6by/fTMvitOsiF2fqeqcoy0RKk4Afho8vIcnDOFX473+YAK/UhkOnGKuGmmkRS
Pbm3bcm26gZ73xI4cB1u/AlDddnjxxgA7hM1n3+s1SJOwGZ4oVGgYFPfpCUSYeB/klG3PtXH
jOku8zmKDsJzmmlS4O4URIlH4CZdL/mkUuidx98cYBlSi2IqhxlSu2JnpCMTDvfsAtYpN1t9
AsxQ58eAJ6vGJokV28IXsj4B0tLkTWZ1Zg9xdVCFhQZNrRhCzPTUrQ1oIBlVFK1iYsIsgTpK
d8awsZXp8C9dDgD8/pLyVZW7JIvD3tCSFJEaFTQiEggQsUAjwV7qwsX8n332cqm4NIRaXexO
mFQrldUEq43NrrOVzx0UDNRguGUcb8cefbh5H0wKhypHzj7uK6+mlazoulPeiI99Vx0LhPas
6MsRCydwgLTG1XVo3V36qhFFL+xm69pYO1ypPFRudfVKwQNyAUNpNxM5N04AAoLFzBgERvar
oAVlyzEwn0WkbKUKC44+xbBlp+N4fli7EZNbiQIzBBABCgAdFiEE2yRz6OBlDn0D7eqc437a
8etPYLsFAlrdTMcACgkQ437a8etPYLtkGxAAlti/4UcA5IkVL9/Uc5+QrWAx0XTdQo2fP+t/
wfXqgf3nB6DdzO5xi4zxm3rfU61BDdZnpEoMKXygLcC6fNyUPRrnCFFjDs3qAb70VLyxIS5b
lGcX+Ry+hAc4F6dvGutFuHnMGD4Ox1oj8LbYjNAgFB0Eewn8eX7InBHr2NLdAxWhVfWEM6MR
1eVHmLciUkSc9LP5HJcvV0ompiXAJasx2AAlRN/AAw0axEtDW0aZ2TRisMAg+1gvDx2mz/zh
FxfqrlRMMWiYAimfDyjWUhXi6eHsacT2aglr0fzX4GEt3bn7u9MxkNhQpPcCJ8KI6wLc/aPC
e5eA8yHNJziwU/gv/3r6HZm+ObUOsFgf2KPd/j0TznklnsU36d0iZPRPpYZvsB5RH2/pYBPr
EUBF4ISzoL2PVeA3V7CoxltssmNvi8+bF7MYrA/LZCXLXsVMQSQFekLvahldLXADtAnM7AjG
uvhjA6j775w1NckdAMxZiG52PKK9BoKHhWqOVrSPfuYl0B62Gs9dJhrSnqDpqgdO1n6lKXW6
dV9KE7U478Ar8pC/pUa1LXOMIm24roNhzNVveuVD78NDRNw+MkeowOB1a1yWDAD601kdy+ND
5CHe7j15QPOzBYCbRt/m9o6YPNfXvpUeA2RsfteZLXLPkGVrgNN5ynnrbj7COiYIZ7OkK/aJ
AjMEEAEKAB0WIQTqN4t1mgDxVUw2wPnM/WEG8+jzoQUCWvC5fgAKCRDM/WEG8+jzoQP2D/wM
bVU/Z4ztSkfM04e+DSe4HbRDcBhQi+6AX4bi4OBA/r7rvHrV+Bu/u152o3HqNtP3U4mzufDQ
lbGMjbtlvVaBz/ZOJqmA+pbLZYklkFPA6jBfrWelou2RsnCb10HX3Suqccr9QHGrEnP66oP6
UR/HqVE2O/fi2qY43kE024UHBVk6BvqSyxBr6czLdJjU9L3+rW80av3quiaj6QIGjpSDGW6R
r4UX0kEkaPvEk+RuzdqwntqDf738t+Fix//swNs9VM3acPPpc1GIRo91/uZz+5mVbQfoRwF4
IasSwLbQsI8n0MrzpZGaIa36WZeKwFi6dg3q66PeNaZGjMyWYwa8LHmb+oGSUMqoMON8Lg8N
yI1rLY7/ijmyJmF6bEhNBIsi3kftwOShCj2eugAyUY10gHTS/EZ1HTC+sZRVAq0ftvEdJps4
oHa0szLbfinPbpslEcHpa8Hc3IZglV8qHCWZjM4iGuau4meYSgSf6ydtuzqTCyj8PFSJSnJY
408KfZ6ueR15JaNxmVDrUUfDUCDlwiPUeMo01bkbR6rgP8qr5Ixp7qBxLAXT3CZoyrhBngCe
sojzZaFFsnBxVSfFGkbM+teg5xwHYEhsyv+Eug4vx3SRkJzUm+P8+z73Zwd88Pe2+lS0LEqv
VWyVxlSzrNHCZrLcvesm/80RFUkmCnXTyrkCDQRBRJ9HEAgAyCW9H0vrTFHrmLZAbiTYKepm
GZFRpPJLHA6U2opa2iRSnN/xaaoDfze5Es7xb1N57VoXsoQwRReAWI/ueezSSugoYuVwtsL6
cTOS/nVqjotyvl1avTzXsuaW8KXY3Up5AOSkcgCJLQtOO4QVjXKiyLYQKI5qfqyBwtpWolVs
RR4hpgk6Jnw7Ug1MAYZ2lWhI++CS5lUqE/a4wiFireqCzqwHlKyERooAZgiIfeVnpQlQhUS7
K6bGk0+qQnUmSmjhLEjDLwpiJD1SjU08/xua/IYZp5ZtE5ss8cI76KrEfEyITjFfTyxWLPED
VgvD2LC10085aRCwz2ufxb+CJ4fRKwADBggAwvMMgLLYgDXByZ/lc+mDgkEW4yN6Dyki5pBk
x/8w7a75GU5Wshc9UW1g6nFBH0LWAKD4GWDapBcE3DX1w1PYS1IaLQe3JxPDDbGcg6dos7Or
94j8udqR0AxyVpNVs2W2tp6mShEUTgTG+6r+0J3Oyyi2eYCFrW3MZ/47dDLGQgEnrMcVM0JE
QYE9iL8972K+Jao0AivdI+GXDtJMWtUOCmd71V2k5lvedVhhAcbqLC9XDOsTbf7zhEwUQ2rg
OHLH0vxHr48y3fju5Px0HTc9cyi86nBdfTrMyB8bAXrRNmyYeq6f8TeATjpiIwTbquZRfkpI
1Ob03YhkDyPP+wVfPYhJBBgRAgAJBQJBRJ9HAhsMAAoJEECXbq9DfQW13FgAmwWNT7Ft7HuB
6/IZDb+aGqJ0RLgzAKCCpDKj7DVPDHoMosX7esXmd/UXdA==
=dd+v
-----END PGP PUBLIC KEY BLOCK-----
EOF
)| sudo apt-key add -

	# Create our chroot
	echo -e "\n${COLOR_ON}Bootstrap the chroot...${COLOR_OFF}" 
	sudo -E debootstrap --arch=${pkg} --include=wget precise ${CHROOT_DIR}/${CHROOT_NAME} http://archive.ubuntu.com/ubuntu/

	# Copy over proxy settings from host machine
	echo -e "\n${COLOR_ON}Adding proxy info to chroot (if set)...${COLOR_OFF}" 
	env | grep -i "_proxy=" | grep -v PERSISTENT_HISTORY_LAST | xargs -i echo export {} | sudo tee ${CHROOT_DIR}/${CHROOT_NAME}/etc/profile.d/steamrtproj.sh
	env | grep -i "_proxy=" | grep -v PERSISTENT_HISTORY_LAST | xargs -i echo export {} | sudo tee -a ${CHROOT_DIR}/${CHROOT_NAME}/etc/environment
	sudo rm -rf "${CHROOT_DIR}/${CHROOT_NAME}/etc/apt/apt.conf"
	if [ -f /etc/apt/apt.conf ]; then sudo cp "/etc/apt/apt.conf" "${CHROOT_DIR}/${CHROOT_NAME}/etc/apt"; fi  

	echo -e "\n${COLOR_ON}Running ${BOOTSTRAP_SCRIPT} ${BETA_ARG}...${COLOR_OFF}" 

	# Touch the logfile first so it has the proper permissions
	rm -f "${LOGFILE}"
	touch "${LOGFILE}"

	# The chroot has access to /tmp so copy the script there and run it with --configure
	TMPNAME="$(basename "$BOOTSTRAP_SCRIPT")"
	TMPNAME="${TMPNAME%.*}-$$.sh"
	cp -f "$BOOTSTRAP_SCRIPT" "/tmp/${TMPNAME}"
	chmod +x "/tmp/${TMPNAME}"
	schroot --chroot ${CHROOT_NAME} -d /tmp --user root -- "/tmp/${TMPNAME}" --chroot ${BETA_ARG}
	rm -f "/tmp/${TMPNAME}"
}

# http://stackoverflow.com/questions/64786/error-handling-in-bash
function cleanup()
{
	echo -e "\nenv is:\n$(env)\n"
	echo "ERROR: ${SCRIPTNAME} just hit error handler."
	echo "  BASH_COMMAND is \"${BASH_COMMAND}\""
	echo "  BASH_VERSION is $BASH_VERSION"
	echo "  pwd is \"$(pwd)\""
	echo "  PATH is \"$PATH\""
	echo ""

	tput setaf 3
	echo "A command returned error. See the logfile: ${LOGFILE}"
	tput sgr0
}

main()
{
	# Check if we have any arguments.
	if [[ $# == 0 ]]; then
		echo >&2 "Usage: $0 [--beta] [--output-dir <DIRNAME>] --i386 | --amd64"
		exit 1
	fi

	# Beta repo or regular repo?
	if [[ "$1" == "--beta" ]]; then
		BETA_ARG="--beta"
		CHROOT_PREFIX=${CHROOT_PREFIX}beta_
		shift
	fi

	if [[ "$1" == "--output-dir" ]]; then
		CHROOT_DIR=$2
		shift;shift
	fi

	# Building root(s)
	prebuild_chroot $@
	trap cleanup EXIT
	for var in "$@"; do
		build_chroot $var
	done
	trap - EXIT

	echo -e "\n${COLOR_ON}Done...${COLOR_OFF}"
}

# Launch ourselves with script so we can time this and get a log file
if [[ ! -v SETUP_CHROOT_LOGGING_STARTED ]]; then
	if which script &>/dev/null; then
		export SETUP_CHROOT_LOGGING_STARTED=1
		export SHELL=/bin/bash
		script --return --command "time $SCRIPT $(sh_quote "$@")" "${LOGFILE}"
		exit $?
	else
		echo >&2 "!! 'script' command not found, will not auto-generate a log file"
		# Continue to main
	fi
fi

main $@

# vi: ts=4 sw=4 expandtab

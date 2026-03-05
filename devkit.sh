#!/bin/sh -efu
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026  Alexey Gladkov <gladkov.alexey@gmail.com>

scr="$(realpath "$0")"
cwd="${scr%/*}"

PROG="${scr##*/}"
workdir=

is_command()
{
	case "$1" in
		clean|clean-all|list|help|version|init|check|upgrade|shell|run)
			;;
		*)
			return 1
			;;
	esac
}

a=
i="$#"
while [ "$i" -gt 0 ] && ! is_command "$a"; do
	a="$1"
	case "$1" in
		--root)
			export ROOT=1
			;;
		--workdir|--workdir=*)
			if [ -n "${1##*=*}" ]; then
				shift
				i=$(( $i - 1 ))

				workdir="$1"
			else
				workdir="${1#*=}"
			fi
			;;
		-h|--help)
			i=1; set -- - help
			;;
		-V|--version)
			i=1; set -- - version
			;;
		*)
			set -- "$@" "$1"
			;;
	esac
	shift
	i=$(( $i - 1 ))
done

NARGS=0
while [ "$i" -gt 0 ]; do
	eval "ARG${NARGS}=\"\$1\""
	eval "export ARG${NARGS}"
	NARGS=$(( $NARGS + 1 ))
	shift
	i=$(( $i - 1 ))
done
export PROG NARGS

exec make -f "$cwd/devkit.mk" ${workdir:+--directory="$workdir"} -- "$@"

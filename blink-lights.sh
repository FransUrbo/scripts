#!/bin/bash
#
# Usage: disk-blink [--off] /dev/sd???
#
# ACHTUNG!
# ALLES TURISTEN UND NONTEKNISCHEN LOOKENPEEPERS!
# DAS KOMPUTERMASCHINE IST NICHT FÜR DER GEFINGERPOKEN UND MITTENGRABEN!
# ODERWISE IST EASY TO SCHNAPPEN DER SPRINGENWERK, BLOWENFUSEN UND POPPENCORKEN
# MIT SPITZENSPARKEN. IST NICHT FÜR GEWERKEN BEI DUMMKOPFEN. DER RUBBERNECKEN
# SIGHTSEEREN KEEPEN DAS COTTONPICKEN HÄNDER IN DAS POCKETS MUSS. ZO RELAXEN
# UND WATSCHEN DER BLINKENLICHTEN.
#
function usage
{
        cat <<END

Usage: $0 [--off] /dev/sd??

END
        exit 1
}

set -e -u

action=--set=locate

dev=$1
[ "${dev}" = --off ] && { action=--clear=locate; dev=$2; }
[ -b "${dev}" ] || { echo 1>&2 "${dev}: not a block device"; exit 1; }

sasaddr=$(
        lsscsi -tg | 
        sed -rn 's/.*sas:(0x[[:xdigit:]]+).*'"${dev//\//\\/}"'[[:space:]].*/\1/ p'
)       
[ "${sasaddr}" ] || { echo "${dev}: SAS address not found"; exit 1; }

#
# Scan all the enclosures for our SAS address
#
for encldev in $(lsscsi -tg | awk '$2 == "enclosu" { print $5 }')
do
        #
        # Note: we discard errors from sg_ses as, at version 1.64 20120118,
        # it prints an error on some enclosures like:
        #
        #  $ sg_ses -j /dev/sg45 > /dev/null
        #  join_work: oi=6, ei=255 (broken_ei=0) not in join_arr
        #
        # See Also: http://thread.gmane.org/gmane.linux.scsi/81514
        #
        slot=$(
                sg_ses -j "${encldev}" 2> /dev/null | 
                egrep "^Slot |^\s+SAS address:" | 
                grep -B1 ${sasaddr} | 
                awk '/^Slot/ { print $2 }'
        )       
        [ "${slot}" ] && break
done
[ "${slot}" ] || { echo 2>&1 "${dev}: enclosure/slot not found"; exit 1; }

#
# Light 'em up
#
sg_ses -D "Slot ${slot}" "${action}" "${encldev}"

exit 0
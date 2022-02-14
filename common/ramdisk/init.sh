#!/bin/sh

# Copyright (c) 2021-2022, ARM Limited and Contributors. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# Redistributions of source code must retain the above copyright notice, this
# list of conditions and the following disclaimer.
#
# Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# Neither the name of ARM nor the names of its contributors may be used
# to endorse or promote products derived from this software without specific
# prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

#Mount things needed by this script
/bin/busybox mount -t proc proc /proc
/bin/busybox mount -t sysfs sysfs /sys
echo "init.sh"

#Create all the symlinks to /bin/busybox
/bin/busybox --install -s


#give linux time to finish initlazing disks
sleep 5
mdev -s

if [ -f  /lib/modules/sbsa_acs.ko ]; then
  #Case of SR
  echo "Starting drivers for SR"
  insmod /lib/modules/xhci-pci-renesas.ko
  insmod /lib/modules/xhci-pci.ko
  insmod /lib/modules/nvme-core.ko
  insmod /lib/modules/nvme.ko
fi

sleep 5

RESULT_DEVICE="";

#mount result partition
cat /proc/partitions | tail -n +3 > partition_table.lst
while read -r line
do
   # do something with $line here
   MAJOR=`echo $line | awk '{print $1}'`
   MINOR=`echo $line | awk '{print $2}'`
   DEVICE=`echo $line | awk '{print $4}'`
   echo "$MAJOR $MINOR $DEVICE"
   mknod /dev/$DEVICE b $MAJOR $MINOR
   mount /dev/$DEVICE /mnt
   if [ -d /mnt/acs_results ]; then
        #Partition is mounted. Break from loop
        RESULT_DEVICE="/dev/$DEVICE"
        echo "Setting RESULT_DEVICE to $RESULT_DEVICE"
        break;
        #Note: umount must be done from the calling function
   else
        #acs_results is not found, so move to next
        umount /mnt
   fi
done < partition_table.lst

rm partition_table.lst



if [ ! -z "$RESULT_DEVICE" ]; then
 echo "Mounted the results partition on device $RESULT_DEVICE"
else
 echo "Warning: the results partition could not be mounted. Logs may not be saved correctly"
fi


#linux debug dump
mkdir -p /mnt/acs_results/linux_dump
lspci -vvv &> /mnt/acs_results/linux_dump/lspci.log

mkdir -p /mnt/acs_results/fwts

#Check for the existense of fwts test configuration file in the package. EBBR Execution
if [ -f  /bin/ir_bbr_fwts_tests.ini ]; then
 test_list=`cat /bin/ir_bbr_fwts_tests.ini | grep -v "^#" | awk '{print $1}' | xargs`
 echo "Test Executed are $test_list"
 /bin/fwts `echo $test_list` -f -r /mnt/acs_results/fwts/FWTSResults.log
else
 #SBBR Execution
 echo "Executing FWTS for SBBR"
 /bin/fwts  -r stdout -q --uefi-set-var-multiple=1 --uefi-get-mn-count-multiple=1 --sbbr esrt uefibootpath > /mnt/acs_results/fwts/FWTSResults.log
fi

sleep 2

if [ ! -f  /bin/ir_bbr_fwts_tests.ini ]; then
 #Run Linux BSA tests for ES and SR only
 mkdir -p /mnt/acs_results/linux
 sleep 3
 echo "Running Linux BSA tests"
 if [ -f  /lib/modules/bsa_acs.ko ]; then
  #Case of ES
  insmod /lib/modules/bsa_acs.ko
  /bin/bsa > /mnt/acs_results/linux/BsaResultsApp.log
  dmesg | sed -n 'H; /PE_INFO/h; ${g;p;}' > /mnt/acs_results/linux/BsaResultsKernel.log
 elif [ -f /lib/modules/sbsa_acs.ko ]; then
  #Case of SR
  insmod /lib/modules/sbsa_acs.ko
  /bin/sbsa > /mnt/acs_results/linux/SbsaResultsApp.log
  dmesg | sed -n 'H; /PE_INFO/h; ${g;p;}' > /mnt/acs_results/linux/SbsaResultsKernel.log
 else
  echo "Error : BSA or SBSA Kernel Driver is not found. Linux BSA or SBSA  Tests cannot be run."
 fi
fi

sync /mnt
sleep 3

exec sh

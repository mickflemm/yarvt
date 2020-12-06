BBL_PARTGUID="2E54B353-1271-4842-806F-E436D6AF6985"
LINUX_PARTGUID="0FC63DAF-8483-4772-8E79-3D69D8477DE4"
FSBL_TYPE=""
MEM_START=0x80000000

function target_usage () {
	pr_inf "\nTARGET: SiFive HiFive Unleashed (Freedom U540)"
	pr_inf "\nsifive-fu540 commands:"
	pr_inf "\thelp/usage: Print this message"
	pr_inf "\tbootstrap: (Re)Build unified images (osbi + Linux + rootfs)"
	pr_inf "\tformat_sd: (Re)Format an SD card for booting the board"
	pr_wrn "\t<arg>: The target SD card device, e.g. /dev/sdd (check out dmesg / fdisk -l)"
	pr_inf "\tflash_bootimg_osbi: (Re)Flash boot image based on OpenSBI (osbi + Linux + rootfs) (requires root)"
	pr_wrn "\t<arg>: The target SD card device, e.g. /dev/sdd (check out dmesg / fdisk -l)"
	pr_inf "\tqemu_test_osbi: Test the OpenSBI-based boot image on QEMU"
}

function target_env_check() {
	if [[ $# < 2 ]]; then
		usage
		exit -1;
	fi

	if [[ ${2} == "usage" || ${2} == "help" ]]; then
		target_usage
		echo -e "\n"
		KEEP_LOGS=0
		exit 0;
	fi

	# Command filter
	if [[ "${2}" != "bootstrap" && "${2}" != "format_sd" && \
	      "${2}" != "flash_bootimg_osbi" && \
	      "${2}" != "qemu_test_osbi" ]];
	      then
		pr_err "Invalid command for ${1}"
		target_usage
		echo -e "\n"
		KEEP_LOGS=0
		exit -1;
	fi
}

function target_env_prepare () {
	TARGET=${1}
	KERNEL_EMBED_INITRAMFS=1
	OSBI_PLATFORM="sifive/fu540"
	OSBI_WITH_PAYLOAD=1
	BASE_ISA=RV64I
}

function target_bootstrap () {
	build_linux
	build_osbi
}

function format_sd () {
	local SAVED_PWD=${PWD}
	local LOGFILE=${TMP_DIR}/fu540-format-sd.log

	if [[ ! -b ${1} ]]; then
		pr_err "Not a block device"
		return -1;
	fi

	pr_inf "Formatting sd card at ${1}"

	sgdisk --clear \
		--new=1:2048:67583 --change-name=1:bootloader \
		--typecode=1:${BBL_PARTGUID} \
		--new=2:264192: --change-name=2:root \
		--typecode=2:${LINUX_PARTGUID} \
		${1} &>> ${LOGFILE}
	if [[ $? != 0 ]]; then
		pr_err "Failed to format sd, check out ${LOGFILE}"
		return -1;
	fi

	partprobe &>> ${LOGFILE}

	cd ${SAVED_PWD}
}

function flash_bootimg_osbi () {
	local SAVED_PWD=${PWD}
	local LOGFILE=${TMP_DIR}/fu540-bootimg-flash.log
	local OSBI_INSTALL_DIR=${WORKDIR}/${BASE_ISA}/riscv-opensbi/
	local PART_GUID=$(sgdisk ${1} -i=1 | grep "Partition GUID code" | awk '{print $4}')
	local TC_INSTALL_DIR=${BINDIR}/riscv-newlib-toolchain
	PATH=${PATH}:${TC_INSTALL_DIR}/bin

	pr_inf "Flashing unified boot image (osbi + Linux + initramfs)"

	if [[ ${PART_GUID} != ${BBL_PARTGUID} ]]; then
		pr_err "Couldn't find bootloader partition"
		return -1;
	fi

	dd if=${OSBI_INSTALL_DIR}/fw_payload.bin of=${BOOT_PARTITION} status=progress \
	   oflag=sync bs=1M &>> ${LOGFILE}

	sync;sync
	eject ${1}

	cd ${SAVED_PWD}
}

function qemu_test () {
	local SAVED_PWD=${PWD}
	local QEMU_INSTALL_DIR=${BINDIR}/riscv-qemu
	local OSBI_INSTALL_DIR=${WORKDIR}/${BASE_ISA}/riscv-opensbi
	local LINUX_INSTALL_DIR=${WORKDIR}/${BASE_ISA}/riscv-linux
	local ROOTFS_INSTALL_DIR=${WORKDIR}/${BASE_ISA}/rootfs
	local BASE_ISA_XLEN=$(echo ${BASE_ISA} | tr -d [:alpha:])
	local QEMU=${QEMU_INSTALL_DIR}/bin/qemu-system-riscv${BASE_ISA_XLEN}
	local BIOS=${OSBI_INSTALL_DIR}/fw_payload.bin

	${QEMU} -nographic -machine sifive_u -cpu sifive-u54 \
		-smp cpus=5,maxcpus=5 -m 4G \
		-bios ${BIOS}

	cd ${SAVED_PWD}
	KEEP_LOGS=0
}

function qemu_test_osbi () {
	FSBL_TYPE="osbi"
	qemu_test;
}

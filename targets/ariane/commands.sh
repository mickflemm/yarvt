FSBL_TYPE=""

function target_usage () {
	pr_inf "\nTARGET: ETH Ariane machine"
	pr_inf "\nariane commands:"
	pr_inf "\thelp/usage: Print this message"
	pr_inf "\tbootstrap: (Re)Build unified images (bbl/osbi + Linux + rootfs)"
	pr_inf "\tbuild_ariane_mcs: (Re)Build ariane mcs file"
	pr_wrn "\t<arg>: Vivado installation directory (the one with settings64.sh)"
	pr_inf "\tflash_ariane_mcs: (Re)Flash ariane mcs file to the Genesys2 board"
	pr_wrn "\t<arg>: Vivado installation directory (the one with settings64.sh)"
	pr_inf "\tformat_sd: (Re)Format an SD card for booting the board"
	pr_wrn "\t<arg>: The target SD card device, e.g. /dev/sdd (check out dmesg / fdisk -l)"
	pr_inf "\tflash_bootimg_bbl: (Re)Flash boot image based on BBL (bbl + Linux + rootfs) (requires root)"
	pr_wrn "\t<arg>: The target SD card device, e.g. /dev/sdd (check out dmesg / fdisk -l)"
	pr_inf "\tflash_bootimg_osbi: (Re)Flash boot image based on OpenSBI (osbi + Linux + rootfs) (requires root)"
	pr_wrn "\t<arg>: The target SD card device, e.g. /dev/sdd (check out dmesg / fdisk -l)"
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
	if [[ "${2}" != "bootstrap" && "${2}" != "build_ariane_mcs" && \
	      "${2}" != "flash_ariane_mcs" && "${2}" != "flash_bootimg_bbl" && \
	      "${2}" != "flash_bootimg_osbi" && "${2}" != "format_sd" ]];
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
	BBL_WITH_PAYLOAD=0
	OSBI_PLATFORM="qemu/virt"
	BASE_ISA=RV64I
	ABI=imac
}

function target_bootstrap () {
	KERNEL_EMBED_INITRAMFS=1
	build_linux
	BBL_WITH_PAYLOAD=1
	build_bbl
	OSBI_WITH_PAYLOAD=1
	build_osbi
}

function build_ariane_mcs () {
	local SAVED_PWD=${PWD}
	local LOGFILE=${TMP_DIR}/ariane.log
	local SOURCES_DIR=${SOURCES}/ariane/
	local GITURL=https://github.com/pulp-platform/ariane.git
	local INSTALL_DIR=${WORKDIR}/ariane/
	local VIVADO_INSTALL_DIR=${1}
	local VIVADO_BOARD_FILES=${VIVADO_INSTALL_DIR}/data/boards/board_files/
	local TC_INSTALL_DIR=${BINDIR}/riscv-newlib-toolchain
	PATH=${PATH}:${TC_INSTALL_DIR}/bin

	pr_ann "Ariane core mcs file"

	if [[ ! -f ${VIVADO_INSTALL_DIR}/settings64.sh ]]; then
		pr_err "Invalid Vivado install directory"
		return -1;
	fi

	if [[ -z ${XILINXD_LICENSE_FILE} ]]; then
		pr_wrn "XILINXD_LICENSE_FILE variable not set, vivado will use the default license"
	fi

	source ${VIVADO_INSTALL_DIR}/settings64.sh

	# Keep makefile happy (it expects riscv-tools)
	export RISCV="${TC_INSTALL_DIR}"

	pr_inf "Checking out ariane sources..."
	get_git_sources
	if [[ $? != 0 ]]; then
		return $?;
	fi

	pr_inf "Preparing ariane sources..."
	cd ${SOURCES_DIR}
	apply_patches "ariane"

	pr_inf "Re-building bootrom..."
	cd ${SOURCES_DIR}/bootrom
	make clean &>> ${LOGFILE}
	make all &>> ${LOGFILE}
	if [[ $? != 0 ]]; then
		pr_err "\tBuild failed, check out ${LOGFILE}..."
		return -1;
	fi

	pr_inf "Re-building zero stage bootloader image..."
	cd ${SOURCES_DIR}/fpga/src/bootrom
	make clean &>> ${LOGFILE}
	make all &>> ${LOGFILE}
	if [[ $? != 0 ]]; then
		pr_err "\tBuild failed, check out ${LOGFILE}..."
		return -1;
	fi

	# Check if board files for genesys2 are installed
	if [[ ! -d ${VIVADO_BOARD_FILES}/genesys2 ]]; then
		pr_inf "Installing Digilent board config files..."
		cd ${TMP_DIR}
		wget https://github.com/Digilent/vivado-boards/archive/master.zip &>> ${LOGFILE}
		if [[ $? != 0 ]]; then
			pr_err "\tFetch failed, check out ${LOGFILE}..."
			return -1;
		fi
		unzip master.zip &>> ${LOGFILE}
		cp -a vivado-boards-master/new/board_files/* ${VIVADO_BOARD_FILES} &>> ${LOGFILE}
	fi

	pr_inf "Building ariane bitstream..."
	cd ${SOURCES_DIR}
	make clean &>> ${LOGFILE}
	make fpga &>> ${LOGFILE}
	if [[ $? != 0 ]]; then
		pr_err "\tBuild failed, check out ${LOGFILE}..."
		return -1;
	fi

	mkdir -p ${INSTALL_DIR} &>> ${LOGFILE}
	cp ${SOURCES_DIR}/fpga/work-fpga/ariane_xilinx.mcs ${INSTALL_DIR}/

	cd ${SAVED_PWD}
}

function flash_ariane_mcs () {
	local SAVED_PWD=${PWD}
	local LOGFILE=${TMP_DIR}/ariane-flash.log
	local INSTALL_DIR=${WORKDIR}/ariane/
	local VIVADO_INSTALL_DIR=${1}
	local TARGET_STRING=""
	local TARGET_ID=0
	local HW_SERVER_PID=0

	pr_ann "Ariane mcs flashing"

	if [[ ! -f ${VIVADO_INSTALL_DIR}/settings64.sh ]]; then
		pr_err "Invalid Vivado install directory"
		return -1;
	fi

	source ${VIVADO_INSTALL_DIR}/settings64.sh

	pr_inf "Starting hardware server..."
	hw_server &>> ${LOGFILE} &
	HW_SERVER_PID=$!
	disown

	if [[ ${HW_SERVER_PID} == 0 ]]; then
		pr_err "Hardware server failed to start"
		return -1;
	fi
	pr_dbg "Hardware server PID: ${HW_SERVER_PID}"

	TARGET_STRING=$(program_flash -jtagtargets | grep "Genesys 2")
	if [[ ${TARGET_STRING} == "" ]]; then
		pr_err "Genesys 2 board not found"
		{ kill ${HW_SERVER_PID} && wait ${HW_SERVER_PID}; } &>> ${LOGFILE}
		return -1;
	fi

	TARGET_ID=$(echo ${TARGET_STRING} | awk '{print $1}')
	pr_dbg "Target ID: ${TARGET_ID}"

	pr_inf "Flashing mcs file to Genesys2 board"
	program_flash -f ${INSTALL_DIR}/ariane_xilinx.mcs \
		      -flash_type s25fl256sxxxxxx0-spi-x1_x2_x4 \
		      -blank_check -verify -url tcp:localhost:3121 &>> ${LOGFILE}
	if [[ $? != 0 ]]; then
		pr_err "\tFlashing failed, check out ${LOGFILE}..."
		return -1;
	fi

	{ kill ${HW_SERVER_PID} && wait ${HW_SERVER_PID}; } &>> ${LOGFILE}

	cd ${SAVED_PWD}
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
		--typecode=1:3000 \
		--new=2:264192: --change-name=2:root \
		--typecode=2:8300 \
		${1} &>> ${LOGFILE}
	if [[ $? != 0 ]]; then
		pr_err "Failed to format sd, check out ${LOGFILE}"
		return -1;
	fi

	partprobe &>> ${LOGFILE}

	cd ${SAVED_PWD}
}

function flash_bootimg_bbl () {
	local SAVED_PWD=${PWD}
	local LOGFILE=${TMP_DIR}/ariane-bootimg-flash.log
	local BBL_INSTALL_DIR=${WORKDIR}/${BASE_ISA}/riscv-bbl
	local BOOT_PARTITION=$(fdisk -l | grep ${1} | grep "ONIE boot" | awk '{print $1}')
	local TC_INSTALL_DIR=${BINDIR}/riscv-newlib-toolchain
	PATH=${PATH}:${TC_INSTALL_DIR}/bin

	pr_inf "Flashing unified boot image (bbl + Linux + initramfs)"

	if [[ ${BOOT_PARTITION} == "" ]]; then
		pr_err "Couldn't find ONIE boot partition"
		return -1;
	fi

	riscv64-unknown-elf-objcopy -S -O binary --change-addresses -0x80000000 \
				    ${BBL_INSTALL_DIR}/bbl ${TMP_DIR}/bbl &>> ${LOGFILE}
	if [[ $? != 0 ]]; then
		pr_err "Unable to prepare binary, check out ${LOGFILE}"
		return -1;
	fi

	dd if=${TMP_DIR}/bbl of=${BOOT_PARTITION} status=progress \
	   oflag=sync bs=1M &>> ${LOGFILE}

	sync;sync
	eject ${1}

	cd ${SAVED_PWD}
}

function flash_bootimg_osbi () {
	local SAVED_PWD=${PWD}
	local LOGFILE=${TMP_DIR}/ariane-bootimg-flash.log
	local OSBI_INSTALL_DIR=${WORKDIR}/${BASE_ISA}/riscv-opensbi/
	local BOOT_PARTITION=$(fdisk -l | grep ${1} | grep "ONIE boot" | awk '{print $1}')
	local TC_INSTALL_DIR=${BINDIR}/riscv-newlib-toolchain
	PATH=${PATH}:${TC_INSTALL_DIR}/bin

	pr_inf "Flashing unified boot image (osbi + Linux + initramfs)"

	if [[ ${BOOT_PARTITION} == "" ]]; then
		pr_err "Couldn't find ONIE boot partition"
		return -1;
	fi

	riscv64-unknown-elf-objcopy -S -O binary --change-addresses -0x80000000 \
				   ${OSBI_INSTALL_DIR}/fw_payload.elf ${TMP_DIR}/osbi &>> ${LOGFILE}
	if [[ $? != 0 ]]; then
		pr_err "Unable to prepare binary, check out ${LOGFILE}"
		return -1;
	fi

	dd if=${TMP_DIR}/osbi of=${BOOT_PARTITION} status=progress \
	   oflag=sync bs=1M &>> ${LOGFILE}

	sync;sync
	eject ${1}

	cd ${SAVED_PWD}	
}

FSBL_TYPE=""

function target_usage () {
	pr_inf "\nTARGET: LowRISC SoC v0.6"
	pr_inf "\nlowrisc-0.6 commands:"
	pr_inf "\thelp/usage: Print this message"
	pr_inf "\tbootstrap: (Re)Build unified image (osbi + Linux + rootfs)"
	pr_inf "\tbuild_lowrisc_mcs: (Re)Build chip_top_new mcs file"
	pr_wrn "\t<arg>: Vivado installation directory (the one with settings64.sh)"
	pr_inf "\tflash_lowrisc_mcs: (Re)Flash chip_top_new mcs file to the Nexys 4 DDR board"
	pr_wrn "\t<arg>: Vivado installation directory (the one with settings64.sh)"
	pr_inf "\tcopy_bootimg_osbi: Copy boot image based on OpenSBI (osbi + Linux + rootfs) to SD Card"
	pr_wrn "\t<arg>: The target partition on the SD card, e.g. /dev/sdd1 (check out dmesg / fdisk -l)"
	pr_inf "\n\nINFO:"
	pr_inf "\tYou'll need to have a Java Development Kit (JDK) and iverilog installed"
	pr_inf "\tfor building the SoC. I've tested it with Vivado 2018.1, with 2018.3 it"
	pr_inf "\tfailed to compile. The SD card needs to be partitioned on MBR mode and"
	pr_inf "\tand its first partition, where the boot image will be, needs to be fat32"
	pr_inf "\tformatted."
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
	if [[ "${2}" != "bootstrap" && "${2}" != "build_lowrisc_mcs" && \
	      "${2}" != "flash_lowrisc_mcs" && "${2}" != "copy_bootimg_osbi" ]];
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
	OSBI_PLATFORM="qemu/virt"
	KERNEL_EMBED_INITRAMFS=1
	OSBI_WITH_PAYLOAD=1
	BASE_ISA=RV64I
}

function target_bootstrap () {
	build_linux
	build_osbi
}

function build_lowrisc_mcs () {
	local SAVED_PWD=${PWD}
	local LOGFILE=${TMP_DIR}/lowrisc-chip-0.6.log
	local SOURCES_DIR=${SOURCES}/lowrisc-chip-0.6
	local GITURL=https://github.com/lowRISC/lowrisc-chip.git
	local BRANCH=refresh-v0.6
	local INSTALL_DIR=${WORKDIR}/lowrisc-chip-0.6
	local VIVADO_INSTALL_DIR=${1}
	local VIVADO_BOARD_FILES=${VIVADO_INSTALL_DIR}/data/boards/board_files/
	local TC_INSTALL_DIR=${BINDIR}/riscv-newlib-toolchain
	PATH=${PATH}:${TC_INSTALL_DIR}/bin

	pr_ann "LowRISC SoC v0.6 mcs file"

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

	pr_inf "Checking out LowRISC sources..."

	# Recursive clone is going to bring in the universe for no
	# reason with all the mess with git submodules so we'll do
	# some manual work and fetch only the submodules we need	
	GIT_CLONE_RECURSIVE=0
	get_git_sources ${BRANCH}
	if [[ $? != 0 ]]; then
		return $?;
	fi

	cd ${SOURCES_DIR}
	GIT_CLONE_RECURSIVE=1
	get_git_submodule fpga
	if [[ $? != 0 ]]; then
		return $?;
	fi

	GIT_CLONE_RECURSIVE=0
	get_git_submodule rocket-chip
	if [[ $? != 0 ]]; then
		return $?;
	fi

	cd rocket-chip
	get_git_submodule chisel3
	if [[ $? != 0 ]]; then
		return $?;
	fi

	get_git_submodule firrtl
	if [[ $? != 0 ]]; then
		return $?;
	fi

	get_git_submodule hardfloat
	if [[ $? != 0 ]]; then
		return $?;
	fi
	GIT_CLONE_RECURSIVE=1

	pr_inf "Preparing LowRISC sources..."
	cd ${SOURCES_DIR}
	apply_patches lowrisc-chip

	# Check if board files for Nexys4 DDR are installed
	if [[ ! -d ${VIVADO_BOARD_FILES}/nexys4_ddr ]]; then
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

	pr_inf "Building lowrisc bitstream..."
	cd ${SOURCES_DIR}/fpga/board/nexys4_ddr
	make cleanall &>> ${LOGFILE}
	make boot &>> ${LOGFILE}
	if [[ $? != 0 ]]; then
		pr_err "\tBuild failed, check out ${LOGFILE}..."
		return -1;
	fi
	make cfgmem-updated &>> ${LOGFILE}
	if [[ $? != 0 ]]; then
		pr_err "\tBuild failed, check out ${LOGFILE}..."
		return -1;
	fi

	mkdir -p ${INSTALL_DIR} &>> ${LOGFILE}
	cp lowrisc-chip-imp/lowrisc-chip-imp.runs/impl_1/chip_top.new.bit.mcs ${INSTALL_DIR}/ &>> ${LOGFILE}

	cd ${SAVED_PWD}
}

function flash_lowrisc_mcs () {
	local SAVED_PWD=${PWD}
	local LOGFILE=${TMP_DIR}/lowrisc-flash-0.6.log
	local SOURCES_DIR=${SOURCES}/lowrisc-chip-0.6
	local INSTALL_DIR=${WORKDIR}/lowrisc-chip-0.6
	local VIVADO_INSTALL_DIR=${1}

	pr_ann "LowRISC SoC mcs flashing"

	if [[ ! -f ${VIVADO_INSTALL_DIR}/settings64.sh ]]; then
		pr_err "Invalid Vivado install directory"
		return -1;
	fi

	source ${VIVADO_INSTALL_DIR}/settings64.sh

	vivado -mode batch -source ${SOURCES_DIR}/fpga/common/script/program_cfgmem.tcl \
		  -tclargs "xc7a100t_0" ${INSTALL_DIR}/chip_top.new.bit.mcs &>> ${LOGFILE}

	if [[ $? != 0 ]]; then
		pr_err "Failed to write mcs file on board's flash"
	fi

	cd ${SAVED_PWD}
}

function copy_bootimg_osbi () {
	local SAVED_PWD=${PWD}
	local LOGFILE=${TMP_DIR}/lowrisc-0.6-bootimg-copy.log
	local OSBI_INSTALL_DIR=${WORKDIR}/${BASE_ISA}/riscv-opensbi/
	local TARGET_DIR=$(df | grep /dev/sde1 | awk '{print $NF}')

	pr_inf "Copying unified boot image (osbi + Linux + initramfs) to SD Card"

	cp ${OSBI_INSTALL_DIR}/fw_payload.elf ${TARGET_DIR}/boot.bin &>> ${LOGFILE}

	if [[ $? != 0 ]]; then
		pr_err "Unable to copy image, check out ${LOGFILE}"
		return -1;
	fi

	sync;sync
	eject ${1} &>> ${LOGFILE}
	cd ${SAVED_PWD}
}

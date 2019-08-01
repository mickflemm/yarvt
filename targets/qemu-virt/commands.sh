FSBL_TYPE=""

function target_usage () {
	pr_inf "\nTARGET: QEMU RISC-V Virt machine"
	pr_inf "\nqemu-virt commands:"
	pr_inf "\thelp/usage: Print this message"
	pr_inf "\tbootstrap: (Re)Build bbl + osbi + Linux + rootfs"
	pr_inf "\tbuild_bbl: (Re)Build the Berkeley Boot Loader"
	pr_inf "\tbuild_osbi: (Re)Build OpenSBI"
	pr_inf "\tbuild_linux: (Re)Build a defconfig RISC-V Linux kernel"
	pr_inf "\tbuild_rootfs: (Re)Build a minimal rootfs on initramfs"
	pr_inf "\trun_linux32_bbl: Run a 32bit QEMU instance with bbl+linux+initramfs"
	pr_inf "\trun_linux64_bbl: Run a 64bit QEMU instance with bbl+linux+initramfs"
	pr_inf "\trun_linux32_osbi: Run a 32bit QEMU instance with osbi+linux+initramfs"
	pr_inf "\trun_linux64_osbi: Run a 64bit QEMU instance with osbi+linux+initramfs"
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
	if [[ "${2}" != "build_linux" && "${2}" != "build_bbl" && \
	      "${2}" != "build_rootfs" && "${2}" != "bootstrap" && \
	      "${2}" != "build_osbi" && \
	      "${2}" != "run_linux32_bbl" && "${2}" != "run_linux64_bbl" && \
	      "${2}" != "run_linux32_osbi" && "${2}" != "run_linux64_osbi" ]];
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
	MEM_START=0x80000000
	OSBI_PLATFORM="qemu/virt"
}

function target_bootstrap () {
	BASE_ISA=RV64I
	build_linux
	build_bbl
	build_rootfs
	build_osbi
	BASE_ISA=RV32I
	build_linux
	build_bbl
	build_rootfs
	build_osbi
}

function run_linux () {
	local SAVED_PWD=${PWD}
	local QEMU_INSTALL_DIR=${BINDIR}/riscv-qemu
	local BBL_INSTALL_DIR=${WORKDIR}/${BASE_ISA}/riscv-bbl
	local OSBI_INSTALL_DIR=${WORKDIR}/${BASE_ISA}/riscv-opensbi
	local LINUX_INSTALL_DIR=${WORKDIR}/${BASE_ISA}/riscv-linux
	local ROOTFS_INSTALL_DIR=${WORKDIR}/${BASE_ISA}/rootfs
	local BASE_ISA_XLEN=$(echo ${BASE_ISA} | tr -d [:alpha:])
	local QEMU=${QEMU_INSTALL_DIR}/bin/qemu-system-riscv${BASE_ISA_XLEN}
	local BIOS=""

	if [[ ${FSBL_TYPE} == "bbl" ]]; then
		BIOS=${BBL_INSTALL_DIR}/bbl
	elif [[ ${FSBL_TYPE} == "osbi" ]]; then
		BIOS=${OSBI_INSTALL_DIR}/fw_jump.elf
	else
		pr_err "Unknown FSBL type"
		return -2;
	fi

	${QEMU} -nographic -machine virt -smp 2 -m 1G \
		-netdev user,id=unet,hostfwd=tcp::2222-:22 \
		-device virtio-net-device,netdev=unet \
		-net user \
		-object rng-random,filename=/dev/urandom,id=rng0 \
		-device virtio-rng-device,rng=rng0 \
		-bios ${BIOS} \
		-kernel ${LINUX_INSTALL_DIR}/Image \
		-initrd ${ROOTFS_INSTALL_DIR}/initramfs.img

	cd ${SAVED_PWD}
	KEEP_LOGS=0
}

function run_linux32_bbl () {
	BASE_ISA=RV32I
	FSBL_TYPE="bbl"
	run_linux
}

function run_linux64_bbl () {
	BASE_ISA=RV64I
	FSBL_TYPE="bbl"
	run_linux
}

function run_linux32_osbi () {
	BASE_ISA=RV32I
	FSBL_TYPE="osbi"
	run_linux
}

function run_linux64_osbi () {
	BASE_ISA=RV64I
	FSBL_TYPE="osbi"
	run_linux
}

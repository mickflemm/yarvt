function target_usage () {
	pr_inf "\nTARGET: QEMU RISC-V Virt machine"
	pr_inf "\nqemu-virt commands:"
	pr_inf "\thelp/usage: Print this message"
	pr_inf "\tbootstrap: (Re)build bbl + Linux + rootfs"
	pr_inf "\tbuild_bbl: Build the Berkeley Boot Loader"
	pr_inf "\tbuild_linux: Build a defconfig RISC-V Linux kernel"
	pr_inf "\tbuild_rootfs: Build a minimal rootfs on initramfs"
	pr_inf "\trun_linux_qemu: Run QEMU with the built bbl/kernel/initramfs"
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
	      "${2}" != "run_linux" ]]; then
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
}

function target_bootstrap () {
	build_linux
	build_bbl
	build_rootfs
}

function run_linux () {
	local SAVED_PWD=${PWD}
	local QEMU_INSTALL_DIR=${BINDIR}/riscv-qemu
	local BBL_INSTALL_DIR=${WORKDIR}/riscv-bbl
	local LINUX_INSTALL_DIR=${WORKDIR}/riscv-linux
	local ROOTFS_INSTALL_DIR=${WORKDIR}/rootfs
	local QEMU=${QEMU_INSTALL_DIR}/bin/qemu-system-riscv${BASE_ISA_XLEN}

	${QEMU} -nographic -machine virt -smp 2 -m 1G \
		-netdev user,id=unet,hostfwd=tcp::2222-:22 \
		-device virtio-net-device,netdev=unet \
		-net user \
		-object rng-random,filename=/dev/urandom,id=rng0 \
		-device virtio-rng-device,rng=rng0 \
		-bios ${BBL_INSTALL_DIR}/bbl \
		-kernel ${LINUX_INSTALL_DIR}/vmlinux \
		-initrd ${ROOTFS_INSTALL_DIR}/initramfs.img \
		-append "ro"
	cd ${SAVED_PWD}
}

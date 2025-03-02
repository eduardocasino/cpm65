from build.ab import simplerule, TargetsMap, filenameof, Rule
from tools.build import mkimd, mkcpmfs
from build.llvm import llvmrawprogram, llvmclibrary
from build.zip import zip
from config import (
    MINIMAL_APPS,
    MINIMAL_APPS_SRCS,
    BIG_APPS,
    BIG_APPS_SRCS,
    PASCAL_APPS,
)

COMMODORE_ITEMS = (
    {"0:ccp.sys@sr": "src+ccp", "0:bdos.sys@sr": "src/bdos"}
    | MINIMAL_APPS
    | MINIMAL_APPS_SRCS
    | BIG_APPS
    | BIG_APPS_SRCS
)


@Rule
def mkcbmfs(self, name, items: TargetsMap = {}, title="CBMFS", id=None):
    cs = ["rm -f {outs[0]}"]
    ins = []

    cmd = "chronic cc1541 -q "
    if id:
        cmd += "-i %d " % id
    cmd += '-n "%s" {outs[0]}' % title
    cs += [cmd]

    for k, v in items.items():
        cs += [
            "chronic cc1541 -q -t -u 0 -r 18 -f %s -w %s {outs[0]}"
            % (k, filenameof(v))
        ]
        ins += [v]

    cs += ["{deps[0]} -f {outs[0]}"]
    simplerule(
        replaces=self,
        ins=ins,
        outs=[f"={name}.img"],
        deps=["tools+mkcombifs"],
        commands=cs,
        label="MKCBMFS",
    )


llvmclibrary(
    name="libsd", srcs=["./libsd.S"], cflags=["-I ."], deps=["include"]
)

llvmclibrary(
    name="k-1013", srcs=["./k-1013.S"], cflags=["-I ."], deps=["include", "./k-1013.inc"]
)

llvmclibrary(
    name="pario", srcs=["./pario.S"], cflags=["-I ."], deps=["include"]
)

llvmclibrary(
    name="sdshield", srcs=["./sdshield.S"], cflags=["-I ."], deps=["include", "./sdshield.inc"]
)

llvmclibrary(
    name="kim-1-k1013", srcs=["./kim-1-k1013.S"], cflags=["-I ."], deps=["include", ".+k-1013"]
)

llvmclibrary(
    name="kim-1-sdcard", srcs=["./kim-1-sdcard.S"], cflags=["-I ."], deps=["include", ".+libsd"]
)

llvmclibrary(
    name="kim-1-iec", srcs=["./kim-1-iec.S"], cflags=["-I ."], deps=["include"]
)

llvmclibrary(
    name="kim-1-sdshield", srcs=["./kim-1-sdshield.S"], cflags=["-I ."], deps=["include", ".+pario", ".+sdshield"]
)

llvmrawprogram(
    name="bios-k1013",
    srcs=["./kim-1.S"],
    deps=["./kim-1.inc", "include", "src/lib+bioslib", ".+kim-1-k1013"],
    linkscript="./kim-1-k1013.ld",
)

llvmrawprogram(
    name="bios-sdcard",
    srcs=["./kim-1.S"],
    deps=["./kim-1.inc", "include", "src/lib+bioslib", ".+kim-1-sdcard"],
    linkscript="./kim-1-sdcard.ld",
)

llvmrawprogram(
    name="bios-iec-kim",
    srcs=["./kim-1.S"],
    deps=[  "./kim-1.inc", "include", "src/lib+bioslib", ".+kim-1-iec"],
    linkscript="./kim-1-iec.ld",
)

llvmrawprogram(
    name="bios-iec-pal",
    srcs=["./kim-1.S"],
    cflags=["-DPAL_1"],
    deps=["./kim-1.inc", "include", "src/lib+bioslib", ".+kim-1-iec"],
    linkscript="./kim-1-iec.ld",
)

llvmrawprogram(
    name="bios-sdshield",
    srcs=["./kim-1.S"],
    deps=["./kim-1.inc", "./parproto.inc", "include", "src/lib+bioslib", ".+kim-1-sdshield"],
    linkscript="./kim-1-sdcard.ld",
)

mkcpmfs(
    name="rawdiskimage-k1013",
    format="k-1013",
    bootimage=".+bios-k1013",
    size=256 * 77 * 26,
    items={
        "0:ccp.sys@sr": "src+ccp", "0:bdos.sys@sr": "src/bdos",
        "0:format.com": "src/arch/kim-1/utils+format",
        "0:format.txt": "src/arch/kim-1/cpmfs/format.txt",
        "0:imu.com": "src/arch/kim-1/utils+imu_k1013",
        "0:imu.txt": "src/arch/kim-1/cpmfs/imu.txt",
        "0:sys.com": "apps+sys",
        "0:pasc.pas": "third_party/pascal-m+pasc_pas_cpm",
    }
    | MINIMAL_APPS
    | MINIMAL_APPS_SRCS
    | BIG_APPS
    | BIG_APPS_SRCS
    | PASCAL_APPS,
)

mkcpmfs(
    name="rawdiskimage-sdcard",
    format="sdcard",
    bootimage=".+bios-sdcard",
    size=512 * 4096 * 16,
    items={
        "0:ccp.sys@sr": "src+ccp", "0:bdos.sys@sr": "src/bdos",
        "0:pasc.pas": "third_party/pascal-m+pasc_pas_cpm",
    }
    | MINIMAL_APPS
    | MINIMAL_APPS_SRCS
    | BIG_APPS
    | BIG_APPS_SRCS
    | PASCAL_APPS,
)

mkcpmfs(
    name="rawdiskimage-sdshield",
    format="k-1013",
    bootimage=".+bios-sdshield",
    size=256 * 77 * 26,
    items={
        "0:ccp.sys@sr": "src+ccp", "0:bdos.sys@sr": "src/bdos",
        "0:imu.com": "src/arch/kim-1/utils+imu_sdshield",
        "0:imu.txt": "src/arch/kim-1/cpmfs/imu.txt",
        "0:sys.com": "apps+sys",
        "0:pasc.pas": "third_party/pascal-m+pasc_pas_cpm",
    }
    | MINIMAL_APPS
    | MINIMAL_APPS_SRCS
    | BIG_APPS
    | BIG_APPS_SRCS
    | PASCAL_APPS,
)

mkimd(name="diskimage-k1013", src=".+rawdiskimage-k1013")

mkcbmfs(
    name="kim-1_cbmfs",
    title="cp/m-65: kim-1",
    items={"cpm": ".+bios-iec-kim"},
)

mkcbmfs(
    name="pal-1_cbmfs",
    title="cp/m-65: pal-1",
    items={"cpm": ".+bios-iec-pal"},
)

mkcpmfs(
    name="diskimage-iec-kim",
    format="c1541",
    template=".+kim-1_cbmfs",
    items=COMMODORE_ITEMS,
)

mkcpmfs(
    name="diskimage-iec-pal",
    format="c1541",
    template=".+pal-1_cbmfs",
    items=COMMODORE_ITEMS,
)

zip(
    name="distro-k1013",
    items={
        "diskimage.imd": ".+diskimage-k1013",
        "boot.bin": "src/arch/kim-1/boot+boot.bin",
        "boot.pap": "src/arch/kim-1/boot+boot.pap",
    },
)

zip(
    name="distro-sdcard",
    items={
        "diskimage.raw": ".+rawdiskimage-sdcard",
        "bootsd.bin": "src/arch/kim-1/boot+bootsd.bin",
        "bootsd.pap": "src/arch/kim-1/boot+bootsd.pap",
        "bootsd-kimrom.bin": "src/arch/kim-1/boot+bootsd-kimrom.bin",
    },
)

zip(
    name="distro-iec",
    items={
        "diskimage-kim.d64": "src/arch/kim-1+diskimage-iec-kim",
        "diskimage-pal.d64": "src/arch/kim-1+diskimage-iec-pal",
        "bootiec-kim.bin": "src/arch/kim-1/boot+bootiec-kim.bin",
        "bootiec-kim.pap": "src/arch/kim-1/boot+bootiec-kim.pap",
        "bootiec-pal.bin": "src/arch/kim-1/boot+bootiec-pal.bin",
        "bootiec-pal.pap": "src/arch/kim-1/boot+bootiec-pal.pap",
    },
)

zip(
    name="distro-sdshield",
    items={
        "CPM-BOOT.DSK": ".+rawdiskimage-sdshield",
        "bootsdshield.bin": "src/arch/kim-1/boot+bootsdshield.bin",
        "bootsdshield.pap": "src/arch/kim-1/boot+bootsdshield.pap",
        "bootsdshield-kimrom.bin": "src/arch/kim-1/boot+bootsdshield-kimrom.bin",
    },
)

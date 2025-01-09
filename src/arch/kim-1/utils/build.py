from build.llvm import llvmprogram

llvmprogram(
    name="format",
    srcs=["./format.S"],
    cflags=["-I src/arch/kim-1"],
    deps=[
        "include",
        "src/arch/kim-1/k-1013.inc",
        "src/arch/kim-1+k-1013",
    ],
)

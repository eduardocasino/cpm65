from build.llvm import llvmprogram

llvmprogram(
    name="format",
    srcs=["./format.S"],
    deps=[
        "include",
    ],
)

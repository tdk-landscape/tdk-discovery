# =============================================================================
# 📚 TOPOLOGIES - DISCOVERY LIBRARIES
# =============================================================================

load("./config.star", "PLATFORM_LIBS_EXPLICIT", "PLATFORM_LIBS_FRONTEND", "PRODUCT_LIBS_FRONTEND", "PRODUCT_LIBS_EXPLICIT")


def autodiscover_libraries(root_path, prefix):
    libs = []
    result = str(local("ls -d " + root_path + "/" + prefix + "*/ 2>/dev/null || true", quiet=True))

    if result:
        for line in result.strip().split("\n"):
            if line:
                lib_path = line.rstrip("/")
                lib_name = lib_path.split("/")[-1]
                if lib_name:
                    libs.append(lib_name)

    return libs


def get_platform_libs(autodiscover = False):
    if autodiscover:
        discovered = autodiscover_libraries("shared-platform-engineering", "platform-")
        if len(discovered) > 0:
            # Show library names (truncated to first 5 in normal mode)
            is_verbose = os.environ.get('TILT_LOG_LEVEL') == 'verbose'
            if is_verbose or len(discovered) <= 5:
                lib_list = ", ".join(discovered)
            else:
                lib_list = ", ".join(discovered[:5]) + ", ... and {} more".format(len(discovered) - 5)
            print("  📚 Autodiscovered platform libraries: {}".format(lib_list))
            return discovered
    return PLATFORM_LIBS_EXPLICIT + PLATFORM_LIBS_FRONTEND


def get_product_libs(autodiscover = False):
    if autodiscover:
        discovered = autodiscover_libraries("shared-product-engineering", "product-")
        if len(discovered) > 0:
            # Show library names (truncated to first 5 in normal mode)
            is_verbose = os.environ.get('TILT_LOG_LEVEL') == 'verbose'
            if is_verbose or len(discovered) <= 5:
                lib_list = ", ".join(discovered)
            else:
                lib_list = ", ".join(discovered[:5]) + ", ... and {} more".format(len(discovered) - 5)
            print("  📚 Autodiscovered product libraries: {}".format(lib_list))
            return discovered
    return PRODUCT_LIBS_EXPLICIT + PRODUCT_LIBS_FRONTEND

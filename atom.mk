
LOCAL_PATH := $(call my-dir)

# Only for native builds. For cross build, use python3 repository.

ifeq ("$(TARGET_OS_FLAVOUR)","native")

# version-less python meta-package to be used for internal alchemy dependencies.
include $(CLEAR_VARS)
LOCAL_HOST_MODULE := python
LOCAL_CATEGORY_PATH := python
LOCAL_DESCRIPTION := Python metapackage to select correct underlying module
LOCAL_LIBRARIES := host.python-native
include $(BUILD_META_PACKAGE)


include $(CLEAR_VARS)
LOCAL_MODULE := python
LOCAL_CATEGORY_PATH := python
LOCAL_DESCRIPTION := Python metapackage to select correct underlying module
LOCAL_LIBRARIES := python-native
include $(BUILD_META_PACKAGE)

# Use the on from the host, but define module so other modules find the dependency
include $(CLEAR_VARS)
LOCAL_HOST_MODULE := python-setuptools
LOCAL_CATEGORY_PATH := python
LOCAL_DESCRIPTION := Python setuptools native package
include $(BUILD_CUSTOM)


# Fake host module just to please internal alchemy dependencies
include $(CLEAR_VARS)
LOCAL_HOST_MODULE := python-native
LOCAL_CATEGORY_PATH := python
LOCAL_DESCRIPTION := Python native package for host build
include $(BUILD_CUSTOM)


include $(CLEAR_VARS)

LOCAL_MODULE := python-native
LOCAL_CATEGORY_PATH := python
LOCAL_DESCRIPTION := Python native package for target build

LOCAL_CONFIG_FILES := Config.in
$(call load-config)

# Get python native binary
ifdef CONFIG_PYTHON_NATIVE_VERSION_2
  PYTHON_NATIVE_BIN := $(shell which python2)
else
  PYTHON_NATIVE_BIN := $(shell which python3)
endif

ifneq ("$(PYTHON_NATIVE_BIN)","")

# Get major.minor version of python
PYTHON_NATIVE_VERSION := $(strip $(shell $(PYTHON_NATIVE_BIN) -c \
	"import sys; print('{0.major:d}.{0.minor:d}'.format(sys.version_info))"))

#
# Include directories, do not get system headers for virtual env
#
ifndef CONFIG_PYTHON_NATIVE_USE_VIRTUAL_ENV
  LOCAL_EXPORT_C_INCLUDES += $(shell $(PYTHON_NATIVE_BIN)-config --includes)
endif

#
# Python3 adds an 'm' at the end of the version for include directory
# See also: python3-config --abiflags
#
PYTHON_ABI := $(shell $(PYTHON_NATIVE_BIN)-config --abiflags)

ifdef CONFIG_PYTHON_NATIVE_VERSION_3
  PYTHON_ABI_NAME := python$(PYTHON_NATIVE_VERSION)$(PYTHON_ABI)
else
  PYTHON_ABI_NAME := python$(PYTHON_NATIVE_VERSION)
endif

PYTHON_CONFIG_DIR := $(shell $(PYTHON_NATIVE_BIN)-config --configdir)
PYTHON_STATIC_LIB := $(shell readlink -e $(PYTHON_CONFIG_DIR)/lib$(PYTHON_ABI_NAME).a)

LOCAL_EXPORT_C_INCLUDES += $(TARGET_OUT_STAGING)/$(TARGET_ROOT_DESTDIR)/include/$(PYTHON_ABI_NAME)
ifeq ("$(call check-version,$(PYTHON_NATIVE_VERSION),3.8)","")
  LOCAL_EXPORT_LDFLAGS := $(shell $(PYTHON_NATIVE_BIN)-config --ldflags 2>&1|grep -o "\-L[^ ]\+")
  LOCAL_EXPORT_LDLIBS := $(shell $(PYTHON_NATIVE_BIN)-config --libs)
else
  # Python >= 3.8 needs the --embed flag
  LOCAL_EXPORT_LDFLAGS := $(shell $(PYTHON_NATIVE_BIN)-config --ldflags --embed 2>&1|grep -o "\-L[^ ]\+")
  LOCAL_EXPORT_LDLIBS := $(shell $(PYTHON_NATIVE_BIN)-config --libs --embed)
endif

#
# Versionless symbol links to actual python locations, that depends on
# build options. Modules that depends on python-native muse use those
# links.
#
PYTHON_TARGET_STATIC_LIB := $(TARGET_OUT_STAGING)/$(TARGET_ROOT_DESTDIR)/lib/libpython.a
PYTHON_TARGET_SHARED_LIB_DIR := $(TARGET_OUT_STAGING)/$(TARGET_ROOT_DESTDIR)/lib/python
PYTHON3_TARGET_SHARED_LIB_DIR := $(TARGET_OUT_STAGING)/$(TARGET_ROOT_DESTDIR)/lib/python3
PYTHON_TARGET_BIN := $(TARGET_OUT_STAGING)/$(TARGET_ROOT_DESTDIR)/bin/python

PYTHON_HOST_STATIC_LIB := $(HOST_OUT_STAGING)/$(HOST_ROOT_DESTDIR)/lib/libpython.a
PYTHON_HOST_SHARED_LIB_DIR := $(HOST_OUT_STAGING)/$(HOST_ROOT_DESTDIR)/lib/python
PYTHON_HOST_BIN := $(HOST_OUT_STAGING)/$(HOST_ROOT_DESTDIR)/bin/python

endif

# Install virtual env in staging if needed, otherwise simply create links
# Create a simlink with a version-less name in lib directory
define LOCAL_CMD_BUILD
	@if [ -z "$(PYTHON_NATIVE_BIN)" ]; then \
		echo "Missing python binary"; \
		exit 1; \
	fi
	@mkdir -p $(HOST_OUT_STAGING)/$(HOST_ROOT_DESTDIR)/bin
	@mkdir -p $(HOST_OUT_STAGING)/$(HOST_ROOT_DESTDIR)/lib/python$(PYTHON_NATIVE_VERSION)
	@mkdir -p $(TARGET_OUT_STAGING)/$(TARGET_ROOT_DESTDIR)/bin
	@mkdir -p $(TARGET_OUT_STAGING)/$(TARGET_ROOT_DESTDIR)/lib/python$(PYTHON_NATIVE_VERSION)
	$(if $(CONFIG_PYTHON_NATIVE_USE_VIRTUAL_ENV), \
		$(Q) DEB_PYTHON_INSTALL_LAYOUT='deb' \
			virtualenv -p $(PYTHON_NATIVE_BIN) \
			$(TARGET_OUT_STAGING)/$(TARGET_ROOT_DESTDIR) \
			--always-copy \
			--system-site-packages $(endl) \
		$(Q) ln -sfr $(TARGET_OUT_STAGING)/$(TARGET_ROOT_DESTDIR)/bin/python $(PYTHON_HOST_BIN) $(endl)\
		$(Q) ln -sf $(TARGET_OUT_STAGING)/$(PYTHON_STATIC_LIB) $(PYTHON_TARGET_STATIC_LIB) \
		, \
		$(Q) ln -sf $(PYTHON_NATIVE_BIN) $(PYTHON_TARGET_BIN) $(endl) \
		$(Q) ln -sf $(PYTHON_NATIVE_BIN) $(PYTHON_HOST_BIN) $(endl) \
		$(Q) ln -sf $(PYTHON_STATIC_LIB) $(PYTHON_TARGET_STATIC_LIB) \
	)
endef

include $(BUILD_CUSTOM)

ifneq ("$(call is-module-in-build-config,python-native)","")

# Rule to create the usr/lib/python symlink early to avoid surprises if a module
# installs something in usr/lib/python before the link is created.
# Use -n to avoid dereferencing existing directory symlink
define python-native-symlink-create
	@if [[ -e $1 && ! -L $1 ]]; then \
		echo "$1 is not a symlink, you need to clean the output directory"; \
		exit 1; \
	fi
	$(Q) mkdir -p $(dir $1)/python$(PYTHON_NATIVE_VERSION)
	$(Q) ln -sfn python$(PYTHON_NATIVE_VERSION) $1
endef

.PHONY: python-native-symlink
python-native-symlink:
	$(call python-native-symlink-create,$(PYTHON_TARGET_SHARED_LIB_DIR))
	$(call python-native-symlink-create,$(PYTHON3_TARGET_SHARED_LIB_DIR))
	$(call python-native-symlink-create,$(PYTHON_HOST_SHARED_LIB_DIR))

TARGET_GLOBAL_PREREQUISITES += python-native-symlink

endif

endif

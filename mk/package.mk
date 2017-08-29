# Common targets and functions for packaging

#
# Ensure required variables are set
#
_REQUIRED_VARS:= PKG_ROOT_DIR PKG_NAME PKG_VERSION PKG_ARCH

define _CHECK_VARIABLE =
$(if $(value $1),,$(error Required environment variable $(1) not set))
endef

$(foreach var,$(_REQUIRED_VARS),$(eval $(call _CHECK_VARIABLE,$(var))))

#
# Functions for dumping values of local variables
#
# Calling package makefiles can assign additional variables to list
# by adding name to _PKG_LOCAL_VARS.
#
_LOCAL_VARS = $(sort $(filter PKG_% $(_REQUIRED_VARS) INNER_PKG_DIR \
				OUTER_PKG_DIR BUILD_DIR TARBALL_DIR,$(.VARIABLES)))

define _DUMP_VARIABLES =
$(foreach var,$(_LOCAL_VARS) $(_PKG_LOCAL_VARS),$(info $(var): $(value $(var))))
endef

#
# PKG_INFO_* variables allow package makefiles to define additional
# fields to be written into INFO file during packaging. The field name
# will be a lowercase version of the suffix following PKG_INFO_
#
_PKG_INFO_VARS = $(sort $(filter-out PKG_INFO_FILE,$(filter PKG_INFO_%,$(.VARIABLES))))
$(info _PKG_INFO_VARS = $(_PKG_INFO_VARS))

# Write a single field to given file
define _WRITE_PKG_INFO_FIELD =
field=$$(echo '$(1)' | sed -e 's/^PKG_INFO_//' | tr A-Z a-z); \
echo $${field}='$(value $(1))' >> $(2);
endef

# Write all PKG_INFO_* vars to INFO file
define _WRITE_PKG_INFO =
$(foreach var,$(_PKG_INFO_VARS),$(call _WRITE_PKG_INFO_FIELD,$(var),$(1)))
endef

ifdef PKG_RELEASE
    PKG_VERSION_FULL:=$(PKG_VERSION)-$(PKG_RELEASE)
else
    PKG_VERSION_FULL:=$(PKG_VERSION)
endif

# TODO: This needs to handle non-x86_64 archs
ifeq ($(PKG_ARCH),x86_64)
    PKG_PLATFORMS := "x86 bromolow cedarview avoton braswell broadwell dockerx64 kvmx64 grantley"
else
    $(error Platform "$(PKG_ARCH)" not currently supported)
endif

BUILD_DIR := $(PKG_ROOT_DIR)/.build/$(PKG_NAME)-$(PKG_ARCH)-$(PKG_VERSION_FULL)
TARBALL_DIR := $(PKG_ROOT_DIR)/.tarballs
INNER_PKG_DIR := $(BUILD_DIR)/_inner_
OUTER_PKG_DIR := $(BUILD_DIR)/_outer_
PKG_INFO_FILE := $(BUILD_DIR)/INFO

PKG_SCRIPT_DIR := $(PKG_ROOT_DIR)/scripts
PKG_SCRIPT_FILES := $(shell ls $(PKG_SCRIPT_DIR)/*)
PKG_ICON_FILES := $(shell ls $(PKG_ROOT_DIR)/icons/PACKAGE_ICON*.PNG)
PKG_CONF_FILES := $(shell ls $(PKG_ROOT_DIR)/conf/*)
PKG_WIZARD_FILES := $(shell ls $(PKG_ROOT_DIR)/wizard/*)


DEST_PACKAGE := $(PKG_NAME)-$(PKG_ARCH)-$(PKG_VERSION)-$(PKG_RELEASE).spk

# Need to export for 'dump-vars' rule
export PKG_VERSION PKG_ARCH PKG_STATIC PKG_TARBALL INFLUXDB_URL
export PKG_ROOT_DIR BUILD_DIR PKG_SCRIPT_DIR PKG_SCRIPT_FILES PKG_INFO_FILE PKG_ICON_FILES PKG_CONF_FILES DEST_PACKAGE


all: build install package

# Fetch retrieves desired version from web
fetch: $(TARBALL_DIR)/$(PKG_TARBALL)

# Build is a no-op as we download pre-compiled binaries from the web
build: $(BUILD_DIR) $(TARBALL_DIR)/$(PKG_TARBALL)

# Create the inner package tarball from contents of INNER_PKG_DIR
$(BUILD_DIR)/package.tgz: $(shell find $(INNER_PKG_DIR) -type f 2>/dev/null)
	tar czf $@ -C $(INNER_PKG_DIR) .

# Create the INFO file
$(PKG_INFO_FILE): $(BUILD_DIR)/package.tgz
	echo "package=\"$(PKG_NAME)\"" > $(PKG_INFO_FILE)
	echo "version=\"$(PKG_VERSION_FULL)\"" >> $(PKG_INFO_FILE)
	echo "arch=\"$(PKG_PLATFORMS)\"" >> $(PKG_INFO_FILE)
	$(call _WRITE_PKG_INFO,$(PKG_INFO_FILE))
	size=$$(du -s $(INNER_PKG_DIR) | cut -f1); \
	  echo "extractsize=$$size" >> $(PKG_INFO_FILE)
	echo "create_time=\"$$(date "+%Y%m%d-%H:%M:%S")\"" >> $(PKG_INFO_FILE)

# To ensure INFO file is always accurate we must force rebuild each time
.PHONY: $(PKG_INFO_FILE)


# Build to .spk package
package: $(DEST_PACKAGE)

$(DEST_PACKAGE): $(BUILD_DIR)/package.tgz $(PKG_SCRIPT_FILES) $(PKG_ICON_FILES) $(PKG_INFO_FILE) $(PKG_CONF_FILES) $(PKG_WIZARD_FILES)
	rm -rf $(OUTER_PKG_DIR)
	install -d $(OUTER_PKG_DIR)
	install -d $(OUTER_PKG_DIR)/scripts
	install -m 755 $(PKG_SCRIPT_FILES) $(OUTER_PKG_DIR)/scripts
	install -m 644 $(BUILD_DIR)/package.tgz $(OUTER_PKG_DIR)
	if [ -n "$(PKG_ICON_FILES)" ]; then \
		install -m 644 $(PKG_ICON_FILES) $(PKG_INFO_FILE) $(OUTER_PKG_DIR); \
	fi
	if [ -n "$(PKG_CONF_FILES)" ]; then \
	  install -d $(OUTER_PKG_DIR)/conf; \
	  install -m 644 $(PKG_CONF_FILES) $(OUTER_PKG_DIR)/conf; \
	fi
	if [ -n "$(PKG_WIZARD_FILES)" ]; then \
	  install -d $(OUTER_PKG_DIR)/WIZARD_UIFILES; \
	  install -m 755 $(PKG_WIZARD_FILES) $(OUTER_PKG_DIR)/WIZARD_UIFILES; \
	fi
	tar czf $@ -C $(OUTER_PKG_DIR) $$(ls $(OUTER_PKG_DIR))

dump-vars:
	@:$(call _DUMP_VARIABLES)

# Create build directory
$(BUILD_DIR) $(TARBALL_DIR):
	@if [ ! -d "$@" ]; then mkdir -p "$@"; fi
	@if [ ! -f "$@/.gitignore" ]; then echo "*" > "$@/.gitignore"; fi

clean:
	rm -rf $(BUILD_DIR)/*

clean-all:
	rm -rf $(PKG_ROOT_DIR)/.build

dist-clean: clean-all
	rm -rf $(TARBALL_DIR)

.PHONY: all clean build install fetch package dist-clean dump-vars

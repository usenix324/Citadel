
# On Centos: sudo yum install kernel-headers

V?=0
ifeq ($(V),0)
Q=@
else
Q=
endif
CURRENTDIR := $(PWD)
CONNECTALDIR ?= $(CURRENTDIR)/../..
include $(CONNECTALDIR)/Makefile.version

obj-m += pcieportal.o

PKG_NAME?=connectal
# DKMS only looks in /usr/src
PREFIX?=/usr
KVERSION=$(shell uname -r)
KROOT=/lib/modules/$(KVERSION)/build
export BS_MOD_DIR=$(DESTDIR)/lib/modules/$(KVERSION)/connectal

.PHONY: default
default: pcieportal.ko ../portalmem/portalmem.ko

EXTRA_CFLAGS := -I$(CONNECTALDIR)/drivers/pciportal -I$(CONNECTALDIR)/cpp -I$(CONNECTALDIR) -I$(CONNECTALDIR)/drivers/portalmem -I$(CONNECTALDIR)/generated/cpp
cflags-y += -I$(PWD)

../portalmem/portalmem.ko: ../portalmem/portalmem.c
	cd ../portalmem; make

driverversion.h:
	VERSION=$(VERSION) echo "#define DRIVER_VERSION \"$$VERSION\"" > driverversion.h

pcieportal.ko: pcieportal.c pcieportal.h driverversion.h
	$(Q)$(MAKE) -C $(KROOT) M=$(PWD) modules

.PHONY: modules_check
modules_check:
	$(Q)$(MAKE) -C $(KROOT) C=2 M=$(PWD) modules

.PHONY: install
install: pcieportal.ko
	install -d -m755 $(BS_MOD_DIR)
	install -m644 pcieportal.ko $(BS_MOD_DIR)
	install -m644 ../portalmem/portalmem.ko $(BS_MOD_DIR)
ifeq ("$(DESTDIR)", "")
	depmod
endif

.PHONY: uninstall
uninstall:
	rm -f $(BS_MOD_DIR)/pcieportal.ko
	rmdir --ignore-fail-on-non-empty $(BS_MOD_DIR)
ifeq ("$(DESTDIR)", "")
	depmod
endif

.PHONY: clean
clean:
	$(Q)$(MAKE) -C $(KROOT) M=$(PWD) clean
	cd ../portalmem; make clean

.PHONY: distclean
distclean: clean

.PHONY: rmmod
rmmod:
	rmmod portalmem || true
	rmmod pcieportal || true

.PHONY: insmod
insmod: rmmod
	insmod pcieportal.ko
	-chmod agu+rw /dev/portal*
	insmod ../portalmem/portalmem.ko
	chmod agu+rw /dev/portalmem

.PHONY: install-dkms
install-dkms:
	rm -f driverversion.h
	make driverversion.h
	mkdir -p $(DESTDIR)$(PREFIX)/src/$(PKG_NAME)-$(VERSION)
	sed "s/@VERSION@/$(VERSION)/" dkms.conf | sed "s/@PKG_NAME@/$(PKG_NAME)/" > dkms.conf.out
	sed "s/@VERSION@/$(VERSION)/" Makefile.dkms > Makefile.dkms.out
	cp -fv dkms.conf.out $(DESTDIR)$(PREFIX)/src/$(PKG_NAME)-$(VERSION)/dkms.conf
	cp -fv Makefile.dkms.out $(DESTDIR)$(PREFIX)/src/$(PKG_NAME)-$(VERSION)/Makefile
	cp -fv pcieportal.c pcieportal.h driverversion.h $(DESTDIR)$(PREFIX)/src/$(PKG_NAME)-$(VERSION)
	cp -fv ../../cpp/*.[ch] ../portalmem/*.[ch] \
	../../generated/cpp/*.[ch] \
	$(DESTDIR)$(PREFIX)/src/$(PKG_NAME)-$(VERSION)
	sed -i 's|drivers/portalmem/||' $(DESTDIR)$(PREFIX)/src/$(PKG_NAME)-$(VERSION)/*.[ch]
	sed -i 's|drivers/pcieportal/||' $(DESTDIR)$(PREFIX)/src/$(PKG_NAME)-$(VERSION)/*.[ch]
	sed -i 's|drivers/zynqportal/||' $(DESTDIR)$(PREFIX)/src/$(PKG_NAME)-$(VERSION)/*.[ch]
	sed -i 's|../../cpp/||g' $(DESTDIR)$(PREFIX)/src/$(PKG_NAME)-$(VERSION)/*.[ch]

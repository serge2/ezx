VSN ?= $(shell sed -n 's/.*{ezx, "\([^"]*\)"}.*/\1/p' rebar.config | head -1)
ARCH ?= amd64

DIST = dist
RELDIR = _build/prod/rel/ezx
DEB = $(DIST)/ezx_$(VSN)_$(ARCH).deb
TGZ = $(DIST)/ezx-$(VSN)-linux-x86_64.tar.gz
DEBDIR = $(DIST)/deb-stage/ezx_$(VSN)_$(ARCH)
TGZDIR = $(DIST)/tgz-stage/ezx-$(VSN)-linux-x86_64

.PHONY: all release deb tgz clean

all: deb tgz

release:
	rebar3 as prod release

deb: $(DEB)

tgz: $(TGZ)

$(RELDIR): release

$(DEB): $(RELDIR) packaging/ezx.desktop packaging/control.in packaging/postinst packaging/postrm priv/ezx.png
	rm -rf $(DEBDIR)
	mkdir -p $(DEBDIR)/DEBIAN \
	         $(DEBDIR)/opt/ezx \
	         $(DEBDIR)/usr/bin \
	         $(DEBDIR)/usr/share/applications \
	         $(DEBDIR)/usr/share/pixmaps
	cp -a $(RELDIR)/. $(DEBDIR)/opt/ezx/
	ln -s /opt/ezx/bin/ezx-launch $(DEBDIR)/usr/bin/ezx
	cp packaging/ezx.desktop $(DEBDIR)/usr/share/applications/ezx.desktop
	cp priv/ezx.png $(DEBDIR)/usr/share/pixmaps/ezx.png
	sed -e 's|@VSN@|$(VSN)|' -e 's|@ARCH@|$(ARCH)|' packaging/control.in > $(DEBDIR)/DEBIAN/control
	cp packaging/postinst $(DEBDIR)/DEBIAN/postinst
	cp packaging/postrm $(DEBDIR)/DEBIAN/postrm
	chmod 755 $(DEBDIR)/DEBIAN/postinst $(DEBDIR)/DEBIAN/postrm
	dpkg-deb --build --root-owner-group $(DEBDIR) $(DEB)

$(TGZ): $(RELDIR) packaging/ezx packaging/ezx.desktop packaging/install.sh packaging/uninstall.sh priv/ezx.png
	rm -rf $(TGZDIR)
	mkdir -p $(TGZDIR)
	cp -a $(RELDIR)/. $(TGZDIR)/
	cp packaging/ezx $(TGZDIR)/ezx
	cp packaging/ezx.desktop $(TGZDIR)/
	cp priv/ezx.png $(TGZDIR)/
	cp packaging/install.sh $(TGZDIR)/install.sh
	cp packaging/uninstall.sh $(TGZDIR)/uninstall.sh
	chmod 755 $(TGZDIR)/ezx $(TGZDIR)/install.sh $(TGZDIR)/uninstall.sh
	tar -C $(DIST)/tgz-stage -czf $(TGZ) ezx-$(VSN)-linux-x86_64

clean:
	rm -rf $(DIST)
	rebar3 as prod clean

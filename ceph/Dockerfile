FROM ceph/daemon:tag-build-master-kraken-ubuntu-16.04
LABEL maintainer "Nazar Mokrynskyi <nazar@mokrynskyi.com>"

RUN \

	apt-get update && \
	apt-get upgrade -y && \
	apt-get install -y --no-install-recommends dnsutils && \
	apt-get clean && \
	rm -rf /var/lib/apt/lists/*

COPY webserver-entrypoint.sh /

VOLUME /var/lib/ceph

ENV \
	CONSUL_SERVICE=consul \

	CLUSTER=ceph \
	KV_TYPE=consul \
	KV_IP=consul \
	KV_PORT=80 \
	OSD_TYPE=directory \
	CEPHFS_CREATE=1 \
	CEPH_MON_SERVICE=ceph-mon \
	CEPH_OSD_SERVICE=ceph-osd \
	CEPH_MDS_SERVICE=ceph-mds \
	CEPH_RWG_SERVICE=ceph-rwg \
	CEPH_RESTAPI_SERVICE=ceph-restapi

ENTRYPOINT ["/webserver-entrypoint.sh"]

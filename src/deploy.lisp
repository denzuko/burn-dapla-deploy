;;;; src/deploy.lisp -- burn-dapla-deploy/deploy core package
;;;;
;;;; Consfigurator properties and DEFHOST for Enclosed at burn.dapla.net.
;;;; Enclosed is a self-hosted encrypted note-sharing tool; notes are
;;;; encrypted client-side before reaching the server. The data dataset
;;;; holds the SQLite store.

(defpackage :burn-dapla-deploy/deploy
  (:use :cl)
  (:import-from :consfigurator
                :defprop :defhost :mrun :stripln
                :remote-exists-p :write-remote-file :on-change)
  (:import-from :consfigurator.property.file
                :has-content :containing-directory-exists)
  (:import-from :consfigurator.property.systemd :lingering-enabled)
  (:import-from :consfigurator.property.service :reloaded)
  (:export :*service-user* :*home-dataset* :*home-mountpoint*
           :*data-dataset* :*data-mountpoint*
           :*home-dataset-keyfile* :*data-dataset-keyfile*
           :*haproxy-fqdn*
           :deploy-app
           :zfs-encryption-key :zfs-dataset-mounted
           :rootless-service-account
           :images-pulled :quadlets-activated
           :cinix-write-string
           :quadlets-written
           :haproxy-vhost-written
           :decommissioned
           :burn-network-sections
           :burn-container-sections
           :haproxy-vhost-config))

(in-package :burn-dapla-deploy/deploy)

(defparameter *service-user* "enclosed")
(defparameter *home-dataset* "storage/users/enclosed")
(defparameter *home-mountpoint* "/var/lib/enclosed")
(defparameter *home-dataset-keyfile* "/etc/zfs-keys/enclosed-users.key")
(defparameter *data-dataset* "storage/containers/enclosed")
(defparameter *data-mountpoint* "/srv/enclosed"
  "Enclosed data directory: SQLite store for encrypted notes.")
(defparameter *data-dataset-keyfile* "/etc/zfs-keys/enclosed-data.key")
(defparameter *haproxy-fqdn* "burn.dapla.net")
(defparameter *haproxy-vhost-name* "burn")

(defparameter *port-base* 10000
  "Added to the service account UID to derive the loopback PublishPort.
   Keeps all ports above 1024 and clear of well-known service ranges.")


(defprop zfs-encryption-key :posix (path)
  "Generate a raw 32-byte ZFS encryption key at PATH, once, left alone on
   redeploy. Written directly by openssl to avoid binary corruption through
   shell capture and string re-encoding."
  (:desc (format nil "ZFS encryption key at ~A" path))
  (:check (remote-exists-p path))
  (:apply
   (containing-directory-exists path)
   (mrun "openssl" "rand" "-out" path "32")
   (mrun "chmod" "600" path)))

(defun zfs-create-command (dataset mountpoint keyfile)
  (if keyfile
      (format nil "zfs create -o mountpoint=~A -o encryption=aes-256-gcm -o keyformat=raw -o keylocation=file://~A ~A"
              mountpoint keyfile dataset)
      (format nil "zfs create -o mountpoint=~A ~A" mountpoint dataset)))

(defprop zfs-dataset-mounted :posix (dataset mountpoint &optional keyfile)
  "Ensure DATASET exists, mounted at MOUNTPOINT, AES-256-GCM encrypted when KEYFILE is supplied."
  (:desc (format nil "ZFS dataset ~A mounted at ~A~:[~; (encrypted)~]" dataset mountpoint keyfile))
  (:check
   (multiple-value-bind (out err exit)
       (consfigurator:run :may-fail (format nil "zfs get -H -o value mounted ~A" dataset))
     (declare (ignore err))
     (and (zerop exit) (string= "yes" (stripln out)))))
  (:apply
   (if (zerop (mrun :for-exit (format nil "zfs list -H -o name ~A" dataset)))
       (progn (when keyfile (mrun (format nil "zfs load-key ~A" dataset)))
              (mrun (format nil "zfs mount ~A" dataset)))
       (mrun (zfs-create-command dataset mountpoint keyfile)))))

(defprop rootless-service-account :posix (username home)
  "Ensure system account USERNAME exists with home HOME, without creating the directory."
  (:desc (format nil "System account ~A at ~A" username home))
  (:check (zerop (mrun :for-exit "id" username)))
  (:apply (mrun "useradd" "--system" "--no-create-home" "--home-dir" home username)))

(defprop images-pulled :posix (user &rest images)
  "Pull IMAGES into USER's rootless Podman image store via `machinectl shell`."
  (:desc (format nil "Podman images pulled for ~A" user))
  (:check (every (lambda (i) (zerop (mrun :for-exit (format nil "machinectl shell ~A@ /usr/bin/podman image exists ~A" user i)))) images))
  (:apply (dolist (i images) (mrun (format nil "machinectl shell ~A@ /usr/bin/podman pull ~A" user i)))))

(defun cinix-write-string (sections)
  "Serialize an alist of (section-name . ((key . value) ...)) into INI/systemd unit-file text."
  (with-output-to-string (s)
    (dolist (section sections)
      (format s "[~A]~%" (car section))
      (dolist (kv (cdr section)) (format s "~A=~A~%" (car kv) (cdr kv)))
      (format s "~%"))))


(defun burn-network-sections ()
  '(("Network" . (("NetworkName" . "burn")
                  ("Driver"      . "bridge")
                  ("Subnet"      . "10.89.2.28/30")
                  ("Gateway"     . "10.89.2.29")))))

(defun burn-container-sections (data-mountpoint)
  "Cinix AST for burn.container. Enclosed uses the rootless-compatible
   image tag. The loopback port is the service account UID."
      `(("Unit"      . (("Description" . "Enclosed encrypted note sharing")))
      ("Container" . (("Image"         . "oci.dapla.net/corentinth/enclosed:latest-rootless")
                      ("ContainerName" . "enclosed")
                      ("AutoUpdate"    . "registry")
                      ("PublishPort"   . ,(format nil "127.0.0.1:~A:8080" port))
                      ("Volume"        . ,(format nil "~A:/app/data:Z" data-mountpoint))
                      ("Network"       . "burn.network")
                      ("Label"         . "io.containers.autoupdate=registry")
                      ("Label"           . "org.cispec.application=burn-dapla-deploy")
                      ("Label"           . "org.cispec.managed-by=consfigurator")
                      ("Label"           . "org.cispec.fqdn=burn.dapla.net")
                      ("Label"           . "org.cispec.service-account=enclosed")))
      ("Service"   . (("Restart" . "on-failure") ("TimeoutStartSec" . "60") ("TimeoutStopSec" . "30")))
      ("Install"   . (("WantedBy" . "default.target"))))))

(defun haproxy-vhost-config ()
  "HAProxy vhost configuration for burn.dapla.net.
   Backend uses the netavark bridge gateway IP 10.89.2.29 on the
   container's natural internal port. No loopback, no port arithmetic.

;;; dapla.net netavark service network allocation
;;; All subnets within 10.89.2.0/26 (64 addresses).
;;; Existing host networks: podman1=10.89.0.0/24, podman2=10.89.1.0/24.
;;;
;;; Service       Network     Subnet           Gateway      Prefix  Containers
;;; find          podman3     10.89.2.0/30     10.89.2.1    /30     1
;;; watch         podman4     10.89.2.4/29     10.89.2.5    /29     2
;;; meet          podman5     10.89.2.12/29    10.89.2.13   /29     3
;;; feed          podman6     10.89.2.20/30    10.89.2.21   /30     1
;;; save          podman7     10.89.2.24/30    10.89.2.25   /30     1
;;; burn          podman8     10.89.2.28/30    10.89.2.29   /30     1
;;; link          podman9     10.89.2.32/30    10.89.2.33   /30     1
;;; support       podman10    10.89.2.36/29    10.89.2.37   /29     4
  "
  (format nil
"frontend burn_http
  bind *:80
  acl host_burn hdr(host) -i burn.dapla.net
  redirect scheme https code 301 if host_burn

frontend burn_https
  bind *:443 ssl crt /etc/haproxy/certs/burn.dapla.net.pem alpn h2,http/1.1
  acl host_burn hdr(host) -i burn.dapla.net
  http-response set-header Strict-Transport-Security \"max-age=63072000; includeSubDomains; preload\"
  http-response set-header X-Content-Type-Options nosniff
  http-response set-header X-Frame-Options SAMEORIGIN
  http-response set-header Referrer-Policy strict-origin-when-cross-origin
  http-response set-header Permissions-Policy \"interest-cohort=()\""
  use_backend burn_be if host_burn

backend burn_be
  balance roundrobin
  option httpchk GET /health
  http-check expect status 200
  timeout connect 5s
  timeout server  60s
  server enclosed 10.89.2.29:8080 check inter 10s rise 2 fall 3
"))

(defprop haproxy-vhost-written :posix ()
  "Write the HAProxy vhost config for this service. Skipped when the
   service account does not yet exist, since the port cannot be determined.
   Reloads HAProxy only when content changes."
  (:desc (format nil "HAProxy vhost written for ~A" *haproxy-fqdn*))
  (:check nil)
  (:apply
        (unless port
       (consfigurator:inapplicable-property
        "Service account ~A does not exist; cannot determine port."
        *service-user*))
     (let* ((cfg-path (format nil "/etc/haproxy/conf.d/~A.cfg" *haproxy-vhost-name*))
            (new-content (haproxy-vhost-config))
            (current (when (probe-file cfg-path)
                       (uiop:read-file-string cfg-path))))
       (unless (equal new-content current)
         (containing-directory-exists cfg-path)
         (write-remote-file cfg-path new-content)
         (consfigurator.property.service:reloaded "haproxy"))))))

(defhost burn-host (:deploy (:local))
  "The Enclosed host: two AES-256-GCM ZFS datasets, rootless service account,
   linger, pulled image, quadlet unit, and HAProxy vhost."
  (zfs-encryption-key *home-dataset-keyfile*)
  (zfs-encryption-key *data-dataset-keyfile*)
  (zfs-dataset-mounted *home-dataset* *home-mountpoint* *home-dataset-keyfile*)
  (zfs-dataset-mounted *data-dataset* *data-mountpoint* *data-dataset-keyfile*)
  (rootless-service-account *service-user* *home-mountpoint*)
  (lingering-enabled *service-user*)
  (images-pulled *service-user* "oci.dapla.net/corentinth/enclosed:latest-rootless")
  (quadlets-written *service-user* *home-mountpoint* *data-mountpoint*)
  (quadlets-activated *service-user*)
  (haproxy-vhost-written))


(defprop decommissioned :posix (user)
  "Tear down the burn-dapla-deploy stack in least-destructive-first order.
   Steps:
     1. Stop all containers in the service account session.
     2. Remove the HAProxy vhost config and reload HAProxy.
     3. Terminate the service account login session.
     4. Disable linger so the account session does not restart.
     5. Delete the service account.
     6. Destroy all ZFS datasets (irreversible without a backup).
     7. Remove the ZFS encryption key files.
   Confirm a current rsync.net replica or snapshot exists before
   executing steps 6 and 7."
  (:desc (format nil "burn-dapla-deploy decommissioned for ~~A" user))
  (:apply
   (mrun (format nil "machinectl shell ~~A@ /usr/bin/systemctl --user stop --all" user))
   (mrun "rm" "-f" (format nil "/etc/haproxy/conf.d/~~A.cfg" *haproxy-vhost-name*))
   (mrun "systemctl" "reload" "haproxy")
   (mrun "loginctl" "terminate-user" user)
   (mrun "loginctl" "disable-linger" user)
   (mrun "userdel" user)
   (mrun "zfs" "destroy" "-r" 'storage/users/enclosed')
   (mrun "zfs" "destroy" "-r" 'storage/containers/enclosed')
   (mrun "rm" "-f" '/etc/zfs-keys/enclosed-users.key')
   (mrun "rm" "-f" '/etc/zfs-keys/enclosed-data.key')))

(defun deploy-app ()
  "Provision Enclosed via BURN-HOST. Aborts loudly if any property is skipped."
  (format t "~&--> Provisioning via Consfigurator (BURN-HOST)...~%")
  (let ((provisioning-failed nil))
    (handler-bind ((consfigurator::skipped-properties
                     (lambda (c) (declare (ignore c)) (setf provisioning-failed t))))
      (burn-host))
    (when provisioning-failed
      (error "BURN-HOST provisioning reported failed properties. Refusing to proceed.")))
  (format t "~&--> Enclosed provisioned. Visit https://~A~%" *haproxy-fqdn*))

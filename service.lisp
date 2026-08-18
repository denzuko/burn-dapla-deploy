(:repo-name    'burn-dapla-deploy'
 :system-name  'burn-dapla-deploy'
 :fqdn         'burn.dapla.net'
 :vhost-name   'burn'
 :service-user 'enclosed'
 :description  'Enclosed encrypted note sharing'
 :image        'oci.dapla.net/corentinth/enclosed:latest-rootless'
 :internal-port 8080
 :health-path  '/health'
 :datasets
 (  (:name 'users/enclosed'
   :mountpoint '/var/lib/enclosed'
   :purpose 'Service account home directory')
  (:name 'containers/enclosed'
   :mountpoint '/srv/enclosed'
   :purpose 'Enclosed SQLite store'))
)

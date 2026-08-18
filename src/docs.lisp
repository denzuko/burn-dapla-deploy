;;;; src/docs.lisp -- burn-dapla-deploy/docs

(defpackage :burn-dapla-deploy/docs
  (:use :cl)
  (:import-from :40ants-doc :defsection))

(in-package :burn-dapla-deploy/docs)

(defsection @burn-dapla-deploy (:title "burn-dapla-deploy")
  "Roswell/Consfigurator deploy for burn.dapla.net."
  (@deploy-properties section))

(defsection @deploy-properties (:title "Consfigurator Properties")
  (burn-dapla-deploy/deploy:deploy-app function))

;;;; t/e2e.lisp -- burn-dapla-deploy/e2e

(defpackage :burn-dapla-deploy/e2e
  (:use :cl :fiveam)
  (:import-from :burn-dapla-deploy/deploy :*haproxy-fqdn*)
  (:export :run-e2e))

(in-package :burn-dapla-deploy/e2e)

(def-suite :burn-dapla-deploy-e2e
  :description "Smoke tests for burn.dapla.net.")

(in-suite :burn-dapla-deploy-e2e)

(test http-redirect
  "Plain HTTP requests redirect to HTTPS."
  (multiple-value-bind (body status)
      (dex:get (format nil "http://~A/" *haproxy-fqdn*)
               :force-string t :want-stream nil :redirect nil)
    (declare (ignore body))
    (is (member status '(301 302)))))

(test frontend-responds
  "The service frontend returns HTTP 200."
  (multiple-value-bind (body status)
      (dex:get (format nil "https://~A" *haproxy-fqdn*)
               :force-string t :want-stream nil)
    (declare (ignore body))
    (is (= 200 status))))

(defun run-e2e ()
  "Run the post-deploy e2e suite and signal an error if any test fails."
  (let ((results (run :burn-dapla-deploy-e2e)))
    (unless (every #'fiveam::test-passed-p results)
      (error "burn-dapla-deploy e2e suite: one or more tests failed."))))

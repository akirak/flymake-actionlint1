;;; flymake-actionlint1.el --- Another flymake backend for actionlint -*- lexical-binding: t -*-

;; Copyright (C) 2023 Akira Komamura

;; Author: Akira Komamura <akira.komamura@gmail.com>
;; Version: 0.1
;; Package-Requires: ((emacs "28.1"))
;; Keywords: languages tools
;; URL: https://github.com/akirak/flymake-actionlint1

;; This file is not part of GNU Emacs.

;;; License:

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;;

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defgroup flymake-actionlint1 nil
  "A Flymake backend for actionlint."
  :group 'flymake)

(defconst flymake-actionlint1-location-regexp
  (rx bol (+ (not (any ":"))) ":"
      (group (+ digit)) ":"
      (group (+ digit)) ":"
      (+ blank) (group (+ nonl))))

(defcustom flymake-actionlint1-executable "actionlint"
  "Executable file of actionlint."
  :type 'file)

(defcustom flymake-actionlint1-shellcheck-executable "shellcheck"
  "Executable file for shellcheck.

Actionlint has built-in integration with shellcheck. Setting this
variable will enable the integration in flymake.

If the value of this variable is nil or the program doesn't
exist, the integration will be disabled."
  :type '(choice file (const nil)))

(defvar-local flymake-actionlint1-process nil)

;;;###autoload
(defun flymake-actionlint1-enable ()
  (interactive)
  (when (buffer-file-name)
    (flymake-mode t)
    (add-hook 'flymake-diagnostic-functions 'flymake-actionlint1--run nil t)))

(defun flymake-actionlint1--run (report-fn &rest _ignored)
  (unless (executable-find flymake-actionlint1-executable)
    (error "The executable %s doesn't exist. See `flymake-actionlint1-executable'"
           flymake-actionlint1-executable))
  (when (and flymake-actionlint1-process
             (process-live-p flymake-actionlint1-process))
    (kill-process flymake-actionlint1-process))
  (let* ((source (current-buffer))
         (buffer (generate-new-buffer "*flymake-actionlint1*"))
         (name (buffer-name buffer))
         (shellcheck-bin (when flymake-actionlint1-shellcheck-executable
                           (executable-find flymake-actionlint1-shellcheck-executable))))
    (cl-flet
        ((sentinel (proc _event)
           (when (memq (process-status proc) '(exit signal))
             (unwind-protect
                 (with-current-buffer (get-buffer name)
                   (goto-char (point-min))
                   (let (result)
                     (while (re-search-forward flymake-actionlint1-location-regexp
                                               nil t)
                       (pcase-let*
                           ((description (match-string 3))
                            (`(,begin . ,end) (flymake-diag-region
                                               source
                                               (string-to-number (match-string 1))
                                               (string-to-number (match-string 2)))))
                         (push (flymake-make-diagnostic source begin end :error
                                                        description)
                               result)))
                     (funcall report-fn (nreverse result))))
               (kill-buffer (get-buffer name))))))
      (setq flymake-actionlint1-process
            (make-process :buffer buffer
                          :name "flymake-actionlint1"
                          :noquery t
                          :connection-type 'pipe
                          :command `(,flymake-actionlint1-executable
                                     "-no-color"
                                     "-oneline"
                                     ,@(when shellcheck-bin
                                         (list "-shellcheck" shellcheck-bin))
                                     "-stdin-filename"
                                     ,(file-name-nondirectory (buffer-file-name))
                                     "-")
                          :sentinel #'sentinel))
      (save-restriction
        (widen)
        (process-send-region flymake-actionlint1-process (point-min) (point-max))
        (process-send-eof flymake-actionlint1-process)))))

(provide 'flymake-actionlint1)
;;; flymake-actionlint1.el ends here

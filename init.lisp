(in-package :lem)

(load-theme "nord")

(add-hook lem-lisp-mode/internal:*lisp-repl-mode-hook*
          (lambda ()
            (change-buffer-mode (current-buffer)
                                'lem-paredit-mode:paredit-mode t)))

(in-package :lem)

(export '(*isearch-keymap*
          isearch-forward
          isearch-backward
          query-replace))

(defvar *isearch-keymap* (make-keymap "isearch" 'isearch-self-insert))
(defvar *isearch-string*)
(defvar *isearch-prev-string* "")
(defvar *isearch-start-point*)
(defvar *isearch-search-function*)
(defvar *isearch-highlight-overlays* nil)

(define-minor-mode isearch-mode
  :name "isearch-mode"
  :keymap *isearch-keymap*)

(defun isearch-update-display ()
  (isearch-update-minibuf)
  (isearch-update-buffer))

(defun isearch-update-minibuf ()
  (minibuf-print (format nil "ISearch: ~a" *isearch-string*)))

(define-key *global-keymap* (kbd "C-s") 'isearch-forward)
(define-command isearch-forward () ()
  (isearch-start
   #'(lambda (str)
       (prev-char (length str))
       (search-forward str))))

(define-key *global-keymap* (kbd "C-r") 'isearch-backward)
(define-command isearch-backward () ()
  (isearch-start
   #'(lambda (str)
       (next-char (length str))
       (search-backward str))))

(defun isearch-start (search-func)
  (isearch-mode t)
  (setq *isearch-string* "")
  (isearch-update-minibuf)
  (setq *isearch-search-function* search-func)
  (setq *isearch-start-point* (point))
  t)

(define-key *isearch-keymap* (kbd "C-g") 'isearch-abort)
(define-command isearch-abort () ()
  (point-set *isearch-start-point*)
  t)

(define-key *isearch-keymap* (kbd "C-h") 'isearch-delete-char)
(define-key *isearch-keymap* (kbd "[backspace]") 'isearch-delete-char)
(define-command isearch-delete-char () ()
  (when (plusp (length *isearch-string*))
    (setq *isearch-string*
          (subseq *isearch-string*
                  0
                  (1- (length *isearch-string*))))
    (isearch-update-display)))

(define-key *isearch-keymap* (kbd "C-q") 'isearch-raw-insert)
(define-command isearch-raw-insert () ()
  (isearch-add-char (getch)))

(define-key *isearch-keymap* (kbd "C-j") 'isearch-end)
(define-key *isearch-keymap* (kbd "C-m") 'isearch-end)
(define-command isearch-end () ()
  (isearch-reset-buffer)
  (setq *isearch-prev-string* *isearch-string*)
  (isearch-mode nil))

(define-key *isearch-keymap* (kbd "C-s") 'isearch-next)
(define-command isearch-next () ()
  (when (string= "" *isearch-string*)
    (setq *isearch-string* *isearch-prev-string*))
  (search-forward *isearch-string*)
  (isearch-update-display))

(define-key *isearch-keymap* (kbd "C-r") 'isearch-prev)
(define-command isearch-prev () ()
  (when (string= "" *isearch-string*)
    (setq *isearch-string* *isearch-prev-string*))
  (search-backward *isearch-string*)
  (isearch-update-display))

(define-key *isearch-keymap* (kbd "C-y") 'isearch-yank)
(define-command isearch-yank () ()
  (let ((str (kill-ring-first)))
    (when str
      (setq *isearch-string* str)
      (isearch-update-display))))

(defun isearch-reset-buffer ()
  (mapc #'delete-overlay *isearch-highlight-overlays*)
  (setq *isearch-highlight-overlays* nil))

(defun isearch-update-buffer ()
  (isearch-reset-buffer)
  (window-adjust-view *current-window* t)
  (unless (equal "" *isearch-string*)
    (multiple-value-bind (search-strings length)
        (split-string *isearch-string* #\newline)
      (with-window-range (start end) *current-window*
        (let ((buffer (window-buffer))
              (buffer-nlines (buffer-nlines)))
          (loop for linum from start below (- end length)
            while (< linum buffer-nlines)
            do (let* ((buffer-strings (buffer-take-lines buffer linum length))
                      (search-string (car search-strings))
                      (buffer-string (car buffer-strings)))
                 (if (= 1 length)
                     (loop with col = 0 do
                       (setq col
                             (search search-string
                                     buffer-string
                                     :start2 col))
                       (if (null col)
                           (return)
                           (let ((start (make-point linum col))
                                 (end (make-point
                                       linum (+ col (length search-string)))))
                             (push (make-overlay start end :prop (get-attr :highlight))
                                   *isearch-highlight-overlays*)))
                       (incf col (length search-string)))
                     (let ((col
                            (- (length buffer-string)
                               (length search-string)))
                           (last-search-string
                            (car (last search-strings))))
                       (when (and (every #'string=
                                         (butlast (cdr search-strings))
                                         (butlast (cdr buffer-strings)))
                                  (<= 0 col)
                                  (string= search-string
                                           buffer-string
                                           :start2 col)
                                  (<= (length last-search-string)
                                      (length (car (last buffer-strings))))
                                  (string= last-search-string
                                           (car (last buffer-strings))
                                           :end2 (length last-search-string)))
                         (let ((start (make-point linum col))
                               (end (make-point (+ linum length -1)
                                                (length last-search-string))))
                           (push (make-overlay start end :prop (get-attr :highlight))
                                 *isearch-highlight-overlays*))))))))))))

(defun isearch-add-char (c)
  (setq *isearch-string*
        (concatenate 'string
                     *isearch-string*
                     (string c)))
  (isearch-update-display)
  (let ((point (point)))
    (unless (funcall *isearch-search-function* *isearch-string*)
      (point-set point))))

(define-command isearch-self-insert () ()
  (let ((c (insertion-key-p *last-input-key*)))
    (if c
        (isearch-add-char c)
        (progn
          (progn
            (mapc 'ungetch (reverse (kbd-list *last-input-key*)))
            (isearch-end))))))

(defun search-step (str first-search search step goto-matched-pos endp)
  (let ((point (point))
        (result
         (let ((res (funcall first-search)))
           (if res
               (progn
                 (funcall goto-matched-pos res)
                 t)
               (do () ((funcall endp))
                 (funcall step)
                 (let ((res (funcall search)))
                   (when res
                     (funcall goto-matched-pos res)
                     (return t))))))))
    (unless result
      (point-set point))
    result))

(defun search-forward (str)
  (multiple-value-bind (lines length)
      (split-string str #\newline)
    (flet ((take-string ()
                        (join (string #\newline)
                              (buffer-take-lines (window-buffer)
                                                 (window-cur-linum)
                                                 length))))
      (search-step str
                   #'(lambda ()
                       (search str (take-string)
                               :start2 (window-cur-col)))
                   #'(lambda ()
                       (search str (take-string)))
                   #'(lambda () (next-line 1))
                   #'(lambda (i)
                       (beginning-of-line)
                       (next-char (+ i (length str))))
                   #'eobp))))

(defun search-backward (str)
  (multiple-value-bind (lines length)
      (split-string str #\newline)
    (flet ((%search (&rest args)
                    (let ((linum (- (window-cur-linum) (1- length))))
                      (when (< 0 linum)
                        (apply 'search str
                               (join (string #\newline)
                                     (buffer-take-lines (window-buffer)
                                                        linum
                                                        length))
                               :from-end t
                               args)))))
      (search-step str
                   #'(lambda ()
                       (%search :end2 (window-cur-col)))
                   #'(lambda ()
                       (%search))
                   #'(lambda () (prev-line 1))
                   #'(lambda (i)
                       (prev-line (1- length))
                       (beginning-of-line)
                       (next-char i))
                   #'bobp))))

(defvar *replace-before-string* nil)
(defvar *replace-after-string* nil)

(defun query-replace-before-after ()
  (let ((before)
        (after))
    (setq before
          (minibuf-read-string
           (if *replace-before-string*
               (format nil "Before (~a with ~a): "
                       *replace-before-string*
                       *replace-after-string*)
               "Before: ")))
    (when (equal "" before)
      (cond (*replace-before-string*
             (setq before *replace-before-string*)
             (setq after *replace-after-string*)
             (return-from query-replace-before-after
               (values before after)))
            (t
             (minibuf-print "Before string is empty")
             (return-from query-replace-before-after
               (values nil nil)))))
    (setq after (minibuf-read-string "After: "))
    (setq *replace-before-string* before)
    (setq *replace-after-string* after)
    (values before after)))

(define-key *global-keymap* (kbd "M-C-r") 'query-replace)
(define-command query-replace () ()
  (multiple-value-bind (before after)
      (query-replace-before-after)
    (when (and before after)
      (do ((n (length before))
           (pass-through nil))
          (nil)
        (unless (search-forward before)
          (return))
        (minibuf-print (format nil "Replace ~s with ~s" before after))
        (prev-char n)
        (unless pass-through (window-update-all))
        (do () (nil)
          (let ((c (unless pass-through (getch))))
            (cond
             ((or pass-through (char= c #\y))
              (buffer-delete-char (window-buffer)
                                  (window-cur-linum) (window-cur-col) n)
              (insert-string after)
              (return))
             ((char= c #\n)
              (next-char n)
              (return))
             ((char= c #\!)
              (setq pass-through t))))))
      (minibuf-clear))
    t))

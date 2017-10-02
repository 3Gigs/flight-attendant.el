;;; elpy-shell.el --- Interactive Python support for elpy -*- lexical-binding: t -*-
;;
;; Copyright (C) 2012-2016  Jorgen Schaefer
;;
;; Author: Jorgen Schaefer <contact@jorgenschaefer.de>, Rainer Gemulla <rgemulla@gmx.de>
;; URL: https://github.com/jorgenschaefer/elpy
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License
;; as published by the Free Software Foundation; either version 3
;; of the License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program. If not, see <http://www.gnu.org/licenses/>.
;;
;;; Commentary:
;;
;; Adds support for interactive Python to elpy
;;
;;; Code:

;;;;;;;;;;;;;;;;;;;;;;
;;; User customization

(defcustom elpy-dedicated-shells nil
  "Non-nil if Elpy should use dedicated shells.

Elpy can use a unique python shell for all buffers and support
manually started dedicated shells. Setting this option to non-nil
force the creation of dedicated shells for each buffers."
  :type 'boolean
  :group 'elpy)

(defcustom elpy-shell-display-buffer-after-send nil ;
  "Whether to display the Python shell after sending something to it."
  :type 'boolean
  :group 'elpy)

(defcustom elpy-shell-echo-output 'when-shell-not-visible
  "Whether to echo the Python shell output in the echo area after input has been sent to the shell.

  Possible choices are nil (=never), when-shell-not-visible, or
  t (=always)."
  :type '(choice (const :tag "Never" nil)
                 (const :tag "When shell not visible" when-shell-not-visible)
                 (const :tag "Always" t))
  :group 'elpy)

(defcustom elpy-shell-echo-input t
  "Whether to echo input sent to the Python shell as input in the
shell buffer."
  :type 'boolean
  :group 'elpy)

(defcustom elpy-shell-echo-input-cont-prompt t
  "Whether to show a continuation prompt when echoing multi-line
input to the Python shell."
  :type 'boolean
  :group 'elpy)

(defcustom elpy-shell-echo-input-lines-head 10
  "Maximum number of lines to show before truncating input echoed
in the Python shell."
  :type 'integer
  :group 'elpy)

(defcustom elpy-shell-echo-input-lines-tail 10
  "Maximum number of lines to show after truncating input echoed
in the Python shell."
  :type 'integer
  :group 'elpy)

;;;;;;;;;;;;;;;
;;; Shell setup

(defun elpy-use-ipython (&optional ipython)
  "Set defaults to use IPython instead of the standard interpreter.

With prefix arg, prompt for the command to use."
  (interactive (list (when current-prefix-arg
                       (read-file-name "IPython command: "))))
  (when (not ipython)
    (setq ipython "ipython"))
  (when (not (executable-find ipython))
    (error "Command %S not found" ipython))
  ;; Needed for IPython 5+
  (setenv "IPY_TEST_SIMPLE_PROMPT" "1")
  (cond
   ;; Emacs 24 until 24.3
   ((boundp 'python-python-command)
    (setq python-python-command ipython))
   ;; Emacs 24.3
   ((and (version<= "24.3" emacs-version)
         (not (boundp 'python-shell-interpreter-interactive-arg)))
    ;; This is from the python.el commentary.
    ;; Settings for IPython 0.11:
    (setq python-shell-interpreter ipython
          python-shell-interpreter-args ""
          python-shell-prompt-regexp "In \\[[0-9]+\\]: "
          python-shell-prompt-output-regexp "Out\\[[0-9]+\\]: "
          python-shell-completion-setup-code
          "from IPython.core.completerlib import module_completion"
          python-shell-completion-module-string-code
          "';'.join(module_completion('''%s'''))\n"
          python-shell-completion-string-code
          "';'.join(get_ipython().Completer.all_completions('''%s'''))\n"))
   ;; Emacs 24.4
   ((boundp 'python-shell-interpreter-interactive-arg)
    (setq python-shell-interpreter ipython
          python-shell-interpreter-args "-i")
    ;; Windows requires some special handling here, see #422
    (let ((exe "C:\\Python27\\python.exe")
          (ipython_py "C:\\Python27\\Scripts\\ipython-script.py"))
      (when (and (eq system-type 'windows-nt)
                 (file-exists-p exe)
                 (file-exists-p ipython_py))
        (setq python-shell-interpreter exe
              python-shell-interpreter-args "-i " + ipython_py))))
   (t
    (error "I don't know how to set ipython settings for this Emacs"))))

(defun elpy-use-cpython (&optional cpython)
  "Set defaults to use the standard interpreter instead of IPython.

With prefix arg, prompt for the command to use."
  (interactive (list (when current-prefix-arg
                       (read-file-name "Python command: "))))
  (when (not cpython)
    (setq cpython "python"))
  (when (not (executable-find cpython))
    (error "Command %S not found" cpython))
  (cond
   ;; Emacs 24 until 24.3
   ((boundp 'python-python-command)
    (setq python-python-command cpython))
   ;; Emacs 24.3 and onwards.
   ((and (version<= "24.3" emacs-version)
         (not (boundp 'python-shell-interpreter-interactive-arg)))
    (setq python-shell-interpreter cpython
          python-shell-interpreter-args "-i"
          python-shell-prompt-regexp ">>> "
          python-shell-prompt-output-regexp ""
          python-shell-completion-setup-code
          "try:
    import readline
except ImportError:
    def __COMPLETER_all_completions(text): []
else:
    import rlcompleter
    readline.set_completer(rlcompleter.Completer().complete)
    def __COMPLETER_all_completions(text):
        import sys
        completions = []
        try:
            i = 0
            while True:
                res = readline.get_completer()(text, i)
                if not res: break
                i += 1
                completions.append(res)
        except NameError:
            pass
        return completions"
          python-shell-completion-module-string-code ""
          python-shell-completion-string-code
          "';'.join(__COMPLETER_all_completions('''%s'''))\n"))
   ;; Emacs 24.4
   ((boundp 'python-shell-interpreter-interactive-arg)
    (setq python-shell-interpreter cpython
          python-shell-interpreter-args "-i"))
   (t
    (error "I don't know how to set ipython settings for this Emacs"))))


;;;;;;;;;;;;;;;;;;
;;; Shell commands

(defvar elpy--shell-last-py-buffer nil
  "Help keep track of python buffer when changing to pyshell.")

(defun elpy-shell-display-buffer ()
  "Display inferior Python process buffer."
  (display-buffer (process-buffer (elpy-shell-get-or-create-process))
                  nil
                  'visible))

;; better name would be pop-to-shell
(defun elpy-shell-switch-to-shell ()
  "Switch to inferior Python process buffer."
  (interactive)
  (setq elpy--shell-last-py-buffer (buffer-name))
  (pop-to-buffer (process-buffer (elpy-shell-get-or-create-process))))

(defun elpy-shell-switch-to-buffer ()
  "Switch from inferior Python process buffer to recent Python buffer."
  (interactive)
  (pop-to-buffer elpy--shell-last-py-buffer))

(defun elpy-shell-switch-to-shell-in-current-window ()
  (interactive)
  (setq elpy--shell-last-py-buffer (buffer-name))
  (switch-to-buffer (process-buffer (elpy-shell-get-or-create-process))))

(defun elpy-shell-switch-to-buffer-in-current-window ()
  (interactive)
  (switch-to-buffer elpy--shell-last-py-buffer))

(defun elpy-shell-kill (&optional kill-buff)
  "Kill the current python shell.

If `elpy-dedicated-shells' is non-nil,
kill the current buffer dedicated shell.

If KILL-BUFF is non-nil, also kill the associated buffer."
  (interactive)
  (let ((shell-buffer (python-shell-get-buffer)))
    (cond
     (shell-buffer
      (delete-process shell-buffer)
      (when kill-buff
	(kill-buffer shell-buffer))
      (message "Killed %s shell" shell-buffer))
     (t
      (message "No python shell to kill")))))

(defun elpy-shell-kill-all (&optional kill-buffers ask-for-each-one)
  "Kill all active python shells.

If KILL-BUFFERS is non-nil, also kill the associated buffers.
If ASK-FOR-EACH-ONE is non-nil, ask before killing each python process.
"
  (interactive)
  (let ((python-buffer-list ()))
    ;; Get active python shell buffers and kill inactive ones (if asked)
    (loop for buffer being the buffers do
	  (when (and (buffer-name buffer)
		     (string-match (rx bol "*Python" (opt "[" (* (not (any "]"))) "]") "*" eol)
				   (buffer-name buffer)))
	    (if (get-buffer-process buffer)
		(push buffer python-buffer-list)
	      (when kill-buffers
		(kill-buffer buffer)))))
    (cond
     ;; Ask for each buffers and kill
     ((and python-buffer-list ask-for-each-one)
      (loop for buffer in python-buffer-list do
	    (when (y-or-n-p (format "Kill %s ?" buffer))
		(delete-process buffer)
		(when kill-buffers
		  (kill-buffer buffer)))))
     ;; Ask and kill every buffers
     (python-buffer-list
      (if (y-or-n-p (format "Kill %s python shells ?" (length python-buffer-list)))
	  (loop for buffer in python-buffer-list do
		(delete-process buffer)
		(when kill-buffers
		  (kill-buffer buffer)))))
     ;; No shell to close
     (t
      (message "No python shell to close")))))

(defun elpy-shell-get-or-create-process (&optional sit)
  "Get or create an inferior Python process for current buffer and return it.

If SIT is non-nil, sit for that many seconds after creating a
Python process. This allows the process to start up."
  (let* ((bufname (format "*%s*" (python-shell-get-process-name nil)))
         (dedbufname (format "*%s*" (python-shell-get-process-name t)))
         (proc (get-buffer-process bufname))
         (dedproc (get-buffer-process dedbufname)))
    (if elpy-dedicated-shells
        (if dedproc
            dedproc
          (run-python (python-shell-parse-command) t t)
          (when sit
            (sit-for sit))
          (get-buffer-process dedbufname))
      (if dedproc
          dedproc
        (if proc
            proc
          (run-python (python-shell-parse-command) nil t)
          (when sit
            (sit-for sit))
          (get-buffer-process bufname))))))

(defun elpy-shell--ensure-shell-running ()
  "Ensure that the Python shell for the current buffer is running.

If the shell is not running, waits a while so that the first
prompt is visible and commands can be sent to the shell."
  ;; this should be enough time to start the shell and show the first prompt
  (elpy-shell-get-or-create-process 3))

(defun elpy-shell--region-without-indentation (beg end)
  "Return the current region as a string, but without indentation."
  (if (= beg end)
      ""
    (let ((region (buffer-substring beg end))
          (indent-level nil)
          (indent-tabs-mode nil))
      (with-temp-buffer
        (insert region)
        (goto-char (point-min))
        (while (< (point) (point-max))
          (cond
           ((and (not indent-level)
                 (not (python-info-current-line-empty-p)))
            (setq indent-level (current-indentation)))
           ((and indent-level
                 (not (python-info-current-line-empty-p))
                 (< (current-indentation)
                    indent-level))
            (error "Can't adjust indentation, consecutive lines indented less than starting line")))
          (forward-line))
        (indent-rigidly (point-min)
                        (point-max)
                        (- indent-level))
        ;; 'indent-rigidly' introduces tabs despite the fact that 'indent-tabs-mode' is nil
        ;; 'untabify' fix that
	(untabify (point-min) (point-max))
        (buffer-string)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Flash input sent to shell

;; functions for flashing a region; only flashes when package eval-sexp-fu is
;; loaded and its minor mode enabled
(defun elpy-shell--flash-and-message-region (begin end)
  "Briefly flashes the region from BEGIN to END when
eval-sexp-fu-flash-mode is active.

Also diplays a message holding the first line of the region being sent."
  (when (> end begin)
    (save-excursion
      (goto-char begin)
      (end-of-line)
      (if (<= end (point))
          (message "Sent: %s" (string-trim (thing-at-point 'line)))
        (message "Sent: %s..." (string-trim (thing-at-point 'line)))))
    (when (bound-and-true-p eval-sexp-fu-flash-mode)
      (multiple-value-bind (bounds hi unhi eflash) (eval-sexp-fu-flash (cons begin end))
        (eval-sexp-fu-flash-doit (lambda () t) hi unhi)))))

;;;;;;;;;;;;;;;;;;;
;; Helper functions

(defun elpy-shell--current-line-else-p ()
  (eq (string-match-p "\\s-*el\\(?:se:\\|if[^\w]\\)" (thing-at-point 'line)) 0))

(defun elpy-shell--current-line-indented-p ()
  (eq (string-match-p "\\s-+[^\\s-]+" (thing-at-point 'line)) 0))

(defun elpy-shell--current-line-really-empty-p ()
  "Whether the current line is really empty.

Whitespace is ignored, but comment lines don't count as empty lines."
  (eq (string-match-p "\\s-*$" (thing-at-point 'line)) 0))

(defun elpy-shell--skip-empty-and-comment-lines (&optional backwards)
  "Move the point to the next non-empty non-comment line.

Point is not moved if it is on a non-empty non-comment line. If
BACKWARDS is non-nil, go backwards."
  (if backwards
      (while (and (or (elpy-shell--current-line-really-empty-p)
                      (python-info-current-line-comment-p))
                  (not (eq (point) (point-min))))
        (forward-line -1))
    (while (and (or (elpy-shell--current-line-really-empty-p)
                    (python-info-current-line-comment-p))
                (not (eq (point) (point-max))))
      (forward-line))))

(defun elpy-shell--current-line-defun-p ()
  "Whether a function definition starts at the current line."
  (eq (string-match-p
       "\\s-*\\(?:def\\|async\\s-+def\\)\\s\-"
       (thing-at-point 'line))
      0))

;;;;;;;;;;
;; Echoing

(defmacro elpy-shell--with-maybe-echo (body)
  `(elpy-shell--with-maybe-echo-output
    (elpy-shell--with-maybe-echo-input
     ,body)))

(defmacro elpy-shell--with-maybe-echo-input (body)
  "Run BODY so that it adheres elpy-shell-echo-input and
elpy/shell-display-buffer."
  `(progn
     (elpy-shell--enable-echo)
     (prog1
         (if elpy-shell-display-buffer-after-send
             (prog1 (progn ,body)
               (elpy-shell-display-buffer))
           (cl-flet ((elpy-shell-display-buffer () ()))
             (progn ,body)))
       (elpy-shell--disable-echo))))

(defmacro elpy-shell--with-maybe-echo-output (body)
  "Run BODY and grab shell output according to elpy/shell-echo-output."
  `(let* ((process (elpy-shell--ensure-shell-running))
          (shell-visible (or elpy-shell-display-buffer-after-send
                             (get-buffer-window (process-buffer process)))))
     (if (cond
          ((null elpy-shell-echo-output) t)
          ((eq elpy-shell-echo-output 'when-shell-not-visible) shell-visible))
         (progn ,body)
       (let ((comint-preoutput-filter-functions
              '(elpy-shell--shell-output-filter))
             (python-shell-output-filter-in-progress t)
             (inhibit-quit t))
         (or
          (with-local-quit
            (progn ,body)
            (sit-for eval-sexp-fu-flash-duration)
            (while python-shell-output-filter-in-progress
              ;; `elpy-shell--shell-output-filter' takes care of setting
              ;; `python-shell-output-filter-in-progress' to NIL after it
              ;; detects end of output.
              (accept-process-output process))
            (prog1
                (progn
                  ;; this is delayed so that the flash overlay stays visible
                  (when (not (string-empty-p python-shell-output-filter-buffer))
                    (run-at-time "1 millisec" nil
                                 (lambda (s)
                                   (let (message-log-max) ;; no need to log in messages
                                     (message "%s" s)))
                                 (string-trim python-shell-output-filter-buffer)))
                  python-shell-output-filter-buffer)
              (setq python-shell-output-filter-buffer nil)))
          (with-current-buffer (process-buffer process)
            (comint-interrupt-subjob)))))))

(defun elpy-shell--shell-output-filter (string)
  "Filter used in `elpy/capture-output' to grab output.

No actual filtering is performed. STRING is the output received
to this point from the process. This filter saves received output
from the process in `python-shell-output-filter-buffer' and stops
receiving it after detecting a prompt at the end of the buffer."
  (setq
   string (ansi-color-filter-apply string)
   python-shell-output-filter-buffer
   (concat python-shell-output-filter-buffer string))
  (when (python-shell-comint-end-of-output-p
         python-shell-output-filter-buffer)
    ;; Output ends when `python-shell-output-filter-buffer' contains
    ;; the prompt attached at the end of it.
    (setq python-shell-output-filter-in-progress nil
          python-shell-output-filter-buffer
          (substring python-shell-output-filter-buffer
                     0 (match-beginning 0))))
  string)

(defun elpy-shell--insert-and-font-lock (string face &optional no-font-lock)
  "Inject STRING into the Python shell buffer."
  (let ((from-point (point)))
    (insert string)
    (if (not no-font-lock)
        (add-text-properties from-point (point)
                             (list 'front-sticky t 'font-lock-face face)))))

(defun elpy-shell--append-to-shell-output (string &optional no-font-lock prepend-cont-prompt)
  "Appends the given STRING to the output of the Python shell
and (unless NO-FONT-LOCK is set) formats it as input. Prepends a
continuation promt if specified."
  (let ((buffer (current-buffer)))
    (set-buffer (process-buffer (elpy-shell-get-or-create-process)))
    (let ((initial-point (point))
          (mark-point (process-mark (elpy-shell-get-or-create-process))))
      (goto-char mark-point)
      (if prepend-cont-prompt
          (let* ((column (+ (- (point) (progn (forward-line -1) (end-of-line) (point))) 1))
                 (prompt (concat (make-string (max 0 (- column 7)) ? ) "...: "))
                 (lines (split-string string "\n")))
            (goto-char mark-point)
            (elpy-shell--insert-and-font-lock (car lines) 'comint-highlight-input no-font-lock)
            (if (cdr lines)
                ;; no additional newline at end for multiline
                (dolist (line (cdr lines))
                  (insert "\n")
                  (elpy-shell--insert-and-font-lock prompt 'comint-highlight-prompt no-font-lock)
                  (elpy-shell--insert-and-font-lock line 'comint-highlight-input no-font-lock))
              ;; but put one for single line
              (insert "\n")))
        (elpy-shell--insert-and-font-lock string 'comint-highlight-input no-font-lock))
      (set-marker (process-mark (python-shell-get-process)) (point))
      (goto-char initial-point))
    (set-buffer buffer)))

(defun elpy-shell--string-head-lines (string n)
  "Extracts the first N lines from STRING."
  (let* ((any "\\(?:.\\|\n\\)")
         (line "\\(?:\\(?:.*\n\\)\\|\\(?:.+\\'\\)\\)")
         (lines (concat line "\\{" (number-to-string n) "\\}"))
         (regexp (concat "\\`" "\\(" lines "\\)")))
    (if (string-match regexp string)
        (match-string 1 string)
      string)))

(defun elpy-shell--string-tail-lines (string n)
  "Extracts the last N lines from STRING."
  (let* ((any "\\(?:.\\|\n\\)")
         (line "\\(?:\\(?:.*\n\\)\\|\\(?:.+\\'\\)\\)")
         (lines (concat line "\\{" (number-to-string n) "\\}"))
         (regexp (concat "\\(" lines "\\)" "\\'")))
    (if (string-match regexp string)
        (match-string 1 string)
      string)))

(defun elpy-shell--python-shell-send-string-echo-advice (string &optional process msg)
  "Advice to enable echoing of input in the Python shell."
  (interactive)
  (let* ((append-string ; strip setup code from Python shell
          (if (string-match "import codecs, os.*__pyfile = codecs.open.*$" string)
              (replace-match "" nil nil string)
            string))
         (append-string ; here too
          (if (string-match "^# -\\*- coding: utf-8 -\\*-\n*$" append-string)
              (replace-match "" nil nil append-string)
            append-string))
         (append-string ; strip newlines from beginning and white space from end
          (string-trim-right
           (if (string-match "\\`\n+" append-string)
               (replace-match "" nil nil append-string)
             append-string)))
         (head (elpy-shell--string-head-lines append-string elpy-shell-echo-input-lines-head))
         (tail (elpy-shell--string-tail-lines append-string elpy-shell-echo-input-lines-tail))
         (append-string (if (> (length append-string) (+ (length head) (length tail)))
                            (concat head "...\n" tail)
                          append-string)))

    ;; append the modified string to the shell output; prepend a newline for
    ;; multi-line strings
    (if elpy-shell-echo-input-cont-prompt
        (elpy-shell--append-to-shell-output append-string nil t)
      (elpy-shell--append-to-shell-output
       (concat (if (string-match "\n" append-string) "\n" "")
               append-string
               "\n")))))

(defun elpy-shell--enable-echo ()
  "Enables input echoing when elpy-shell-echo-input is set."
  (when elpy-shell-echo-input
    (advice-add 'python-shell-send-string
                :before 'elpy-shell--python-shell-send-string-echo-advice)))

(defun elpy-shell--disable-echo ()
  "Disables input echoing."
  (advice-remove 'python-shell-send-string
                 'elpy-shell--python-shell-send-string-echo-advice))

;; overwrites python-shell-send-file modified such that: if the file ends with
;; an expression, it's evaluated separately so that the result is recognized by
;; the python shell.  This let's use see the output of the last expression in a
;; multiline statement
;; TODO: might be better to avoid overwriting but use advices instead
(defun python-shell-send-file (file-name &optional process temp-file-name
                                         delete msg)
  "Send FILE-NAME to inferior Python PROCESS.
If TEMP-FILE-NAME is passed then that file is used for processing
instead, while internally the shell will continue to use
FILE-NAME.  If TEMP-FILE-NAME and DELETE are non-nil, then
TEMP-FILE-NAME is deleted after evaluation is performed.  When
optional argument MSG is non-nil, forces display of a
user-friendly message if there's no process running; defaults to
t when called interactively."
  (interactive
   (list
    (read-file-name "File to send: ")   ; file-name
    nil                                 ; process
    nil                                 ; temp-file-name
    nil                                 ; delete
    t))                                 ; msg
  (let* ((process (or process (python-shell-get-process-or-error msg)))
         (encoding (with-temp-buffer
                     (insert-file-contents
                      (or temp-file-name file-name))
                     (python-info-encoding)))
         (file-name (expand-file-name
                     (or (file-remote-p file-name 'localname)
                         file-name)))
         (temp-file-name (when temp-file-name
                           (expand-file-name
                            (or (file-remote-p temp-file-name 'localname)
                                temp-file-name)))))
    (python-shell-send-string
     (format
      (concat
       "import codecs, os, ast;"
       "__pyfile = codecs.open('''%s''', encoding='''%s''');"
       "__code = __pyfile.read().encode('''%s''');"
       "__pyfile.close();"
       (when (and delete temp-file-name)
         (format "os.remove('''%s''');" temp-file-name))
       "__block = ast.parse(__code, '''%s''', mode='exec');"
       "__last = __block.body[-1];" ;; the last statement
       "__isexpr = isinstance(__last,ast.Expr);" ;; is it an expression?
       "__block.body.pop() if __isexpr else None;" ;; if so, remove it
       "exec(compile(__block, '''%s''', mode='exec'));" ;; execute everything else
       "eval(compile(ast.Expression(__last.value), '''%s''', mode='eval')) if __isexpr else None" ;; if it was an expression, it has been removed; now evaluate it
       )
      (or temp-file-name file-name) encoding encoding file-name file-name file-name)
     process)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Navigation commands for sending

(defun elpy-shell--nav-beginning-of-statement ()
  "Moves the point to the beginning of the current or next Python statement.

If the current line starts with a statement, behaves exactly like
python-nav-beginning of statement. If the point is on an empty or
comment line, skips forward to the first line holding a
statement. If the line is an else/elif clause,goes backward to
the beginning of the corresponding if clause.
  "
  (elpy-shell--skip-empty-and-comment-lines)
  (python-nav-beginning-of-statement)
  (let ((p))
    (while (and (not (eq p (point)))
                (elpy-shell--current-line-else-p))
      (elpy-nav-backward-block)
      (setq p (point)))))

;; internal; point needs to be exactly at the beginning of the statement
(defun elpy-shell--nav-end-of-statement ()
  "Moves the point to the end of the current Python statement.

Assumes that the point is precisely at the beginning of a
statement (e.g., after calling
elpy-shell--nav-beginning-of-statement). Correctly handles
if/elif/else statements."
  (let ((indent (current-column))
        (continue t)
        (p))
    (while (and (not (eq p (point)))
                continue)
      ;; check if there is a another block at the same indentation level
      (setq p (point))
      (elpy-nav-forward-block)

      ;; if not, go to the end of the block and done
      (if (eq p (point))
          (progn
            (python-nav-end-of-block)
            (setq continue nil))
        ;; otherwise check if its an else/elif clause
        (unless (elpy-shell--current-line-else-p)
          (forward-line -1)
          (elpy-shell--skip-empty-and-comment-lines t)
          (setq continue nil)))))
  (end-of-line))

(defun elpy-shell--nav-beginning-of-top-statement ()
  "Move the point to the beginning of the current or next top-level statement.

If the point is within a top-level statement, move to its
beginning. Otherwise, move to the beginning of the next top-level
statement.
  "
  (interactive)
  (elpy-shell--nav-beginning-of-statement)
  (let ((p))
    (while (and (not (eq p (point)))
                (elpy-shell--current-line-indented-p))
      (forward-line -1)
      (elpy-shell--skip-empty-and-comment-lines t)
      (elpy-shell--nav-beginning-of-statement))))

(defun elpy-shell--nav-beginning-of-defun ()
  "Move point to the beginning of the function definition containing the current line.

If the current line does not contain a function definition, returns nil, else t."
  (let ((beg-ts (save-excursion (elpy-shell--nav-beginning-of-top-statement) (point)))
        (orig-p (point))
        (max-indent (current-indentation))
        (found))
    (while (and (not found)
                (>= (point) beg-ts))
      (if (and (elpy-shell--current-line-defun-p)
               (<= (current-indentation) max-indent))
          (setq found t)
        (unless (python-info-current-line-empty-p)
          (setq max-indent (min max-indent
                                (- (current-indentation) 1))))
        (forward-line -1)))
    (if found
        (python-nav-beginning-of-statement)
      (goto-char orig-p))
    found))

(defun elpy-shell--nav-beginning-of-group ()
  "Move point to the beginning of the current or next group of top-level statements.

A sequence of top-level statements is a group if they are not
separated by empty lines. (Empty lines within each top-level
statement are ignored though.)

If the point is within a top-level statement, move to the
beginning of the group containing this statement. Otherwise, move
to the first top-level statement below point.
   "
  (elpy-shell--nav-beginning-of-top-statement)
  (while (not (or (elpy-shell--current-line-really-empty-p)
                  (eq (point) (point-min))))
    (unless (python-info-current-line-comment-p)
      (elpy-shell--nav-beginning-of-top-statement))
    (forward-line -1)
    (beginning-of-line))
  (when (elpy-shell--current-line-really-empty-p)
    (forward-line 1)
    (beginning-of-line)))

;;;;;;;;;;;;;;;;;
;;; Send commands

(defun elpy-shell-send-statement-and-step ()
  "Send current or next statement to Python shell and step.

If the current line starts with a statement, send this statement.
If the point is on an empty or comment line, send the next
statement below point. Correctly handles if/else/elif statements.
  "
  (interactive)
  (elpy-shell--ensure-shell-running)
  (let ((beg (progn (elpy-shell--nav-beginning-of-statement)
                    (save-excursion
                      (beginning-of-line)
                      (point))))
        (end (progn (elpy-shell--nav-end-of-statement) (point))))
    (unless (eq beg end)
      (elpy-shell--flash-and-message-region beg end)
        (elpy-shell--with-maybe-echo
         (python-shell-send-string (elpy-shell--region-without-indentation beg end)))))
  (python-nav-forward-statement))

(defun elpy-shell-send-top-statement-and-step ()
  "Send the current top-level statement to the Python shell and step.

If the point is within a top-level statement, send this one.
Otherwise, send the next one below point.
  "
  (interactive)
  (elpy-shell--ensure-shell-running)
  (let* ((beg (progn (elpy-shell--nav-beginning-of-top-statement) (point)))
         (end (progn (elpy-shell--nav-end-of-statement) (point))))
    (elpy-shell--flash-and-message-region beg end)
    (if (string-match-p "\\`[^\n]*\\'" (buffer-substring beg end))
        ;; single line
        (elpy-shell-send-statement-and-step)
      ;; multiple lines
      (elpy-shell--with-maybe-echo
       (python-shell-send-region beg end))
      (setq mark-active nil)
      (python-nav-forward-statement))))

(defun elpy-shell-send-defun-and-step ()
  "Sends the function that contains the current line to the Python shell and steps."
  (interactive)
  (if (elpy-shell--nav-beginning-of-defun)
      (elpy-shell-send-statement-and-step)
    (message "There is no function definition that includes the current line.")))

(defun elpy-shell-send-group-and-step ()
  "Send the current or next group of top-level statements to the Python shell and step.

A sequence of top-level statements is a group if they are not
separated by empty lines. (Empty lines within each top-level
statement are ignored though.)

If the point is within a top-level statement, send the group
around this statement. Otherwise, go to the top-level statement
below point and send the group around this statement.
   "
  (interactive)
  (elpy-shell--ensure-shell-running)
  (let* ((beg (progn (elpy-shell--nav-beginning-of-group) (point)))
         (end (progn
                ;; go forward to end of group
                (unless (python-info-current-line-comment-p)
                  (elpy-shell--nav-end-of-statement))
                (let ((p))
                  (while (not (eq p (point)))
                    (setq p (point))
                    (forward-line)
                    (if (elpy-shell--current-line-really-empty-p)
                        (goto-char p) ;; done
                      (unless (python-info-current-line-comment-p)
                        (elpy-shell--nav-end-of-statement)))))
                (point))))
    (if (> end beg)
        (progn
          (elpy-shell--flash-and-message-region beg end)
          ;; send the region and jump to next statement
          (if (string-match-p "\\`[^\n]*\\'" (buffer-substring beg end))
              ;; single line
              (elpy-shell-send-statement-and-step)
            ;; multiple lines
            (elpy-shell--with-maybe-echo
             (python-shell-send-region beg end))
            (python-nav-forward-statement)))
      (goto-char (point-max)))
    (setq mark-active nil)))

(defun elpy-shell-send-region-or-buffer-and-step ()
  "Send the active region or the buffer to the Python shell."
  (interactive)
  (if (use-region-p)
      (elpy-shell--flash-and-message-region (region-beginning) (region-end))
    (elpy-shell--flash-and-message-region (point-min) (point-max)))
  (elpy-shell--with-maybe-echo
   (elpy-shell--send-region-or-buffer-internal))
  (if (use-region-p)
      (goto-char (region-end))
    (goto-char (point-max))))

(defun elpy-shell--send-region-or-buffer-internal (&optional arg)
  "Send the active region or the buffer to the Python shell.

If there is an active region, send that. Otherwise, send the
whole buffer.

In Emacs 24.3 and later, without prefix argument, this will
escape the Python idiom of if __name__ == '__main__' to be false
to avoid accidental execution of code. With prefix argument, this
code is executed."
  (interactive "P")
  ;; Ensure process exists
  (elpy-shell-get-or-create-process)
  (let ((if-main-regex "^if +__name__ +== +[\"']__main__[\"'] *:")
        (has-if-main nil))
    (if (use-region-p)
        (let ((region (elpy-shell--region-without-indentation
                       (region-beginning) (region-end))))
          (setq has-if-main (string-match if-main-regex region))
          (when (string-match "\t" region)
            (message "Region contained tabs, this might cause weird errors"))
          (python-shell-send-string region))
      (save-excursion
        (goto-char (point-min))
        (setq has-if-main (re-search-forward if-main-regex nil t)))
      (python-shell-send-buffer arg))
    (elpy-shell-display-buffer)
    (when has-if-main
      (message (concat "Removed if __name__ == '__main__' construct, "
                       "use a prefix argument to evaluate.")))))

(defun elpy-shell-send-buffer-and-step ()
  "Send entire buffer to Python shell"
  (interactive)
  (elpy-shell--ensure-shell-running)
  (elpy-shell--flash-and-message-region (point-min) (point-max))
  (elpy-shell--with-maybe-echo
   (python-shell-send-buffer))
  (goto-char (point-max)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Send command variations (with/without step; with/without go)

(defun elpy-shell--send-with-step-go (fun &optional step go)
  "Run a function with STEP and/or GO.

When STEP is nil, keeps point position. When GO is non-nil,
switches focus to Python shell buffer."
  (interactive)
  (let ((orig (point)))
    (call-interactively fun)
    (when (not step)
      (goto-char orig)))
  (when go
    (elpy-shell-switch-to-shell)))

(defun elpy-shell-send-statement ()
  (interactive)
  (elpy-shell--send-with-step-go 'elpy-shell-send-statement-and-step nil nil))

(defun elpy-shell-send-top-statement ()
  (interactive)
  (elpy-shell--send-with-step-go 'elpy-shell-send-top-statement-and-step nil nil))

(defun elpy-shell-send-defun ()
  (interactive)
  (elpy-shell--send-with-step-go 'elpy-shell-send-defun-and-step nil nil))

(defun elpy-shell-send-group ()
  (interactive)
  (elpy-shell--send-with-step-go 'elpy-shell-send-group-and-step nil nil))

(defun elpy-shell-send-region-or-buffer ()
  (interactive)
  (elpy-shell--send-with-step-go 'elpy-shell-send-region-or-buffer-and-step nil nil))

(defun elpy-shell-send-buffer ()
  (interactive)
  (elpy-shell--send-with-step-go 'elpy-shell-send-buffer-and-step nil nil))

(defun elpy-shell-send-statement-and-go ()
  (interactive)
  (elpy-shell--send-with-step-go 'elpy-shell-send-statement-and-step nil t))

(defun elpy-shell-send-top-statement-and-go ()
  (interactive)
  (elpy-shell--send-with-step-go 'elpy-shell-send-top-statement-and-step nil t))

(defun elpy-shell-send-defun-and-go ()
  (interactive)
  (elpy-shell--send-with-step-go 'elpy-shell-send-defun-and-step nil t))

(defun elpy-shell-send-group-and-go ()
  (interactive)
  (elpy-shell--send-with-step-go 'elpy-shell-send-group-and-step nil t))

(defun elpy-shell-send-region-or-buffer-and-go ()
  (interactive)
  (elpy-shell--send-with-step-go 'elpy-shell-send-region-or-buffer-and-step nil t))

(defun elpy-shell-send-buffer-and-go ()
  (interactive)
  (elpy-shell--send-with-step-go 'elpy-shell-send-buffer-and-step nil t))

(defun elpy-shell-send-statement-and-step-and-go ()
  (interactive)
  (elpy-shell--send-with-step-go 'elpy-shell-send-statement-and-step t t))

(defun elpy-shell-send-top-statement-and-step-and-go ()
  (interactive)
  (elpy-shell--send-with-step-go 'elpy-shell-send-top-statement-and-step t t))

(defun elpy-shell-send-defun-and-step-and-go ()
  (interactive)
  (elpy-shell--send-with-step-go 'elpy-shell-send-defun-and-step t t))

(defun elpy-shell-send-group-and-step-and-go ()
  (interactive)
  (elpy-shell--send-with-step-go 'elpy-shell-send-group-and-step t t))

(defun elpy-shell-send-region-or-buffer-and-step-and-go ()
  (interactive)
  (elpy-shell--send-with-step-go 'elpy-shell-send-region-or-buffer-and-step t t))

(defun elpy-shell-send-buffer-and-step-and-go ()
  (interactive)
  (elpy-shell--send-with-step-go 'elpy-shell-send-buffer-and-step t t))


(provide 'elpy-shell)
;;; elpy-shell.el ends here

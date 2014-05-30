;; Verify all the conf marked with FIXME

;; -*- emacs-lisp -*-
;;
;; ===================================================================
;; File ~/.emacs (configuration file for Emacs)
;; Thomas Gambier <thomas_gambier@sdesigns.eu>
;; translated and adaptated from Sébastien Dinot's .emacs :
;;       http://sebastien.dinot.free.fr/dotemacs.html
;; Time-stamp: <2008-11-21 17:44:02>
;; ===================================================================
;;
;;
;; ===================================================================
;;
;; CONTENT:
;;   I   Appearence and interaction
;;        a- Cursor
;;        b- Window
;;        c- Mouse
;;        d- Font colors
;;   II  General edition
;;   III External plugins configuration
;;   IV  Code edition
;;        a- C/C++
;;        b- Verilog
;;        c- Shell
;;        d- Perl
;;   V   Key bindings
;;        a- Overloading key bindings
;;        b- Keys Fxx
;;        c- Buffer cycling
;;        d- Keys for doxygen
;;
;; ===================================================================
;;
;;
;; ===================================================================
;;
;; Some very useful basic commands to remember :
;;
;; C-_ :
;;   Undo the last operation
;; C-x k :
;;   Close an editing buffer (by default, the current buffer)
;; C-x C-right arrow :
;;   Go to next editing buffer in the list
;; C-x C-left arrow :
;;   Go to previous editing buffer in the list
;; C-q <ascii code> RET :
;;   Insert the character with ascii code <ascii code>. By default,
;;   this code is in octal. For example, to insert an indivisible
;;   space whose code ascii is :
;;    - 0xa0 in hexa
;;    - 160 in decimal
;;    - 0240 in octal
;;   you have to type " C-q 2 4 0 RET ". To be able to give this value
;;   in decimal, you have to modify the variable read-quoted-char-radix :
;;   (setq read-quoted-char-radix 10)
;;   When this is done, to insert the same indivisible space, we will
;;   now type " C-q 1 6 0 RET "
;; M-g g <line number> RET :
;;   Go to line <line number>
;;
;; ===================================================================


;; Add the common lisp directory for sigma in the path where emacs will
;; search modules
(if (file-exists-p "/utils/unix_share/elisp/")
  (setq load-path (cons (concat "/utils/unix_share/elisp/") load-path))
)

;; Put the custom option in a separate file to keep this file as clean
;; as possible
(setq custom-file "~/.emacs-custom.el")
(load custom-file 'noerror)


;; ===================================================================
;; ==============   I   Appearence and interaction   =================
;; ===================================================================


;; =========================   a- Cursor   ===========================

;; Cursor appearence : 2 pixels wide bar, to see how to change it, see :
;; http://www.gnu.org/software/emacs/elisp/html_node/Cursor-Parameters.html
(setq default-cursor-type '(bar . 2))

;; Cursor color
(set-cursor-color "red")

;; Blinking cursor
(blink-cursor-mode t)

;; Show the cursor position in the modal line
(setq column-number-mode t)
(setq line-number-mode t)

;; Leave in place the cursor in a scroll through pages. By default,
;; Emacs place the cursor at the beginning or end of the screen
;; depending on the direction of scrolling
(setq scroll-preserve-screen-position t)

;; If this variable is different from 'nil', when one is at the end of
;; a line, a vertical movement of the cursor is accompanied by a
;; horizontal movement to reach the end of the current line. If this
;; is' nil ', the move is strictly vertical.
(setq track-eol t)

;; When the cursor reaches the end of the window, the content moves
;; from one line and not a half-window
(setq scroll-step 1)

;; Keep a single line of context while traveling on a page in the
;; content (press "page up or page down")
(setq next-screen-context-lines 1)


;; =========================   b- Window   ===========================

;; When a line is larger than the display window, Emacs can display it
;; on as many lines as necessary rather than mask the party that
;; exceeds the display. For this to work in any circumstance, it is
;; necessary to set two variables.
;; - truncate-lines : behavior in a buffer occupying the whole width
;;   of the window
;; - truncate-partial-width-windows : behavior in buffer occupying a
;;   fraction of the width of the window (for example, after a
;;   horizontal split with C-x 3) .
;; nil = no truncate , t = truncate
(setq truncate-lines nil)
(setq truncate-partial-width-windows nil)

;; Show time in the status bar (24 hours format)
(display-time)
(setq display-time-24hr-format t)

;; Don't display startup message
(setq inhibit-startup-message t)

;; Displaing of the menu and options bars
;; 1=display     0=do not display
(menu-bar-mode 1)
(tool-bar-mode 1)

;; Specific configuration for use in X-Window
(if window-system
    (progn
      ;; Default size of the window 100 x 60 characters.
      ;; To add a position (in pixels), type the following command :
      ;; (setq initial-frame-alist
      ;;       '((top . 1) (left . 1) (width . 100) (height . 60)))
      (setq initial-frame-alist '((width . 100) (height . 60)))

      ;; Font size used in X
      ;; To choose correctly your prefered font, type "xfontsel" in a shell.
      (set-default-font "-*-fixed-bold-r-*-*-*-130-*-*-*-*-iso10646-*")
    )
)

;; By default, when Emacs is launched in a terminal, it doesn't get
;; the terminal and keyboard configuration. So it doesn't do any
;; conversion of input/output. The following lines ask it to do the
;; conversion based on locales.
(when (and (not window-system) locale-coding-system)
  (set-language-environment locale-coding-system)
  (set-keyboard-coding-system locale-coding-system)
  (set-terminal-coding-system locale-coding-system)
)


;; =========================   c- Mouse   ============================

;; In a "copy-paste" with the mouse, insert text at the mouse position
;; and not at the cursor position
(setq mouse-yank-at-point nil)

;; Support for the mouse wheel.
;; Used alone, the rotation of the wheel causes a scroll of 5 lines
;; per movement. Combined with the Shift key, the scroll is reduced to
;; one line. Combined with the Control key, scrolling is done page (1
;; window height) per page.
(require 'mwheel)
(mouse-wheel-mode 1)

(setq mouse-wheel-scroll-amount '(3 ((shift) . 3))) ;; one line at a time

(setq mouse-wheel-progressive-speed nil) ;; don't accelerate scrolling

(setq mouse-wheel-follow-mouse 't) ;; scroll window under mouse

(setq scroll-step 3)

(defun scroll-down-keep-cursor ()
   ;; Scroll the text one line down while keeping the cursor
   (interactive)
   (scroll-down 2))

(defun scroll-up-keep-cursor ()
   ;; Scroll the text one line up while keeping the cursor
   (interactive)
   (scroll-up 2))

;; Bind the functions to the /-key and the *-key (on the numeric keypad) with:

(global-set-key [kp-divide] 'scroll-down-keep-cursor)
(global-set-key [kp-multiply] 'scroll-up-keep-cursor)


;; =======================   d- Font colors   ========================

;; Maximum syntax colorization in all modes
(require 'font-lock)
(global-font-lock-mode t)
(setq font-lock-maximum-decoration t)

;; Fontlock
;; (set-face-foreground 'font-lock-builtin-face "light yellow")
;; (set-face-foreground 'font-lock-comment-face "dark turquoise")
;; (set-face-foreground 'font-lock-constant-face "green4")
;; (set-face-foreground 'font-lock-doc-face "firebrick2")
;; (set-face-foreground 'font-lock-function-name-face "light yellow")
;; (set-face-foreground 'font-lock-keyword-face "red")
;; (set-face-foreground 'font-lock-string-face "green4")
;; (set-face-foreground 'font-lock-type-face "orange red")
;; (set-face-foreground 'font-lock-variable-name-face "dark goldenrod")
;; (set-face-foreground 'font-lock-warning-face "lightgreen")
;; (set-face-foreground 'region "mistyrose")
;; (set-face-background 'region "firebrick")
;; Note: instead of setting the two following lines, you may call emacs
;; with the --reverse-video option.
(set-background-color "black")
(set-foreground-color "green")
;; (set-foreground-color "lightgrey")

;; Default tab width
(setq default-tab-width 4)

;; =========================   e- Search   ===========================

;; I was meant to not erase the search while scrooling, but it does
(defun isearch-dehighlight ()
  (unless (or (eq last-command-event 'next)
              (eq last-command-event 'prior))
  (when isearch-overlay
    (delete-overlay isearch-overlay))))


;; ===================================================================
;; =====================   II  General edition   =====================
;; ===================================================================

;; When you enter text while a zone is selected, it is overwritten by
;; the text.
(delete-selection-mode 1)

;; Select the text by holding SHIFT
(delete-selection-mode t)

;; Highlighting the selected area
(transient-mark-mode 1)

;; Do not replace spaces with tabs
(setq-default indent-tabs-mode nil)

;; Add newline at the end of the file :
;;   t      = when the file is saved
;;   nil    = never
;;   `visit = as soon as the file is visited
;;   `query = ask when saving the file
(setq require-final-newline 'query)

;; Active minor mode ffap (Find File At Point) to be able to open file
;; easily. For example, typing C-x C-f with the cursor over a link
;; location will automaticaly fill the minibuffer with this link
;; location
(ffap-bindings)

;; Data encoding conversion when doing a copy / paste from other
;; X softwares
;; The value " compound-text-with-extensions " make the problem of
;; accented letters conversion disappear:
;;   é => ^[%/1\200\214iso8859-15^B
;; This function requires emacs version > 21
(if (>= emacs-major-version 21)
  (setq selection-coding-system 'compound-text-with-extensions)
)

;; Default major mode of Emacs
;;   - at startup of Emacs :
;; (setq initial-major-mode 'shell-script-mode)
;;   - when creating a new buffer or when opening a file whose type is
;; unknown :
;; (setq default-major-mode 'shell-script-mode)

;; It is tedious to type "yes" to confirm, shorten it to 'y' (ditto for
;; "no" now "n").
(fset 'yes-or-no-p 'y-or-n-p)

;; Remove the backup files when quitting (you know, these famous
;; files whose names end with "~") .
(setq make-backup-files nil)

;; The down arrow does not extend the buffer at end of file (only an
;; explicit return does).
(setq next-line-add-newlines nil)

;; Break lines if they get longer than 70 (value of variable
;; 'fill-colummn') characters in text mode
(add-hook 'text-mode-hook 'turn-on-auto-fill)

;; Selecting the editing mode based on the file name.
(setq auto-mode-alist
  (append
    '(("\\.sh$" . sh-mode)
      ("bash" . sh-mode)
      ("profile" . sh-mode)
      ("Makefile$" . makefile-mode)
      ("makefile$" . makefile-mode)
      ("\\.mk$" . makefile-mode)
      ("\\.c$"  . c-mode)
      ("\\.h$"  . c++-mode)
      ("\\.cc$" . c++-mode)
      ("\\.hh$" . c++-mode)
      ("\\.cpp$"  . c++-mode)
      ("\\.hpp$"  . c++-mode)
      ("\\.pgc$"  . c++-mode)  ; Files " Embedded PostgreSQL in C "
      ("\\.p[lm]$" . perl-mode)
      ("\\.el$" . emacs-lisp-mode)
      ("\\.emacs.*$" . emacs-lisp-mode)
      ("\\.l$" . lisp-mode)
      ("\\.lisp$" . lisp-mode)
      ("\\.txt$" . text-mode)
      ("\\.sgml$" . xml-mode)
      ("\\.xml$" . xml-mode)
      ("\\.xsl$" . xml-mode)
      ("\\.svg$" . xml-mode)
      ("\\.[sx]?html?$" . xml-mode)
      ("\\.tpl$" . xml-mode)
      ("\\.php$" . php-mode)
      ("\\.inc$" . php-mode)
      ("\\.awk$" . awk-mode)
      ("\\.tex$" . latex-mode)
      ("\\.ad\\(a\\|b\\|c\\|s\\)$" . ada-mode)
      ("\\.aadl$" . aadl-mode)
      ("\\.v$" . verilog-mode)
      ("\\.sv$" . verilog-mode)
      ("\\.asm$" . c-mode)
      )
     auto-mode-alist
  )
)



;; ===================================================================
;; =============   III External plugins configuration   ==============
;; ===================================================================


;; Highlight invisible characters such as spaces, tabs, newline, ...
;; The mode used works only with emacs version > 22
(if (not t)
(if (>= emacs-major-version 22)
    (progn
      ;; http://emacswiki.org/cgi-bin/wiki/BlankMode
      (require 'blank-mode)
      ;; The mode isn't activated by default, so active it
      (global-blank-mode 1)
      ;; ... including in the text mode where the syntax colorisation
      ;; is inhibited by default
      (add-hook 'text-mode-hook 'blank-mode)
      ;; Choose which characters to show. For a complete list, type
      ;; "C-h v blank-chars RET"
      (setq blank-chars '(tabs trailing space-before-tab hspaces))
      ;; The highlighting is just color, don't add any substitution
      ;; character (mark).
      (setq blank-style '(color))
      ;; Style used for hard spaces
      (set-face-background 'blank-hspace "PaleGreen")
      (set-face-foreground 'blank-hspace "black")
      ;; Style used for spaces at the left of a tab
      (set-face-background 'blank-space-before-tab "orange")
      (set-face-foreground 'blank-space-before-tab "black")
      ;; Style used for tab
      (set-face-background 'blank-tab "lemonchiffon")
      (set-face-foreground 'blank-tab "black")
      ;; Style used for trailing whitespaces
      (set-face-background 'blank-trailing "gold")
      (set-face-foreground 'blank-trailing "black")
    )
)
)

;; Show matching brackets (systematically and not only after the
;; strike)
(require 'paren)
(show-paren-mode t)
(setq blink-matching-paren t)
(setq blink-matching-paren-on-screen t)
(setq show-paren-style 'expression)
(setq blink-matching-paren-dont-ignore-comments t)
(set-face-background 'show-paren-match-face "dark slate grey")


;; Saving history (open files, invoked functions, regular expressions typed,
;; etc.) from one session to another.
;; FIXME
;; (require 'session)
;; (add-hook 'after-init-hook 'session-initialize)
;; (setq session-initialize '(de-saveplace session places keys menus))

;; Give a menu to java mode
;; (require 'java-mode-menu)

;; Insert some usefull macros. See usefull_macros.el in
;; /utils/unix_share/elisp to have more details
(autoload 'rev-buffer "useful-macros.el")

;; ===================================================================
;; ======================   IV  Code edition   =======================
;; ===================================================================


;; ====================   a- C/C++ code edition   ====================

;; Load C/C++ mode
(require 'cc-mode)

;; Load cscope
;; (require 'xcscope)

;; Setting a style (ie a layout) with my little habits. The meanings
;; of various parameters is explained in the manual mode CC,
;; especially the parameters for indentations:
;; http://www.delorie.com/gnu/docs/emacs/cc-mode_32.html
;; If you don't like this style or prefer the default one, just
;; comment the line under this definition setting it as the default
;; style...
;; If you prefer a smaller indentation offset see the variable
;; "c-basic-offset"
(defconst my-c-style
  '(;; pressing "tab" should not insert a tab but indent the current
    ;; line depending on the context and rules defined in style.
    (c-tab-always-indent . t)
    ;; Line must not be larger than 78 characters
    (fill-column . 78)
    ;; Indentation offset
    (c-basic-offset . 2)
    ;; Comments on only one line are aligned with the code
    (c-comment-only-line-offset . 0)
    ;; Multi lines comments begin with a simple line '/*'
    (c-hanging-comment-starter-p . t)
    ;; and end with a simple line '*/'
    (c-hanging-comment-ender-p . t)
    ;; Cases where a brace provocs an automatic layout
    (c-hanging-braces-alist .
      ((substatement-open after)
       (brace-list-open)
       (brace-entry-open)
       (block-close . c-snug-do-while)
       (extern-lang-open after)
       (inexpr-class-open after)
       (inexpr-class-close before)))
    ;; Cases where the character " : " force an automatic layout
    (c-hanging-colons-alist .
      ((member-init-intro before)
       (inher-intro)
       (case-label after)
       (label after)
       (access-label after)))
    ;; Automatic cleanup for some layouts
    (c-cleanup-list .
      (scope-operator
       empty-defun-braces
       defun-close-semi))
    ;; How to indent the code. Please see the manual for meaning of
    ;; each parameter. If you want to know which rule is used for a
    ;; line, just look in the minibuffer when pressing "tab"
    (c-offsets-alist .
       (
       (topmost-intro . 0)
       (topmost-intro-cont . 0)
       (arglist-intro . +)
       (arglist-cont . 0)
       ;;(arglist-cont-nonempty . 0)
       (arglist-cont-nonempty . c-lineup-arglist)
       (arglist-close . c-lineup-close-paren)
       (statement . 0)
       (statement-cont . 0)
       (statement-block-intro . +)
       (statement-case-intro . +)
       (statement-case-open . 0)
       (substatement . +)
       (substatement-open . 0)
       (brace-list-open . 0)
       (brace-list-close . 0)
       (brace-list-intro . +)
       (brace-list-entry . 0)
       (brace-entry-open . 0)
       (case-label . +)
       (access-label . -)
       (label . 0)
       (block-open . +)
       (block-close . 0)
       (string . c-lineup-dont-change)
       (comment-intro . c-lineup-comment)
       (c . c-lineup-C-comments)
       (defun-open . 0)
       (defun-close . 0)
       (defun-block-intro . +)
       (else-clause . 0)
       (catch-clause . 0)
       (class-open . 0)
       (class-close . 0)
       (inline-open . 0)
       (inline-close . 0)
       (stream-op . c-lineup-streamop)
       (inclass . ++)
       (extern-lang-open . 0)
       (extern-lang-close . 0)
       (inextern-lang . +)
       (namespace-open . 0)
       (namespace-close . 0)
       (innamespace . +)
       (inher-intro . +)
       (inher-cont . c-lineup-multi-inher)
       (member-init-intro . +)
       (member-init-cont . c-lineup-multi-inher)
       (func-decl-cont . +)
       (cpp-macro . -1000)
       (cpp-macro-cont . c-lineup-dont-change)
       (friend . 0)
       (do-while-closure . 0)
       (inexpr-statement . -)
       (inexpr-class . +)
       (template-args-cont . +)
       (knr-argdecl-intro . +)
      (knr-argdecl . 0)))
    (c-echo-syntactic-information-p . t)
  )
  "My C Programming Style"
)

;; Make the above style the C/C++ default style
(defun my-c-mode-common-hook ()
  (setq indent-tabs-mode nil)
  (c-add-style "PERSONAL" my-c-style t)
)
(add-hook 'c-mode-hook 'my-c-mode-common-hook)
(add-hook 'c++-mode-hook 'my-c-mode-common-hook)

;; Enable HideShow minor mode in C/C++ modes
;; see http://www.emacswiki.org/cgi-bin/wiki/HideShow
(add-hook 'c-mode-common-hook 'hs-minor-mode t)

;; ctypes adds more recognition of the C language syntax (especially
;; for types recognition)
(require 'ctypes)

;; Loading the file describing the C/C++ types non recognized by
;; default (~/elisp/ctypes).
;; (defun my-ctypes-load-hook ()
;;  (ctypes-read-file "~/elisp/ctypes" nil t t)
;; )
;; (add-hook 'ctypes-load-hook 'my-ctypes-load-hook)


;; ===================   b- Verilog code edition   ===================

(require 'verilog-mode)
(setq verilog-align-ifelse t)
(setq verilog-auto-indent-on-newline nil)
(setq verilog-auto-newline nil)
(setq verilog-compiler "verilog -c")
(setq verilog-highlight-translate-off t)
(setq verilog-indent-begin-after-if nil)
(setq verilog-indent-level 2)
(setq verilog-indent-level-behavioral 2)
(setq verilog-indent-level-declaration 2)
(setq verilog-indent-level-directive 2)
(setq verilog-indent-level-module 2)
(setq verilog-minimum-comment-distance 60)


;; ====================   c- Shell code edition   ====================

;; use bash as shell
(setq explicit-shell-file-name "bash")

;; For subprocesses invoked via the shell
;; (e.g., "shell -c command")
(setq shell-file-name explicit-shell-file-name)

;; Basic offset when editing shell
(setq sh-basic-offset 2)

;; Cut lines too long in shell mode
(add-hook 'shell-script-mode-hook 'turn-on-auto-fill)


;; ====================   d- Perl code edition   =====================

;; Load Perl mode (cperl-mode is a better perl-mode).
(require 'cperl-mode)

;; We defines perl-mode as an alias of cperl-mode to avoid having to
;; alter the default statements.
(defalias 'perl-mode 'cperl-mode)

;; Adapt Perl indentation
(add-hook 'cperl-mode-hook 'my-cperl-mode-hook t)
(defun my-cperl-mode-hook ()
  (setq cperl-indent-level 2)
  (setq cperl-continued-statement-offset 0)
  (setq cperl-extra-newline-before-brace t)
)


;; ===================================================================
;; ======================   V   Key bindings   =======================
;; ===================================================================

(autoload 'roll-tab-size-and-c-offset "useful-macros.el")

;; ==============   a - Overloading key bindings   ===================

;; Overloading of the sequence "C x-C-b". Make a buffer-menu rather
;; than list-buffers for the focus directly in the buffer list
(global-set-key [(control x) (control b)] 'buffer-menu)

;; Overloading of the sequence "C-x k". Instead of asking the name of
;; the buffer to destroy it systematically destroys the current
;; buffer.
(global-set-key [(control x) (k)] 'kill-this-buffer)


;; =======================   b - Keys Fxx   ==========================

;; "F1" <=> Comment selected region
;; "F2" <=> Uncomment selected region
;; "F3" <=> Show blank chars
;; "F4" <=> Change tab size
(global-set-key [f1] 'comment-region)
(global-set-key [f2] 'uncomment-region)
(global-set-key [f3] 'global-blank-mode)
(global-set-key [f4] 'roll-tab-size-and-c-offset)

;; "F5" <=> CVS examine
;; "F6" <=> Goto line (alternative to the sequence "M-g g")
;; "F7" <=> Revert a buffer without confirmation
;; "F8" <=> Active the make command (or the last compilation command
;;          used)
(global-set-key [f5] 'cvs-examine)
(global-set-key [f6] 'goto-line)
(global-set-key [f7] 'rev-buffer)
(global-set-key [f8] 'compile)

;; "F9"       <=> Interactive simple replacement
;; "Shift-F9" <=> Interactive replacement with regular expression
;; "F10"      <=> Delete all trailing whitespaces. If emacs version >=
;;                22, the function is native. Otherwise, it's defined
;;                in macros.el
;; "F11"      <=> Delete spaces before tabs in a region
;; "F12"      <=> Show/Hide block of code
(global-set-key [f9]         'query-replace)
(global-set-key [(shift f9)] 'query-replace-regexp)
(global-set-key [f10]        'delete-trailing-whitespace)
(global-set-key [f11]        'blank-cleanup-region)
(global-set-key [f12]        'hs-toggle-hiding)


;; =====================   c - Buffer cycling   ======================

;; Control + Tab         <=> Next buffer
;; Control + Shift + Tab <=> Previous buffer
(global-set-key [C-tab] 'next-buffer)
(global-set-key [C-S-iso-lefttab] 'previous-buffer)

;; Control + x + arrow   <=> Move to the window in the direction of the arrow
(global-set-key (kbd "C-x <up>") 'windmove-up)
(global-set-key (kbd "C-x <down>") 'windmove-down)
(global-set-key (kbd "C-x <right>") 'windmove-right)
(global-set-key (kbd "C-x <left>") 'windmove-left)

;; ====================   d - Keys for doxygen   =====================

;; Hold Control + keypad number
(global-set-key '[C-kp-0] 'doxygen-insert-function-comment)
(global-set-key '[C-kp-5] 'doxygen-insert-file-comment)
(global-set-key '[C-kp-8] 'doxygen-insert-comment)


;; ========================   End of file   ==========================
;; (setq load-path (cons "/users/teixeira/.emacs.local.d/" load-path))
;; (require 'erin)
;; (add-to-list 'auto-mode-alist (cons "web..*.sdesigns.com" 'erin-mode))

(setq x-select-enable-clipboard t)

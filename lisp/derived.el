;;; mode-clone.el -- allow inheritance of major modes.

;; Copyright (C) 1993, 1994 Free Software Foundation, Inc.

;; Author: David Megginson (dmeggins@aix1.uottawa.ca)
;; Maintainer: FSF

;; This file is part of GNU Emacs.

;; GNU Emacs is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 675 Mass Ave, Cambridge, MA 02139, USA.

;;; Commentary:

;; GNU Emacs is already, in a sense, object oriented -- each object
;; (buffer) belongs to a class (major mode), and that class defines
;; the relationship between messages (input events) and methods
;; (commands) by means of a keymap.
;;
;; The only thing missing is a good scheme of inheritance.  It is
;; possible to simulate a single level of inheritance with generous
;; use of hooks and a bit of work -- sgml-mode, for example, also runs
;; the hooks for text-mode, and keymaps can inherit from other keymaps
;; -- but generally, each major mode ends up reinventing the wheel.
;; Ideally, someone should redesign all of Emacs's major modes to
;; follow a more conventional object-oriented system: when defining a
;; new major mode, the user should need only to name the existing mode
;; it is most similar to, then list the (few) differences.
;;
;; In the mean time, this package offers most of the advantages of
;; full inheritance with the existing major modes.  The macro
;; `define-mode-clone' allows the user to make a clone of an existing
;; major mode, with its own keymap.  The new mode will inherit the key
;; bindings of its parent, and will, in fact, run its parent first
;; every time it is called.  For example, the commands
;;
;;  (define-mode-clone hypertext-mode text-mode "Hypertext"
;;    "Major mode for hypertext.\n\n\\{hypertext-mode-map}"
;;    (setq case-fold-search nil))
;;
;;  (define-key hypertext-mode-map [down-mouse-3] 'do-hyper-link)
;;
;; will create a function `hypertext-mode' with its own (sparse)
;; keymap `hypertext-mode-map.'  The command M-x hypertext-mode will
;; perform the following actions:
;;
;; - run the command (text-mode) to get its default setup
;; - replace the current keymap with 'hypertext-mode-map,' which will
;;   inherit from 'text-mode-map'.
;; - replace the current syntax table with
;;   'hypertext-mode-syntax-table', which will borrow its defaults
;;   from the current text-mode-syntax-table.
;; - replace the current abbrev table with
;;   'hypertext-mode-abbrev-table', which will borrow its defaults
;;   from the current text-mode-abbrev table
;; - change the mode line to read "Hypertext"
;; - assign the value 'hypertext-mode' to the 'major-mode' variable
;; - run the body of commands provided in the macro -- in this case,
;;   set the local variable `case-fold-search' to nil.
;; - **run the command (hypertext-mode-setup), which is empty by
;;   default, but may be redefined by the user to contain special
;;   commands (ie. setting local variables like 'outline-regexp')
;;   **NOTE: do not use this option -- it will soon be obsolete.
;; - run anything assigned to 'hypertext-mode-hooks' (obsolete, but
;;   supported for the sake of compatibility).
;;
;; The advantages of this system are threefold.  First, text mode is
;; untouched -- if you had added the new keystroke to `text-mode-map,'
;; possibly using hooks, you would have added it to all text buffers
;; -- here, it appears only in hypertext buffers, where it makes
;; sense.  Second, it is possible to build even further, and clone the
;; clone.  The commands
;;
;;   (define-mode-clone html-mode hypertext-mode "HTML")
;;   [various key definitions]
;; 
;; will add a new major mode for HTML with very little fuss.
;;
;; Note also the function `clone-class,' which returns the non-clone
;; major mode which a clone is based on (ie. NOT necessarily the
;; immediate parent).
;;
;; (clone-class 'text-mode) ==> text-mode
;; (clone-class 'hypertext-mode) ==> text-mode
;; (clone-class 'html-mode) ==> text-mode

;;; Code:

;; PUBLIC: define a new major mode which inherits from an existing one.

;;;###autoload
(defmacro define-mode-clone (child parent name &optional docstring &rest body)
  "Create a new mode which is similar to an old one.

The arguments to this command are as follow:

PARENT:    the name of the command for the parent mode (ie. text-mode).
CHILD:     the name of the command for the clone mode.
NAME:      a string which will appear in the status line (ie. \"Hypertext\")
DOCSTRING: an optional documentation string--if you do not supply one,
           the function will attempt to invent something useful.
BODY:      forms to execute just before running the
           hooks for the new mode.

The following simple command would clone LaTeX mode into
LaTeX-Thesis mode:

  (define-mode-clone LaTeX-thesis-mode LaTeX-mode \"LaTeX-Thesis\")

You could then make new key bindings for `LaTeX-thesis-mode-map'
without changing regular LaTeX mode.  In this example, BODY is empty,
and DOCSTRING is generated by default.

On a more complicated level, the following command would clone
sgml-mode and change the variable `case-fold-search' to nil:

  (define-mode-clone article-mode sgml-mode \"Article\"
    \"Major mode for editing technical articles.\"
    (setq case-fold-search nil))

Note that if the documentation string had been left out, it would have
been generated automatically, with a reference to the keymap."

					; Some trickiness, since what
					; appears to be the docstring
					; may really be the first
					; element of the body.
  (if (and docstring (not (stringp docstring)))
      (progn (setq body (cons docstring body))
	     (setq docstring nil)))
  (setq docstring (or docstring (clone-make-docstring parent child)))

  (` (progn 
       (clone-init-mode-variables (quote (, child)))
       (defun (, child) ()
	 (, docstring)
	 (interactive)
					; Run the parent.
	 ((, parent))
					; Identify special modes.
	 (if (get (quote (, parent)) 'special)
	     (put (quote (, child)) 'special t))
					; Identify the child mode.
	 (setq major-mode (quote (, child)))
	 (setq mode-name (, name))
					; Set up maps and tables.
	 (clone-set-keymap (quote (, child)))
	 (clone-set-syntax-table (quote (, child)))
	 (clone-set-abbrev-table (quote (, child)))
					; Splice in the body (if any).
	 (,@ body)
;;;					; Run the setup function, if
;;;					; any -- this will soon be
;;;					; obsolete.
;;;	 (clone-run-setup-function (quote (, child)))
					; Run the hooks, if any.
	 (clone-run-hooks (quote (, child)))))))


;; PUBLIC: find the ultimate class of a clone mode.

(defun clone-class (mode)
  "Find the class of a major mode.
A mode's class is the first ancestor which is NOT a clone.
Use the `clone-parent' property of the symbol to trace backwards."
  (while (get mode 'clone-parent)
    (setq mode (get mode 'clone-parent)))
  mode)


;; Inline functions to construct various names from a mode name.

(defsubst clone-setup-function-name (mode)
  "Construct a setup-function name based on a mode name."
  (intern (concat (symbol-name mode) "-setup")))

(defsubst clone-hooks-name (mode)
  "Construct a hooks name based on a mode name."
  (intern (concat (symbol-name mode) "-hooks")))

(defsubst clone-map-name (mode)
  "Construct a map name based on a mode name."
  (intern (concat (symbol-name mode) "-map")))

(defsubst clone-syntax-table-name (mode)
  "Construct a syntax-table name based on a mode name."
  (intern (concat (symbol-name mode) "-syntax-table")))

(defsubst clone-abbrev-table-name (mode)
  "Construct an abbrev-table name based on a mode name."
  (intern (concat (symbol-name mode) "-abbrev-table")))


;; Utility functions for defining a clone mode.

(defun clone-init-mode-variables (mode)
  "Initialise variables for a new mode. 
Right now, if they don't already exist, set up a blank keymap, an
empty syntax table, and an empty abbrev table -- these will be merged
the first time the mode is used."

  (if (boundp (clone-map-name mode))
      t
    (eval (` (defvar (, (clone-map-name mode)) 
	       (make-sparse-keymap)
	       (, (format "Keymap for %s." mode)))))
    (put (clone-map-name mode) 'clone-unmerged t))

  (if (boundp (clone-syntax-table-name mode))
      t
    (eval (` (defvar (, (clone-syntax-table-name mode))
	       (make-vector 256 nil)
	       (, (format "Syntax table for %s." mode)))))
    (put (clone-syntax-table-name mode) 'clone-unmerged t))

  (if (boundp (clone-abbrev-table-name mode))
      t
    (eval (` (defvar (, (clone-abbrev-table-name mode))
	       (progn (define-abbrev-table (clone-abbrev-table-name mode) nil)
		      (make-abbrev-table))
	       (, (format "Abbrev table for %s." mode)))))))

(defun clone-make-docstring (parent child)
  "Construct a docstring for a new mode if none is provided."

  (format "This major mode is a clone of `%s', created by `define-mode-clone'.
It inherits all of the parent's attributes, but has its own keymap,
abbrev table and syntax table:

  `%s-map' and `%s-syntax-table'

which more-or-less shadow

  `%s-map' and `%s-syntax-table'

\\{%s-map}" parent child child parent parent child))


;; Utility functions for running a clone mode.

(defun clone-set-keymap (mode)
  "Set the keymap of the new mode, maybe merging with the parent."
  (let* ((map-name (clone-map-name mode))
	 (new-map (eval map-name))
	 (old-map (current-local-map)))
    (if (get map-name 'clone-unmerged)
	(clone-merge-keymaps old-map new-map))
    (put map-name 'clone-unmerged nil)
    (use-local-map new-map)))

(defun clone-set-syntax-table (mode) 
  "Set the syntax table of the new mode, maybe merging with the parent."
  (let* ((table-name (clone-syntax-table-name mode))
	 (old-table (syntax-table))
	 (new-table (eval table-name)))
    (if (get table-name 'clone-unmerged)
	(clone-merge-syntax-tables old-table new-table))
    (put table-name 'clone-unmerged nil)
    (set-syntax-table new-table)))

(defun clone-set-abbrev-table (mode)
  "Set the abbrev table if it exists.  
Always merge its parent into it, since the merge is non-destructive."
  (let* ((table-name (clone-abbrev-table-name mode))
	 (old-table local-abbrev-table)
	 (new-table (eval table-name)))
    (clone-merge-abbrev-tables old-table new-table)
    (setq local-abbrev-table new-table)))

;;;(defun clone-run-setup-function (mode)
;;;  "Run the setup function if it exists."

;;;  (let ((fname (clone-setup-function-name mode)))
;;;    (if (fboundp fname)
;;;	(funcall fname))))

(defun clone-run-hooks (mode)
  "Run the hooks if they exist."

  (let ((hooks-name (clone-hooks-name mode)))
    (if (boundp hooks-name)
	(run-hooks hooks-name))))

;; Functions to merge maps and tables.

(defun clone-merge-keymaps (old new)
  "Merge an old keymap into a new one.
The old keymap is set to be the cdr of the new one, so that there will
be automatic inheritance."
  (setcdr (nthcdr (1- (length new)) new) old))

(defun clone-merge-syntax-tables (old new)
  "Merge an old syntax table into a new one.
Where the new table already has an entry, nothing is copied from the old one."
  (let ((idx 0)
	(end (min (length new) (length old))))
    (while (< idx end)
      (if (not (aref new idx))
	  (aset new idx (aref old idx)))
      (setq idx (1+ idx)))))

(defun clone-merge-abbrev-tables (old new)
  "Merge an old abbrev table into a new one.
This function requires internal knowledge of how abbrev tables work,
presuming that they are obarrays with the abbrev as the symbol, the expansion
as the value of the symbol, and the hook as the function definition.
This could well break with some future version of Gnu Emacs."
  (mapatoms 
   (function 
    (lambda (symbol)
      (or (intern-soft (symbol-name symbol) new)
	  (define-abbrev new (symbol-name symbol)
	    (symbol-value symbol) (symbol-function symbol)))))
   old))
    
(provide 'mode-clone)

;;; mode-clone.el ends here



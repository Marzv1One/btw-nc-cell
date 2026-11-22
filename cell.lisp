;;;; cell.lisp --- btw: the package this cell's definitions read in.
;;;;
;;;; Written by new-cell. The cell's code is btw.lisp beside it, in
;;;; (in-package #:marzv1one-btw); a (define-cell btw ...) there declares its
;;;; commands, tools and settings: (help :cells).

(defpackage #:marzv1one-btw
  (:use #:cl #:nodecode.kernel #:nodecode.evolved))

(in-package #:marzv1one-btw)

(define-peripheral btw :not-running t)

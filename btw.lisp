;;;; btw.lisp --- /btw: a quick side question to a fresh subagent.
;;;;
;;;; Built on the nodecode-subagents cell: each /btw opens a one-worker
;;;; detached team, seeds it with the tail of this session's transcript,
;;;; waits, and shows the worker's answer inline. This session's own
;;;; conversation is never touched.
;;;;
;;;; SPDX-License-Identifier: MIT

(in-package #:marzv1one-btw)

(defparameter +context-char-budget+ 11000
  "Character budget for the transcript tail; subagents caps shared context at 12000.")

(defparameter +whitespace+ '(#\Space #\Tab #\Newline #\Return))

(defun message-events (session-id)
  "Non-empty user/assistant messages of SESSION-ID, oldest first, as (role . text)."
  (let ((messages '()))
    (dolist (event (nlk:events :session-id session-id :limit 2000))
      (when (typep event 'nlk:message-event)
        (let ((role (nlk:message-event-role event))
              (text (nlk:message-event-content event)))
          (when (and (member role '("user" "assistant") :test #'string=)
                     (stringp text)
                     (plusp (length (string-trim +whitespace+ text))))
            (push (cons role text) messages)))))
    (nreverse messages)))

(defun clip-tail (messages count budget)
  "The newest COUNT messages, trimmed from the oldest end to fit BUDGET characters."
  (let ((kept '())
        (total 0))
    (dolist (message (reverse (last messages count)) (nreverse kept))
      (incf total (+ (length (cdr message)) 16))
      (when (> total budget)
        (return (nreverse kept)))
      (push message kept))))

(defun format-context (messages)
  (format nil "Recent conversation of the parent session, oldest first:~%~%~{~a: ~a~%~}"
          (loop for (role . text) in messages
                collect role collect text)))

(defun last-assistant-reply (session-id)
  "The newest non-empty assistant message of SESSION-ID, or NIL."
  (let ((reply nil))
    (dolist (message (message-events session-id) reply)
      (when (string= (car message) "assistant")
        (setf reply (cdr message))))))

(defvar *btw-worker-model* nil
  "Dynamically bound only while /btw creates its worker.")

(defun prepare-btw-worker (next config node)
  "Pin a /btw child before submission; leave other workers untouched."
  (multiple-value-bind (success failure) (funcall next config node)
    (if (and success *btw-worker-model*)
        (handler-case
            (progn
              (apply #'nlk:record-session-model-selection
                     (getf node :id) *btw-worker-model*)
              (values success failure))
          (error (condition)
            (subagents::update-node
             (getf config :id) (getf node :id)
             (lambda (record)
               (setf (getf record :status) :failed
                     (getf record :error) (princ-to-string condition))))
            (values nil (format nil "failed ~a (~a): model selection: ~a"
                                (getf node :name) (getf node :id) condition))))
        (values success failure))))

(defun btw (args session-id)
  "/btw QUESTION => a quick side answer from a fresh subagent."
  (let ((question (string-trim +whitespace+ (or args "")))
        (session (or session-id nlk:*scribe-session-id*)))
    (when (zerop (length question))
      (return-from btw
        "usage: /btw <question> — a fresh subagent answers a side question, seeded with the recent conversation; this session is untouched."))
    (let ((nlk:*scribe-session-id* session))
      (handler-case
          (let* ((tail (clip-tail (message-events session)
                                  (setting :context-messages)
                                  +context-char-budget+))
                 (context (if tail (format-context tail) "(no prior conversation)"))
                 (assignment (format nil
                                     (concatenate 'string
                                       "Answer the operator's side question below directly and concisely. "
                                       "This is a quick aside (/btw), not a work assignment: do not edit files, "
                                       "do not create agents, and make no board posts; just answer in your reply. "
                                       "Use tools only if the question truly needs one. "
                                       "The shared context is background from the parent conversation.~%~%"
                                       "Question: ~a")
                                     question)))
            (multiple-value-bind (provider model effort) (auxiliary-model session)
              (unless (and provider model)
                (error "No auxiliary model or session model is available for /btw."))
              (let ((*btw-worker-model* (list :provider provider :model model :effort effort)))
                (subagents:task (list (list :name "btw" :task assignment))
                                :context context :await t
                                :timeout-seconds (setting :timeout))))
            (let* ((config (subagents::current-team session))
                   (node (find "btw" (getf config :nodes)
                               :key (lambda (item) (getf item :name))
                               :test #'string=))
                   (reply (and node (last-assistant-reply (getf node :id)))))
              (cond (reply (format nil "btw~%~a" reply))
                    (node (format nil "btw: no answer yet.~%~a"
                                  (subagents::node-status-line node)))
                    (t "btw: the worker started but its team record was not found."))))
        (subagents:subagents-error (condition)
          (format nil "btw: ~a" condition))))))

(defparameter +primer+
  "/btw <question> asks a fresh detached subagent a side question and shows its answer inline.
  The subagent is seeded with the last btw.context_messages user/assistant messages of this
  session (clipped to ~11k characters) as shared context; this session's transcript is untouched.
  Built on nodecode-subagents: each call is a one-worker team, visible to /agents list.
  Its worker uses the configured auxiliary model, or the parent session model at its
  weakest reasoning effort when none is configured. Other workers are unaffected.
  Settings: btw.timeout (seconds to wait, default 120, max 300), btw.context_messages (default 10).
  The command blocks until the answer lands or the timeout passes; on timeout it reports worker status.")

(nle:define-cell btw
  (:section ("btw")
    ("timeout" :integer :default 120 :min 1
               :doc "seconds to wait for the side answer (subagents caps waits at 300)")
    ("context_messages" :integer :default 10 :min 2
                        :doc "recent parent messages handed to the subagent as context"))
  (:settings (lambda (values table)
               (declare (ignore table))
               (when (> (getf values :timeout) 300)
                 (nlk:config-error "btw.timeout is ~d; the maximum wait is 300 seconds"
                                   (getf values :timeout)))
               (when (> (getf values :context-messages) 50)
                 (nlk:config-error "btw.context_messages is ~d; the maximum is 50"
                                   (getf values :context-messages)))
               values))
  (:start (lambda ()
            (hook 'subagents::prepare-node-session "btw-auxiliary-model"
                  #'prepare-btw-worker)
            (on-stop (lambda ()
                       (unhook 'subagents::prepare-node-session "btw-auxiliary-model")))))
  (:command "btw" 'btw
            :catches 'subagents:subagents-error
            :description "Quick side question to a fresh subagent, seeded with the recent conversation")
  (:help :btw "/btw asks a fresh subagent a side question with the recent conversation as context" +primer+))

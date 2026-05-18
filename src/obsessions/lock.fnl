;; obsessions.nvim - lock module
;; Advisory file locking using libuv / flock(2).
;; Each session has a .lock file and an .owner file.
;; The .lock file is flock'd during writes (short-lived).
;; The .owner file records which Neovim instance owns a session (long-lived).

(local M {})
(local uv vim.uv)
(local config (require :obsessions.config))

;;; ---------------------------------------------------------------------------
;;; Owner tracking (which nvim instance is using which session)
;;; ---------------------------------------------------------------------------

(fn owner-path [session-path]
  (.. session-path ".owner"))

(fn M.claim-session [session-path]
  "Mark this Neovim instance as the owner of `session-path`.
   Returns true on success, (nil, err) if another live instance owns it."
  (let [opath (owner-path session-path)]
    ;; Check if an existing owner is still alive
    (when (let [(stat _) (uv.fs_stat opath)] stat)
      (let [(fd _) (uv.fs_open opath "r" 438)]
        (when fd
          (let [(bytes _) (uv.fs_read fd 256)]
            (uv.fs_close fd)
            (when bytes
              (let [(ok info) (pcall vim.json.decode bytes)]
                (when (and ok info info.pid)
                  ;; Check if the PID is still running
                  (let [(result _) (pcall uv.kill info.pid 0)]
                    (when result
                      (values nil
                              (string.format
                                "Session is owned by another Neovim instance (PID %d, server %s)"
                                info.pid (or info.servername "unknown"))))))))))))
    ;; Write our ownership info
    (let [info (vim.json.encode
                 {:pid (uv.getpid)
                  :servername vim.v.servername
                  :timestamp (os.time)})
          (fd err) (uv.fs_open opath "w" 438)]
      (if (not fd)
          (values nil (.. "failed to write owner file: " (or err "unknown")))
          (do
            (uv.fs_write fd info)
            (uv.fs_close fd)
            true)))))

(fn M.release-session [session-path]
  "Release ownership of `session-path`."
  (let [opath (owner-path session-path)]
    (pcall uv.fs_unlink opath)))

;;; ---------------------------------------------------------------------------
;;; Write locking (short-lived, for atomic save operations)
;;; ---------------------------------------------------------------------------

(fn lock-path [session-path]
  (.. session-path ".lock"))

(fn M.acquire-write-lock [session-path]
  "Acquire an exclusive write lock for saving session data.
   Returns a handle (the lock directory path) on success, (nil, err) on failure.
   Caller must pass the handle to `release-write-lock` when done.

   Uses mkdir(2) as the atomic primitive: on POSIX, creating an existing
   directory fails, which lets us detect another writer holding the lock."
  (let [dir-lock (.. (lock-path session-path) ".d")
        (pok rc) (pcall vim.fn.mkdir dir-lock)]
    (if (and pok (= rc 1))
        dir-lock
        (values nil "session is locked by another writer"))))

(fn M.release-write-lock [lock-handle]
  "Release the write lock obtained from `acquire-write-lock`."
  (when lock-handle
    (pcall uv.fs_rmdir lock-handle)))

M

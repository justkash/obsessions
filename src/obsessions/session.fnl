;; obsessions.nvim - session module
;; High-level session management: create, save, load, delete, list, switch.

(local M {})
(local config (require :obsessions.config))
(local storage (require :obsessions.storage))
(local lock (require :obsessions.lock))
(local state (require :obsessions.state))
(local lazy-mod (require :obsessions.lazy))

(var current-session nil)  ;; name of the active session, or nil

;;; ---------------------------------------------------------------------------
;;; Helpers
;;; ---------------------------------------------------------------------------

(fn session-path [name]
  "Return the full file path for a session by name."
  (let [cfg (config.get)]
    (.. cfg.storage-path "/" name ".msgpack")))

(fn last-session-path []
  "Path to the file that stores the name of the last active session."
  (let [cfg (config.get)]
    (.. cfg.storage-path "/.last")))

(fn validate-name [name]
  "Validate a session name. Returns (true) or (nil, err)."
  (if (or (not name) (= (length name) 0))
      (values nil "session name cannot be empty")
      (name:find "[/\\%c]")
      (values nil "session name contains invalid characters")
      true))

(fn save-last-session-name [name]
  "Persist the name of the last active session."
  (let [path (last-session-path)
        (fd _) (vim.uv.fs_open path "w" 438)]
    (when fd
      (vim.uv.fs_write fd name)
      (vim.uv.fs_close fd))))

(fn read-last-session-name []
  "Read the name of the last active session, or nil."
  (let [path (last-session-path)
        (fd _) (vim.uv.fs_open path "r" 438)]
    (when fd
      (let [(stat _) (vim.uv.fs_fstat fd)]
        (when stat
          (let [(bytes _) (vim.uv.fs_read fd stat.size)]
            (vim.uv.fs_close fd)
            (when bytes
              (string.gsub bytes "%s+$" ""))))))))

;;; ---------------------------------------------------------------------------
;;; Public API
;;; ---------------------------------------------------------------------------

(fn M.get-current []
  "Return the name of the currently active session, or nil."
  current-session)

(fn M.list []
  "Return a list of {name, path, mtime} for all saved sessions."
  (let [cfg (config.get)
        dir cfg.storage-path
        sessions []]
    (let [(handle err) (vim.uv.fs_scandir dir)]
      (when handle
        (var entry (vim.uv.fs_scandir_next handle))
        (while entry
          (let [name entry]
            (when (vim.endswith name ".msgpack")
              (let [session-name (name:sub 1 (- (length name) 8))
                    full-path (.. dir "/" name)
                    (stat _) (vim.uv.fs_stat full-path)]
                (table.insert sessions
                              {:name session-name
                               :path full-path
                               :mtime (if stat stat.mtime.sec 0)})))
            (set entry (vim.uv.fs_scandir_next handle))))))
    ;; Sort by mtime descending (most recent first)
    (table.sort sessions (fn [a b] (> a.mtime b.mtime)))
    sessions))

(fn M.exists [name]
  "Return true if a session with `name` exists."
  (storage.exists (session-path name)))

(fn M.save [name]
  "Save the current editor state to the named session.
   If `name` is nil, uses the current session name.
   Returns true on success, (nil, err) on failure."
  (let [session-name (or name current-session)]
    (if (not session-name)
        (values nil "no session name specified and no active session")
        (let [(valid? verr) (validate-name session-name)]
          (if (not valid?)
              (values nil verr)
              (let [path (session-path session-name)
                    ;; Acquire write lock
                    (lock-handle lerr) (lock.acquire-write-lock path)]
                (if (not lock-handle)
                    (values nil (.. "could not acquire lock: " (or lerr "unknown")))
                    (let [;; Capture state
                          editor-state (state.capture session-name)
                          _ (tset editor-state :session-name session-name)
                          ;; Write atomically
                          (ok werr) (storage.write path editor-state)]
                      ;; Release lock
                      (lock.release-write-lock lock-handle)
                      (if (not ok)
                          (values nil (.. "failed to save: " (or werr "unknown")))
                          (do
                            (set current-session session-name)
                            (save-last-session-name session-name)
                            (vim.notify (.. "Obsessions: saved session '" session-name "'")
                                        vim.log.levels.INFO)
                            true))))))))))

(fn M.load [name]
  "Load a session by name, restoring all editor state.
   Returns true on success, (nil, err) on failure."
  (let [(valid? verr) (validate-name name)]
    (if (not valid?)
        (values nil verr)
        (let [path (session-path name)]
          (if (not (storage.exists path))
              (values nil (.. "session '" name "' does not exist"))
              (let [;; Release ownership of the previously-loaded session, if any
                    _ (when (and current-session (not= current-session name))
                        (lock.release-session (session-path current-session)))
                    ;; Claim ownership
                    (claimed? cerr) (lock.claim-session path)]
                (if (not claimed?)
                    (values nil (or cerr "could not claim session"))
                    (let [;; Read session data
                          (session-data rerr) (storage.read path)]
                      (if (not session-data)
                          (values nil (.. "failed to read session: " (or rerr "unknown")))
                          (let [cfg (config.get)
                                lazy? cfg.lazy-load-buffers]
                            ;; Clean up previous lazy autocmds
                            (lazy-mod.cleanup)
                            ;; Restore state
                            (state.restore session-data lazy? name)
                            (set current-session name)
                            (save-last-session-name name)
                            (vim.notify (.. "Obsessions: loaded session '" name "'")
                                        vim.log.levels.INFO)
                            true))))))))))

(fn M.create [name]
  "Create a new session with the given name. Opens a terminal buffer.
   Returns true on success, (nil, err) on failure."
  (let [(valid? verr) (validate-name name)]
    (if (not valid?)
        (values nil verr)
        (if (M.exists name)
            (values nil (.. "session '" name "' already exists"))
            (let [cfg (config.get)]
              ;; Close current session if any
              (when current-session
                (M.save)
                (lock.release-session (session-path current-session)))
              ;; Clear the editor while preserving live terminals from the
              ;; previous session in the background.
              (state.clear)
              ;; Open initial terminal
              (state.open-new-session-terminal cfg.new-session-layout
                                               cfg.new-session-terminal-height
                                               cfg.new-session-terminal-width)
              ;; Set as current and save
              (set current-session name)
              (M.save name))))))

(fn M.delete [name callback]
  "Delete a session after user confirmation.
   `callback` receives (true) on success or (nil, err) on failure/cancel."
  (let [cb (or callback (fn []))]
    (if (not (M.exists name))
        (cb nil (.. "session '" name "' does not exist"))
        (let [choice (vim.fn.confirm (.. "Delete session '" name "'?")
                                     "&Yes\n&No" 2 "Question")]
          ;; vim.fn.confirm shows a Y/N prompt; returns 1 for Yes, 2/0 otherwise.
          (if (= choice 1)
                (let [path (session-path name)
                      ;; Release ownership if we own it
                      _ (lock.release-session path)
                      ;; Delete the data file
                      (ok derr) (storage.delete path)]
                  (if ok
                      (do
                        (let [(closed? cerr) (state.close-session-terminals name)]
                          (when (not closed?)
                            (vim.notify (.. "Obsessions: warning - deleted session '"
                                            name
                                            "' but could not close all terminal buffers: "
                                            (or cerr "unknown"))
                                        vim.log.levels.WARN)))
                        ;; If we deleted the current session, clear it
                        (when (= current-session name)
                          (set current-session nil))
                        (vim.notify (.. "Obsessions: deleted session '" name "'")
                                    vim.log.levels.INFO)
                        (cb true))
                      (cb nil (.. "failed to delete: " (or derr "unknown")))))
                (cb nil "cancelled"))))))

(fn M.rename [old-name new-name]
  "Rename a saved session from `old-name` to `new-name`.
   If the renamed session is the active one, updates the current session.
   Returns true on success, (nil, err) on failure."
  (let [(valid-old? oerr) (validate-name old-name)
        (valid-new? nerr) (validate-name new-name)]
    (if (not valid-old?)
        (values nil oerr)
        (not valid-new?)
        (values nil nerr)
        (= old-name new-name)
        (values nil "new name is the same as the current name")
        (not (M.exists old-name))
        (values nil (.. "session '" old-name "' does not exist"))
        (M.exists new-name)
        (values nil (.. "session '" new-name "' already exists"))
        (let [old-path (session-path old-name)
              new-path (session-path new-name)
              was-current? (= current-session old-name)]
          ;; If we currently own this session, release first so the claim check
          ;; below treats us as a non-owner and we can detect *other* owners.
          (when was-current?
            (lock.release-session old-path))
          (let [(claimed? cerr) (lock.claim-session old-path)]
            (if (not claimed?)
                (do
                  (when was-current?
                    (lock.claim-session old-path))
                  (values nil (or cerr "could not claim session for rename")))
                (let [_ (lock.release-session old-path)
                      (_ rerr) (vim.uv.fs_rename old-path new-path)]
                  (if rerr
                      (do
                        (when was-current?
                          (lock.claim-session old-path))
                        (values nil (.. "failed to rename file: " rerr)))
                      (do
                        (pcall vim.uv.fs_unlink (.. old-path ".lock"))
                        (pcall vim.uv.fs_rmdir (.. old-path ".lock.d"))
                        (state.rename-session-terminals old-name new-name)
                        (when was-current?
                          (lock.claim-session new-path)
                          (set current-session new-name)
                          (save-last-session-name new-name))
                        (vim.notify (.. "Obsessions: renamed session '" old-name
                                        "' to '" new-name "'")
                                    vim.log.levels.INFO)
                        true)))))))))

(fn M.switch [name]
  "Save the current session (if any) and load the target session.
   Returns true on success, (nil, err) on failure."
  ;; Save current first
  (when current-session
    (let [(ok err) (M.save)]
      (when (not ok)
        (vim.notify (.. "Obsessions: warning - could not save current session: "
                        (or err "unknown"))
                    vim.log.levels.WARN))))
  ;; Release ownership of current session
  (when current-session
    (lock.release-session (session-path current-session)))
  ;; Load the target
  (M.load name))

(fn M.restore-last []
  "Restore the last active session if configured to do so.
   Returns true if a session was restored, false otherwise."
  (let [cfg (config.get)]
    (if (not cfg.restore-last-session)
        false
        (let [last-name (read-last-session-name)]
          (if (and last-name (M.exists last-name))
              (let [(ok _) (M.load last-name)]
                (or ok false))
              false)))))

M

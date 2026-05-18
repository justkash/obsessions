;; obsessions.nvim - init module
;; Plugin entry point: setup(), public API, and VimEnter restore hook.

(local M {})
(local config-mod (require :obsessions.config))
(local session (require :obsessions.session))
(local autosave (require :obsessions.autosave))
(local picker (require :obsessions.picker))
(local state (require :obsessions.state))

(var setup-done false)

;;; ---------------------------------------------------------------------------
;;; setup
;;; ---------------------------------------------------------------------------

(fn M.setup [opts]
  "Initialise obsessions.nvim with user options.
   Should be called once from the user's Neovim config."
  (if setup-done
      nil
      (do
        ;; Merge config
        (config-mod.setup opts)

        ;; Start autosave (timer + VimLeavePre)
        (autosave.start)

        ;; If configured, restore last session on VimEnter
        (let [cfg (config-mod.get)]
          (when cfg.restore-last-session
            (vim.api.nvim_create_autocmd [:VimEnter]
              {:group (vim.api.nvim_create_augroup :ObsessionsRestore {:clear true})
               :once true
               :nested true
               :callback (fn []
                           ;; Only restore if nvim was started with no file arguments
                           (when (= (vim.fn.argc) 0)
                             (session.restore-last)))})))

        (set setup-done true)
        (vim.api.nvim_exec_autocmds :User {:pattern "ObsessionsSetup"})
        nil)))

;;; ---------------------------------------------------------------------------
;;; Public API (delegates to session module)
;;; ---------------------------------------------------------------------------

(fn M.save [name]
  "Save the current session. If name is nil, saves to the active session."
  (session.save name))

(fn M.load [name]
  "Load a session by name."
  (session.load name))

(fn M.create [name]
  "Create a new session with a terminal buffer."
  (session.create name))

(fn M.delete [name]
  "Delete a session (with confirmation dialog)."
  (session.delete name))

(fn M.rename [old-name new-name]
  "Rename a session from `old-name` to `new-name`."
  (session.rename old-name new-name))

(fn M.switch [name]
  "Save current session and switch to another."
  (if name
      (session.switch name)
      ;; No name given: open picker
      (picker.pick-session {:action :switch})))

(fn M.list []
  "Return a list of all saved sessions."
  (session.list))

(fn M.current []
  "Return the name of the active session, or nil."
  (session.get-current))

(fn M.pick [action]
  "Open the session picker. `action` is 'switch', 'load', or 'delete'."
  (picker.pick-session {:action (or action :switch)}))

M

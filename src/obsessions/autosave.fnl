;; obsessions.nvim - autosave module
;; Periodic autosave via libuv timer + VimLeavePre event hook.

(local M {})
(local config (require :obsessions.config))
(local uv vim.uv)

(var timer nil)
(var augroup nil)

(fn do-autosave []
  "Perform an autosave if there is an active session."
  (let [session (require :obsessions.session)
        current (session.get-current)]
    (when current
      (let [(ok err) (session.save)]
        (when (not ok)
          (vim.notify (.. "Obsessions: autosave failed: " (or err "unknown"))
                      vim.log.levels.WARN))))))

(fn M.start []
  "Start the autosave timer and VimLeavePre hook."
  ;; Stop any existing timer
  (M.stop)

  (let [cfg (config.get)
        interval cfg.autosave-interval]
    ;; Periodic timer
    (when (and interval (> interval 0))
      (set timer (uv.new_timer))
      (let [ms (* interval 1000)]
        (timer:start ms ms
          (vim.schedule_wrap do-autosave))))

    ;; VimLeavePre autocmd for save-on-exit
    (set augroup (vim.api.nvim_create_augroup :ObsessionsAutosave {:clear true}))
    (vim.api.nvim_create_autocmd [:VimLeavePre]
      {:group augroup
       :callback (fn []
                   (do-autosave)
                   ;; Release session ownership on exit
                   (let [session (require :obsessions.session)
                         lock-mod (require :obsessions.lock)
                         current (session.get-current)]
                     (when current
                       (let [cfg* (config.get)
                             path (.. cfg*.storage-path "/" current ".msgpack")]
                         (lock-mod.release-session path)))))})
    nil))

(fn M.stop []
  "Stop the autosave timer and remove autocmds."
  (when timer
    (when (timer:is_active)
      (timer:stop))
    (timer:close)
    (set timer nil))
  (when augroup
    (vim.api.nvim_del_augroup_by_id augroup)
    (set augroup nil)))

M
